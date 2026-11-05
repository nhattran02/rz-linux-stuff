#!/bin/sh
# dts_parse.sh - include order, label resolution and override tracing for a .dts
#
# Usage:
#   dts_parse.sh FILE.dts             summary per file: + new node, ~ override/reopen
#   dts_parse.sh FILE.dts -a          every label -> full node path (file:line)
#   dts_parse.sh FILE.dts -l LABEL    where LABEL is defined, who overrides it,
#                                     and the final property values (last one wins)
#
# Notes:
#   - Only #include "file" found next to the including file is followed.
#   - Assumes #include lines sit at the top of each file (as in the kernel DTS).
#   - Labels are resolved after ALL files are read (same as dtc does).

usage() { echo "Usage: $0 FILE.dts [-a | -l LABEL]" >&2; exit 1; }

[ "$#" -ge 1 ] || usage
dts_file=$1
shift
mode=sum
label=
case "$1" in
    "")  ;;
    -a)  mode=all ;;
    -l)  [ -n "$2" ] || usage; mode=label; label=$2 ;;
    *)   usage ;;
esac

case "$dts_file" in
    *.dts) ;;
    *) echo "Please provide a valid .dts file path" >&2; exit 1 ;;
esac
[ -f "$dts_file" ] || { echo "Please provide a valid .dts file path" >&2; exit 1; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM
: > "$TMP/order"
: > "$TMP/tree"

find_includes() {
    dir=$(dirname "$1")
    awk '
        match($0, /#include[ \t]+"[^"]+"/) {
            s = substr($0, RSTART, RLENGTH)
            sub(/^[^"]*"/, "", s); sub(/"$/, "", s)
            print s
        }
    ' "$1" | while IFS= read -r inc; do
        [ -e "$dir/$inc" ] && printf '%s\n' "$inc"
    done
}

walk() {
    local file indent dir includes inc pad
    file=$1; indent=$2
    dir=$(dirname "$file")
    includes=$(find_includes "$file")
    if [ "$indent" -ge 2 ]; then
        pad=$((indent - 2))
        printf '%*s└─' "$pad" "" >> "$TMP/tree"
    fi
    basename "$file" >> "$TMP/tree"
    for inc in $includes; do
        walk "$dir/$inc" $((indent + 2))
    done
    echo "$file" >> "$TMP/order"      # children first = parse order
}

walk "$dts_file" 0

cat > "$TMP/p.awk" <<'AWK'
function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function sh(f) { sub(/.*\//, "", f); return f }

function add_prop(s,   id) {
    gsub(/[ \t\r]+/, " ", s); s = trim(s)
    if (s == "" || depth < 1) return
    id = idst[depth]; bnp[id]++; bprop[id, bnp[id]] = s
}
function flush_complete(   p, s) {
    while ((p = index(stmt, ";")) > 0) {
        s = substr(stmt, 1, p - 1); stmt = substr(stmt, p + 1)
        add_prop(s)
    }
}
function open_block(h,   name, labs, l, id, par, path, la, n, i) {
    name = h; labs = ""
    while (match(name, /^[A-Za-z_][A-Za-z0-9_]*[ \t]*:[ \t]*/)) {
        l = substr(name, 1, RLENGTH); sub(/[ \t]*:[ \t]*$/, "", l)
        labs = labs (labs == "" ? "" : ",") l
        name = substr(name, RLENGTH + 1)
    }
    name = trim(name)
    depth++
    id = ++nb
    bfile[id] = FILENAME; bline[id] = FNR; bname[id] = name
    blabels[id] = labs; bdepth[id] = depth
    par = (depth > 1) ? idst[depth - 1] : 0
    bparent[id] = par
    if (depth == 1)            path = name
    else if (bpath[par] == "/") path = "/" name
    else                        path = bpath[par] "/" name
    bpath[id] = path
    idst[depth] = id
    if (labs != "") {
        n = split(labs, la, ",")
        for (i = 1; i <= n; i++) if (!(la[i] in labelblk)) labelblk[la[i]] = id
    }
}
# Resolve "&label/child" to the real path of the node that label names
function rpath(id,   p, i, ref, rest, b) {
    if (id in rp) return rp[id]
    p = bpath[id]
    if (substr(p, 1, 1) == "&") {
        i = index(p, "/")
        if (i) { ref = substr(p, 2, i - 2); rest = substr(p, i) }
        else   { ref = substr(p, 2);        rest = "" }
        if ((ref in labelblk) && labelblk[ref] != id && !(labelblk[ref] in busy)) {
            busy[id] = 1
            b = rpath(labelblk[ref])
            delete busy[id]
            p = b rest
        }
    }
    rp[id] = p
    return p
}

FNR == 1 { nf++; ford[nf] = FILENAME; fstart[nf] = nb + 1; depth = 0; incom = 0; stmt = "" }

/^[ \t]*#(include|define|undef|ifdef|ifndef|if|else|elif|endif)([ \t"<]|$)/ { next }

{
    # 1) strip comments (also multi-line)
    line = $0; out = ""
    while (line != "") {
        if (incom) {
            p = index(line, "*/")
            if (!p) { line = ""; break }
            line = substr(line, p + 2); incom = 0
        } else {
            p = index(line, "/*"); q = index(line, "//")
            if (q && (!p || q < p)) { out = out substr(line, 1, q - 1); line = ""; break }
            if (!p) { out = out line; line = ""; break }
            out = out substr(line, 1, p - 1) " "
            line = substr(line, p + 2); incom = 1
        }
    }
    # 2) walk the braces
    rest = out
    while (match(rest, /[{}]/)) {
        ch = substr(rest, RSTART, 1)
        stmt = stmt " " substr(rest, 1, RSTART - 1)
        rest = substr(rest, RSTART + 1)
        flush_complete()
        if (ch == "{") { open_block(trim(stmt)); stmt = "" }
        else           { stmt = ""; if (depth > 0) depth-- }
    }
    stmt = stmt " " rest
    flush_complete()
}

END {
    fstart[nf + 1] = nb + 1
    for (id = 1; id <= nb; id++) rpath(id)

    if (mode == "all") {
        for (id = 1; id <= nb; id++) {
            if (blabels[id] == "") continue
            n = split(blabels[id], la, ",")
            for (i = 1; i <= n; i++)
                printf "%-26s %s   (%s:%d)\n", la[i], rp[id], sh(bfile[id]), bline[id]
        }
        exit
    }

    if (mode == "label") {
        if (!(want in labelblk)) { print "Label '" want "' is not defined in any parsed file."; exit }
        d = labelblk[want]; target = rp[d]
        printf "%s -> %s\n\n", want, target
        for (id = 1; id <= nb; id++) {
            if (rp[id] != target) continue
            if (id == d)                         kind = "definition"
            else if (bdepth[id] == 1)            kind = "override via " bname[id]
            else                                 kind = "reopened"
            printf "%s:%d  [%s]\n", sh(bfile[id]), bline[id], kind
            for (k = 1; k <= bnp[id] + 0; k++) {
                s = bprop[id, k]
                printf "    %s;\n", s
                if (s ~ /^\/delete-property\//) { nm = trim(substr(s, 18)); eff[nm] = ""; if (!(nm in pos)) { pos[nm] = ++np; pname[np] = nm } continue }
                nm = s; i = index(s, "="); if (i) nm = trim(substr(s, 1, i - 1))
                if (!(nm in pos)) { pos[nm] = ++np; pname[np] = nm }
                eff[nm] = s
            }
        }
        print "\nFinal values (last one wins):"
        for (k = 1; k <= np; k++) if (eff[pname[k]] != "") printf "    %s;\n", eff[pname[k]]
        exit
    }

    # summary
    for (f = 1; f <= nf; f++) {
        print sh(ford[f])
        for (id = fstart[f]; id < fstart[f + 1]; id++) {
            p = rp[id]
            if (bdepth[id] == 1 && bname[id] == "/") { seen[p] = 1; continue }
            if (bdepth[id] == 1) {
                printf "  ~ %-36s %d props\n", bname[id], bnp[id] + 0
            } else if (p in seen) {
                printf "  ~ %-36s reopened, %d props\n", bname[id], bnp[id] + 0
            } else {
                isnew[id] = 1
                if (!isnew[bparent[id]]) printf "  + %-36s under %s\n", bname[id], bpath[bparent[id]]
            }
            # an override (&label) is not a definition, so it must not mark the node as seen
            if (bdepth[id] != 1) seen[p] = 1
        }
    }
}
AWK

files=$(cat "$TMP/order")
case "$mode" in
    sum)
        echo "Include order"; echo "-------------"
        cat "$TMP/tree"
        echo
        echo "Parse order  (+ new node, ~ override/reopen)"
        echo "--------------------------------------------"
        ;;
esac
# shellcheck disable=SC2086
awk -v mode="$mode" -v want="$label" -f "$TMP/p.awk" $files
