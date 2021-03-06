#!/bin/sh

CWD=$(pwd)
TROOT="$CWD/_tests"
PWD=$(cd $(dirname $0); pwd;)
PATH=$PWD:$PATH

mkrepo() {(
  # Create repo $1 and the corrsponding bare-bone repor $1.git
  set -e -x
  local name="$1"
  test -d "$TD"
  D="$TD/$name"
  DB="$TD/$name.git"

  # Remote
  mkdir -p "$DB"
  cd -P "$DB"
  git init --bare

  # The repo
  mkdir -p "$D"
  cd -P "$D"
  git init
  (
  for l in `seq 0 1 3` ; do
    if test "$l" != "0" ; then
      mkdir "lvl$l"
      cd -P "lvl$l"
    fi
    for i in `seq 1 1 5` ; do
      echo "File$i of $name" >file${i}
      git add file${i}
    done
  done
  )
  git commit -m 'Initial commit'
  git remote add origin "$DB"
  git push origin master
  git branch --set-upstream-to=origin/master
)}

mkrepoS() {(
  set -e -x
  local base=$1
  local subm=$2
  local path=$3
  test -d "$TD"
  mkrepo "$subm"

  cd -P "$TD/$base"
  mkdir -p $(dirname "$path")
  git submodule add "$TD/$subm.git" "$path"
  git commit -m "Add submodule $subm"
  git push
)}

clone() {(
  set -e -x
  local base=$1
  local copy=$2
  test -d "$TD"

  cd -P "$TD"
  git clone --recursive "$base" "$copy"
)}

modify() {(
  set -e -x
  cd -P "$TD/$1"
  test -f "$2"
  echo "Modified" >> "$2"
)}

powercommit() {(
  set -e -x
  cd -P "$TD/$1"
  shift
  git powercommit --debug --log=$TD/powercommit.log "$@"
)}

test1() {(
  set -e -x
  export TD="$TROOT/test1"
  mkdir -p "$TD"
  mkrepo repo1
  mkrepoS repo1 sub1 modules/sub1
  mkrepoS repo1 sub2 modules/sub2

  modify repo1 'file1'
  modify repo1 'lvl1/file1'
  modify repo1 'lvl1/lvl2/file1'
  modify repo1 'lvl1/lvl2/file2'
  modify repo1 'lvl1/lvl2/lvl3/file1'
  modify repo1 'lvl1/lvl2/lvl3/file2'
  modify repo1 'lvl1/lvl2/lvl3/file3'

  cd -P "$TD/repo1"
  powercommit repo1
  git status --porcelain
  git log --oneline | grep 'Update lvl1$'
  git log --oneline | grep 'Update lvl1/lvl2$'
  git log --oneline | grep 'Update lvl1/lvl2/lvl3$'
)}

test2() {(
  set -e -x
  export TD="$TROOT/test2"
  mkdir -p "$TD"
  mkrepo repo1
  mkrepoS repo1 sub1 modules/sub1
  mkrepoS repo1 sub2 modules/sub2

  modify repo1 'lvl1/file1'
  modify repo1 'modules/sub1/lvl1/file1'
  modify repo1 'modules/sub2/lvl1/file1'

  cd -P "$TD/repo1"
  powercommit repo1
  git status --porcelain
  git log --oneline | grep 'Bump'
)}

test_log() {(
  set -e -x
  export TD="$TROOT/test_log"
  mkdir -p "$TD"
  mkrepo repo1
  mkrepoS repo1 sub1 modules/sub1
  modify repo1 'lvl1/file1'
  modify repo1 'modules/sub1/lvl1/file1'
  cd -P "$TD/repo1"
  powercommit repo1 --debug --log=$TD/powercommit2.log
  cat $TD/powercommit2.log | grep '^Creating a backup'
  cat $TD/powercommit2.log | grep '^  Creating a backup'
)}

test_detached_head() {(
  set -e -x
  export TD="$TROOT/test_detached_head"
  mkdir -p "$TD"
  mkrepo repo1
  mkrepoS repo1 sub1 modules/sub1
  modify sub1 'lvl1/file1'
  (cd "$TD/sub1" && git add --all && git commit -m 'Modified' && git push origin; )
  clone repo1.git repo1c
  # (cd "$TD/repo1c/modules/sub1" && git pull ;)
  # (cd "$TD/repo1c" && git add modules/sub1 && git commit -m 'Bump' && git push ;)

  # git pull --rebase
  modify repo1c 'lvl1/file1'
  modify repo1c 'modules/sub1/file2'
  powercommit repo1c && exit 1 || ( echo "(Intended failure!)" && true)
  (cd "$TD/repo1c/modules/sub1" && git checkout master ; )
  powercommit repo1c
)}

test_untracked() {(
  set -e -x
  export TD="$TROOT/test_untracked"
  mkdir -p "$TD"
  mkrepo repo1
  mkrepoS repo1 sub1 modules/sub1
  cd -P "$TD/repo1"
  echo Foo>fileA
  echo Bar>$TD/repo1/modules/sub1/fileB
  modify repo1 'lvl1/file1'
  modify repo1 'modules/sub1/lvl1/file1'
  powercommit repo1 --debug
  cat $TD/powercommit.log | grep "Untracked fileA"
  cat $TD/powercommit.log | grep "Untracked modules/sub1/fileB"
)}

test_screencap() {(
  set -e -x
  export TD="$TROOT/test_screencap"
  mkdir -p "$TD"
  mkrepo repo1
  mkrepoS repo1 sub1 modules/sub1
  mkrepoS repo1 sub2 modules/sub2

  modify repo1 'lvl1/file1'
  modify repo1 'modules/sub1/lvl1/file1'
  modify repo1 'modules/sub2/lvl1/file1'
  echo Foo>$TD/repo1/fileA
  echo Bar>$TD/repo1/modules/sub1/fileB
)}

test_always_gpr() {(
  set -e -x
  export TD="$TROOT/test_always_gpr"
  mkdir -p "$TD"
  mkrepo repo1
  mkrepoS repo1 sub1 modules/sub1
  modify sub1 'lvl1/file1'
  powercommit sub1
  cat $TD/sub1/lvl1/file1 | grep "Modified"

  powercommit repo1 --debug
  # cd -P "$TD/repo1"
  # git submodule foreach git pull
  cat $TD/repo1/modules/sub1/lvl1/file1 | grep "Modified"
)}

set -e -x
rm -rf "$TROOT" || true

# test_screencap
test1
test2
test_log
test_detached_head
test_untracked
test_always_gpr
echo OK

