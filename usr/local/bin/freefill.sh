#!/bin/bash

dir=""
while [ "$1" ]; do
  a="$1"; shift
  if [ "$a" = "-q" ]; then
    QUIET=1
    continue
  fi
  if [ "$a" ] && [ -z "$dir" ]; then
    dir="$a"
    continue
  fi
done

if [ -z "$dir" ]; then
  dir=$(/bin/pwd)
fi

if [ ! -d "$dir" ]; then
  echo "$dir isn't a directory"
  exit 1
fi
export dir
cleanexit() {
 rm -vrf "${dir}"/fill.*
 exit 0
}
freespace() {
 stat -f --printf '%a\n' $dir
}
trap cleanexit 1 2 3 6 11 13 14 15 17 30
tmpdir="${dir}/fill.$$"
mkdir "$tmpdir" || exit 2
c=0
while :; do
  dd if=/dev/zero of=${tmpdir}/z.${c} bs=1024k count=100
  if [ "$?" -gt 0 ]; then
    cleanexit
  fi
  f=$(freespace)
  echo "freespace: $f blocks"
  if [ "$f" -lt 40000 ]; then
    cleanexit
  fi
  c=$((c+1))
done
