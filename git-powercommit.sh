#!/bin/sh

errexit() {
  echo "$@" >&2
  exit 1
}

which git 2>&1 >/dev/null || \
  errexit "\`git\` is not installed"

BNAME=powercommit
RECURSIVE=`echo "$@" | grep -q -E '\-\-recursive' && echo y || echo n`
DRYRUN=`echo "$@" | grep -q -E '\-\-dry-run' && echo y || echo n`
if test -z "$INDENT" ; then
  INDENT=""
fi

run() {
  if test "$DRYRUN" = "y" ; then
    echo "$INDENT$@"
  else
    "$@"
  fi
}

dirname2() {
  # Print the dirname of a file if it is not empty. Otherwize print the file.
  local dn=$(dirname "$1")
  if test "$dn" = "." ; then
    echo "$1"
  else
    echo "$dn"
  fi
}

mapchanges() {(
  # Scan git repo, call a `filter` to calculate the paths of interest. After
  # that sort these paths and call `commiter` for every such path.
  #
  # FIXME: currently ignores failures in filter or commiter, if any.
  set -e -x
  local filter="$1"
  local commiter="$2"
  git status --no-renames --porcelain=v2 | \
  while read N XY sub mH mI mW hH hI path ; do
    echo "||| $N $XY $sub $mH $mI $mW $hH $hI $path" >&2
    $filter $N $XY $sub $mH $mI $mW $hH $hI "$path"
  done | \
  sort -u --reverse | \
  while read path; do
    $commiter "$path"
  done
)}

filter_normal() {
  # Inputs are according to `git status --porcelain=v2` spec. The function
  # filters normal changes, i.e. not renames and submodules
  local XY="$2"
  local subm="$3"
  shift 8; local path="$1"
  case "$XY" in
    .M|M.|MM)
      case "$subm" in
        N...) dirname2 "$path" ;;
        *) ;;
      esac ;;
    *) ;;
  esac
}

commit_normal() {
  # Commit changes assuming that the path points to normal file/folder
  local path="$1"
  run git add -u -- "$path"
  run git commit -m "Update $path"
}

filter_subm() {
  # Inputs are according to `git status --porcelain=v2` spec. The function
  # filters submodules which has changed commits.
  local sub="$3"; shift 8; local path="$1"
  case "$sub" in
    SC??) echo "$path" ;;
    *) ;;
  esac
}

commit_subm() {
  # Commit changes assuming that the path points to a submodule
  local path="$1"
  run git add -u -- "$path"
  run git commit -m "Bump $path"
}

{ git branch -a; git stash list; } | grep -q "$BNAME" && \
  errexit "Looks like the last call to powercommit failed." \
          "Consider making some investigation, then remove the branch" \
          "\`$BANME\` and the stash of the same name. Typical repair " \
          "commands are:" $'\n\n\t' \
          "git reset --hard \"$BNAME\"; git stash pop;" \
          "git branch -D \"$BNAME\""

set -ex
cd -P $(git rev-parse --show-toplevel)
git status --porcelain | grep -v '^??' | grep -q '^[^\s]*' || exit 0
run git branch "$BNAME"
run git stash push -m "$BNAME"
run git pull --rebase
run git stash apply
if test "$RECURSIVE" = "y" ; then
  for s in `git submodule status | awk '{print $2}'` ; do
    echo "Entering \"$s\""
    ( cd -P "$s" && INDENT="$INDENT  " $0 "$@" ; )
    echo "Exiting \"$s\""
  done
  mapchanges filter_subm commit_subm
fi

mapchanges filter_normal commit_normal

run git push
run git branch --delete "$BNAME"
run git stash drop


