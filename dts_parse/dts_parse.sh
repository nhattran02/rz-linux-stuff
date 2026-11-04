#!/bin/sh
# dts_order.sh - show #include order and node order of a .dts file
# Usage: ./dts_order.sh <path_to_dts_file>

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path_to_dts_file>"
    exit 1
fi

dts_file=$1

case "$dts_file" in
    *.dts) ;;
    *) echo "Please provide a valid .dts file path"; exit 1 ;;
esac

if [ ! -f "$dts_file" ]; then
    echo "Please provide a valid .dts file path"
    exit 1
fi

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM
: > "$TMP/names"

# Print the name of each #include "file" that exists next to the given file
find_includes() {
    dir=$(dirname "$1")
    awk '
        match($0, /#include[ \t]+"[^"]+"/) {
            s = substr($0, RSTART, RLENGTH)
            sub(/^[^"]*"/, "", s)
            sub(/"$/, "", s)
            print s
        }
    ' "$1" | while IFS= read -r inc; do
        [ -e "$dir/$inc" ] && printf '%s\n' "$inc"
    done
}

# Print names of override nodes:  &name {
find_nodes_modified() {
    awk '
        match($0, /&[A-Za-z0-9_]+[ \t]*[{]/) {
            s = substr($0, RSTART + 1, RLENGTH - 1)
            sub(/[ \t]*[{]$/, "", s)
            print s
        }
    ' "$1"
}

# Print names of new nodes (depth 2, lines without &)
find_nodes_new() {
    awk '
        {
            line = $0
            if (index(line, "{")) lvl++
            if (index(line, "}")) lvl--
            if (index(line, "&")) next
            if (index(line, "{") && lvl == 2) {
                gsub(/[{]/, "", line)
                p = index(line, ":")
                if (p) line = substr(line, 1, p - 1)
                sub(/^[ \t\r]+/, "", line)
                sub(/[ \t\r]+$/, "", line)
                print line
            }
        }
    ' "$1"
}

# Read names from stdin, format 4 per line, padded to a fixed width
# $1 = prefix ("&" or ""), $2 = pad width
format_nodes() {
    awk -v prefix="$1" -v width="$2" '
        BEGIN { out = "\n    "; count = 0 }
        {
            if (count == 4) { out = out "\n    "; count = 0 }
            count++
            out = out prefix $0
            sp = width - length($0)
            if (sp > 1) { for (i = 0; i < sp; i++) out = out " " }
            else        { out = out " " }
        }
        END { printf "%s", out }
    '
}

process_file() {
    local file_path indent directory includes inc idx pad
    file_path=$1
    indent=$2
    directory=$(dirname "$file_path")
    includes=$(find_includes "$file_path")

    # Tree prefix
    if [ "$indent" -ge 2 ]; then
        pad=$((indent - 2))
        printf '%*s└─' "$pad" ""
    fi
    basename "$file_path"

    for inc in $includes; do
        process_file "$directory/$inc" $((indent + 2))
    done

    # Children are stored first, so the list is in "parse order"
    idx=$(($(wc -l < "$TMP/names") + 1))
    basename "$file_path" >> "$TMP/names"
    find_nodes_new "$file_path"      | format_nodes ""  21 > "$TMP/new.$idx"
    find_nodes_modified "$file_path" | format_nodes "&"  20 > "$TMP/mod.$idx"
}

echo "-----------------------------------"
echo "Include order"
echo "-----------------------------------"
echo " "

process_file "$dts_file" 0

echo " "
echo " "
echo "-------------------------------------------------------------"
echo "Order of how files and nodes are parsed."
echo "-------------------------------------------------------------"
echo "Remember, the #include is at the top of the files and the nodes come after. So that means the last file"
echo "that gets included will have the nodes that get processed first. This is important to know when you have"
echo "multiple files that modify the same node."
echo " "

count=$(wc -l < "$TMP/names")
i=1
while [ "$i" -le "$count" ]; do
    sed -n "${i}p" "$TMP/names"
    printf '  nodes new:'
    cat "$TMP/new.$i"
    echo " "
    printf '  nodes override:'
    cat "$TMP/mod.$i"
    echo " "
    echo " "
    i=$((i + 1))
done
