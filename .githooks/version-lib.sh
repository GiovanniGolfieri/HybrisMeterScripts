#!/bin/bash
# --------------------------------------------------------------------------------------------------------------------
# Shared helpers for the platform version (MAJOR.MINOR.BUILD), sourced by .githooks/pre-commit and ./version.sh
#   - one VERSION file at the root of each repository: DB, BE, FE, INSTALLERAPP, USERAPP
#   - BUILD is a single counter across all repositories: it only grows (it is the Android versionCode)
#   - MINOR (and MAJOR) are raised by hand with ./version.sh set
# --------------------------------------------------------------------------------------------------------------------

HM_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
HM_REPOS=(DB BE FE INSTALLERAPP USERAPP)
HM_VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

# prints the version stored in a file, or nothing
hm_read_file() {
  [ -f "$1" ] || return 0
  local v
  v="$(tr -d '[:space:]' < "$1")"
  [[ "$v" =~ $HM_VERSION_RE ]] && echo "$v"
}

# prints "MAJOR MINOR BUILD"
hm_split() { echo "$1" | tr '.' ' '; }

# highest version over the working-tree VERSION files of all repositories (optionally excluding one)
# prints "MAJOR MINOR MAXBUILD": MAJOR.MINOR of the highest MAJOR.MINOR, MAXBUILD = highest BUILD anywhere
hm_max() {
  local skip="$1" maj=0 min=0 bld=0 r v a b c
  for r in "${HM_REPOS[@]}"; do
    [ "$r" = "$skip" ] && continue
    v="$(hm_read_file "$HM_ROOT/$r/VERSION")"
    [ -z "$v" ] && continue
    read -r a b c <<< "$(hm_split "$v")"
    if (( a > maj || (a == maj && b > min) )); then maj=$a; min=$b; fi
    (( c > bld )) && bld=$c
  done
  echo "$maj $min $bld"
}
