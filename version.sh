#!/bin/bash
# --------------------------------------------------------------------------------------------------------------------
# Platform version (DB, BE, FE, INSTALLERAPP, USERAPP share one number: MAJOR.MINOR.BUILD, "0." until the first official release)
#
#   ./version.sh                  current version of each repository and the next automatic one
#   ./version.sh set 0.8          next commit of every repository: 0.8.<next build>  (same number everywhere;
#                                 a new MINOR also starts over DB/SRC/þ-deploy/changesLIST.txt via reset.sh)
#   ./version.sh set 0.8.300      next commit of every repository: exactly 0.8.300   (build may only grow)
#   ./version.sh set 0.8 FE       the same, only for the listed repositories
#   ./version.sh install          activate the shared git hook in every repository
#
# Without "set" every commit raises BUILD by one automatically (.githooks/pre-commit).
# A "set" only edits the VERSION files: commit them (alone or with other changes) to make it effective.
# --------------------------------------------------------------------------------------------------------------------
source "$(dirname "$(readlink -f "$0")")/.githooks/version-lib.sh"

cmd="${1:-show}"
case "$cmd" in
  show)
    for r in "${HM_REPOS[@]}"; do
      v="$(hm_read_file "$HM_ROOT/$r/VERSION")"
      head_v="$(git -C "$HM_ROOT/$r" show HEAD:VERSION 2>/dev/null | tr -d '[:space:]')"
      note=""
      [ -n "$v" ] && [ "$v" != "$head_v" ] && note="  (impostata, in attesa di commit)"
      hook="$(git -C "$HM_ROOT/$r" config core.hooksPath)"
      [ -z "$hook" ] && note="$note  (hook non attivo)"
      printf "  %-12s %s%s\n" "$r" "${v:--}" "$note"
    done
    read -r maj min maxb <<< "$(hm_max "")"
    echo "  prossimo commit automatico: $maj.$min.$((maxb + 1))"
    ;;

  set)
    target="$2"; shift 2
    repos=("$@"); [ ${#repos[@]} -eq 0 ] && repos=("${HM_REPOS[@]}")
    read -r _ _ maxb <<< "$(hm_max "")"
    if [[ "$target" =~ ^[0-9]+\.[0-9]+$ ]]; then
      new="$target.$((maxb + 1))"
    elif [[ "$target" =~ $HM_VERSION_RE ]]; then
      read -r _ _ b <<< "$(hm_split "$target")"
      if (( b <= maxb )); then
        echo "La compilazione deve crescere: $b non è maggiore di $maxb." >&2; exit 1
      fi
      new="$target"
    else
      echo "Uso: ./version.sh set MAGGIORE.MINORE[.COMPILAZIONE] [repository...]" >&2; exit 1
    fi
    read -r cmaj cmin _ <<< "$(hm_max "")"
    for r in "${repos[@]}"; do
      [ -d "$HM_ROOT/$r/.git" ] || { echo "Repository sconosciuto: $r" >&2; exit 1; }
      echo "$new" > "$HM_ROOT/$r/VERSION"
      echo "  $r -> $new"
    done
    # new MAJOR.MINOR: the DB changes list (and the empty alter files) start over
    read -r nmaj nmin _ <<< "$(hm_split "$new")"
    if [ "$nmaj.$nmin" != "$cmaj.$cmin" ] && [[ " ${repos[*]} " == *" DB "* ]]; then
      "$HM_ROOT/DB/SRC/þ-deploy/reset.sh" "$nmaj.$nmin" Y
    fi
    echo "Versione impostata: diventa effettiva con il prossimo commit di ciascun repository."
    ;;

  install)
    for r in "${HM_REPOS[@]}"; do
      git -C "$HM_ROOT/$r" config core.hooksPath "$HM_ROOT/.githooks"
      echo "  $r: hook attivo"
    done
    ;;

  *)
    sed -n '2,14p' "$0"; exit 1 ;;
esac
