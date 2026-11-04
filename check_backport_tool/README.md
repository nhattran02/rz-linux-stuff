# bpcheck.sh - Backport Check Tool
 
## Purpose
 
`bpcheck.sh` helps you backport commits from upstream to a local branch. It works in any git repository, and it was written for Linux kernel backports (for example, mainline to CIP).
 
It answers these questions:
 
- Which upstream commits changed these files between two versions? (`list`)
- Does my local branch already have this commit? (`check`)
- When did this commit land (mainline release, linux-next, stable), and should I port it? (`since`)
It does not only compare commit hashes. It compares the **patch-id** (the content of the diff), so it can find a commit even when the hash is different (for example, after a cherry-pick).
 
## Requirements
 
- `bash` 4 or newer (it uses associative arrays)
- `git`, `awk`, `sed`, `sort -V`, `md5sum`, `mktemp`
- Network access the first time you use a remote (the tool fetches it for you). Use `-N` to work offline.
## Install
 
```sh
chmod +x bpcheck.sh
# optional: put it in your PATH
cp bpcheck.sh ~/bin/
```
 
Run it inside a git repository (your local kernel tree).
 
## Quick start
 
```sh
# 1. List upstream commits for one driver, and save the list as "sci"
./bpcheck.sh list -s sci mainline/v6.12..mainline/master -- drivers/tty/serial/sh-sci.c
 
# 2. Check which commits your branch still does not have, and keep only those
./bpcheck.sh check -L sci -m -s sci-todo
 
# 3. For the missing commits: when did they land, and should you port them?
./bpcheck.sh since -S -L sci-todo
```
 
## Usage
 
```
bpcheck.sh <command> [options] [args] [-- <path>...]
```
 
### Commands
 
| Command | Description |
|---|---|
| `list <range>...` | List commits in a range, e.g. `mainline/v6.12..mainline/master` |
| `check <commit\|range\|->` | Check commits against the local branch. `-` reads shas from stdin |
| `check -L <list>` | Check every commit of a saved list |
| `since <commit\|range\|->` | Show when a commit landed and whether to port it (also works with `-L <list>`) |
| `pid <commit>...` | Print the patch-id of commits |
| `lists` | Show saved lists |
| `show <list>` | Print a saved list |
| `rm <list>...` | Delete saved lists |
| `fetch <remote>[/<ref>]...` | Fetch a branch or tag (or the whole remote) |
| `remotes` | Show configured remotes and built-in aliases |
| `help` | Show the help text |
 
### Options
 
| Option | Description |
|---|---|
| `-- <path>...` | Limit to these files, directories or globs. Quote globs: `'dir/renesas,*'` |
| `-l <ref>` | Local branch to compare against (default: `HEAD`) |
| `-s <name>` | `list`: save the result as `<name>`. `check`: save the commits that are **not** HAVE as `<name>` |
| `-a` | With `-s`: append to an existing list instead of replacing it |
| `-L <name>` | Use a saved list. Its saved paths are used unless you give `--` |
| `-m` | `check`: hide commits that are already present (HAVE) |
| `-c` | CSV output (`check`, `list`, `since`) |
| `-r` | `check`: add a RELEASE column (first mainline tag, or `next-YYYYMMDD`) |
| `-S` | `since`: also look in `stable/linux-X.Y.y` (X.Y is read from the Makefile of the local branch). Fetches that branch and its tags if missing |
| `-F` | Always fetch remote refs before use (refresh) |
| `-N` | Never fetch (offline) |
 
## Refs and remotes
 
- `<remote>/<name>` is fetched automatically if it is missing. `<name>` can be a **branch or a tag**.
- Plain local refs (`HEAD`, `v6.12`, `my-branch`, a sha) work as usual.
- These remote aliases are built in and are added automatically:
| Alias | Repository |
|---|---|
| `mainline` | Linus' tree (`torvalds/linux.git`) |
| `next` | linux-next |
| `stable` | stable tree (`stable/linux.git`) |
 
- You can add your own remote alias:
```sh
git config bpcheck.remote.<name> <url>
```
 
Run `./bpcheck.sh remotes` to see all remotes and aliases.
 
> The first fetch of a kernel tree can take a long time.
 
## Check status
 
Each commit gets one status:
 
| Status | Meaning |
|---|---|
| `HAVE` | The same diff (patch-id) exists locally, or the commit is an ancestor of the local branch |
| `TAG` | A local commit says `commit <sha> upstream`, `[ Upstream commit <sha> ]` or `cherry picked from commit <sha>`, but the diff is different |
| `SUBJ` | A local commit has the same subject, but the diff is different. Compare with `git range-diff` |
| `MISSING` | Not found. This is a **backport candidate** |
| `UNKNOWN` | The commit object is not available locally |
 
### FIX column
 
The FIX column is based on the `Fixes:` tag of the commit:
 
| Value | Meaning |
|---|---|
| `yes` | The fixed commit **is** in the local branch, so you are affected |
| `n/a` | The fixed commit is not in the local branch |
| `?` | The fixed commit object is not available locally |
| `-` | This commit is not a fix |
 
### How patch-ids are computed
 
- Without `-- <path>`, each commit is compared over the files it touches.
- With `-- <path>`, patch-ids are computed only over those paths (on both sides).
## The `since` command
 
For each commit, `since` prints:
 
- **mainline**: the first release tag that contains it (for example `v6.13-rc1`). If it is not released yet, it shows the first `next-*` tag.
- **fix**: the FIX value (see above).
- **stable**: with `-S`, the stable backport and the first stable tag (for example `v6.12.60`).
- **local**: the status of the commit in your local branch, and the kernel version of the local branch.
- **verdict**: a suggestion, for example:
  - already in the local branch
  - only in linux-next, not released yet
  - in a release older than or equal to the local version (it should already be in the base)
  - in stable: it will come with the next stable/CIP update
  - newer than the local version: backport candidate, check API and dependencies
  - backported with changes: compare with `range-diff`
## Saved lists
 
Saved lists let you work in steps (list, then check, then since) without typing the same range again.
 
- Lists are stored in `$(git rev-parse --git-common-dir)/bpcheck/`. Change the folder with the `BPCHECK_DIR` environment variable.
- A list file contains the commits (sha and subject), and the paths that were used.
- List names can use letters, digits, `.`, `_` and `-`.
```sh
./bpcheck.sh lists          # show all lists
./bpcheck.sh show sci       # print one list
./bpcheck.sh rm sci         # delete a list
```
 
## More examples
 
```sh
# Check two commits
./bpcheck.sh check c3ca8a0aac83 92b1ea22454b
 
# Check with the release where each commit landed
./bpcheck.sh check -r -L sci -m
 
# Compare against another local branch, only for one file
./bpcheck.sh check -l g3s/dev mainline/master..next/master -- drivers/watchdog/rzg2l_wdt.c
 
# List recent stable commits for a directory
./bpcheck.sh list stable/linux-6.12.y~50..stable/linux-6.12.y -- drivers/tty/serial/
 
# Read commits from stdin
git log --format=%H --grep=sh-sci v6.12..v6.18 | ./bpcheck.sh check -
 
# CSV output for a spreadsheet
./bpcheck.sh check -c -r -L sci > sci.csv
```
 
## Typical backport workflow
 
1. `list -s <name> <range> -- <path>`: collect upstream commits for your driver.
2. `check -L <name> -m -s <name>-todo`: keep only what is not in your branch yet.
3. `since -S -L <name>-todo`: see which ones are fixes, and which ones will come from stable anyway.
4. Backport the commits you need. For `TAG` and `SUBJ` commits, use `git range-diff` to see what is different.
5. Run `check -L <name>-todo -m` again to confirm that the commits are now HAVE.
## Notes
 
- Merge commits are ignored.
- `check -L` and `since -L` use the paths saved in the list, unless you give `-- <path>`.
- Colors are shown only when the output is a terminal. They are off for `-c` and for pipes.
- Messages and the summary line (for example `total=... HAVE=... MISSING=...`) go to stderr, so they do not break the CSV output.
