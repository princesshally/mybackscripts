#!/bin/bash
# PFLOCAL
# PFDISTRIB
# file-snob (smallest newest oldest biggest)
# Finds 5 smallest, biggest, oldest, newest files in a particular (or current) directory
export LC_ALL=C
export LANG=C
DEPTH=1; export DEPTH
snob() {
  TMP=$(mktemp)
  T2=$(mktemp)
  dir=$(echo "$1" | sed -e 's/\/\/*/\//g')
  find "$dir" -maxdepth $DEPTH -xdev -type f -printf '%TY%Tm%Td\t%s\t%P\n' | egrep -vi 'tmp|etl_' > $TMP

  if [ "$short" ]; then
    CNT=$(cat $TMP | wc -l)
    cut -f 1 < $TMP | sort -n > $T2
    FL=$(cat $T2 | wc -l)
    I1=$((FL/5))
    I5=$((FL/2))
    I9=$((FL-I1))
    P0=$(head -1 $T2)
    P1=$(head -$I1 $T2 | tail -1)
    P5=$(head -$I5 $T2 | tail -1)
    P9=$(head -$I9 $T2 | tail -1)
    P10=$(tail -n -1 $T2)
    R1="${P0}-${P1}-${P5}-${P9}-${P10}"
  
    cut -f 2 < $TMP | sort -n > $T2
    P0=$(head -1 $T2)
    P1=$(head -$I1 $T2 | tail -1)
    P5=$(head -$I5 $T2 | tail -1)
    PAVG=$(cat $T2| perl -e '$c=0;while(<>){$c++;$a+=$_}print int($a/$c)."\n"')
    P9=$(head -$I9 $T2 | tail -1)
    P10=$(tail -n -1 $T2)
    R2="${P0}-${P1}-${PAVG}-${P9}-${P10}"
    if [ "$cksum" ]; then
      MD=$(echo -n "${CNT}+${R1}+${R2}" | md5sum | cut -c 1-7)
      echo -e "${MD}\t${dir}"
    else
      echo -e "${CNT}+${R1}+${R2}\t${dir}"
    fi
  
  else
  echo "${dir} OLDEST:"
  cat "$TMP" | sort -sn | head -5
  echo ""
  echo "${dir} NEWEST:"
  cat "$TMP" | sort -srn | head -5
  echo ""
  echo "${dir} SMALLEST:"
  cat "$TMP" | sort -sn -k 2 | head -5
  echo ""
  echo "${dir} BIGGEST:"
  cat "$TMP" | sort -srn -k 2 | head -5
  echo ""

  cut -f 1 < $TMP | sort -n > $T2
  FL=$(cat $T2 | wc -l)
  I1=$((FL/5))
  I5=$((FL/2))
  I9=$((FL-I1))
  P0=$(head -1 $T2)
  P1=$(head -$I1 $T2 | tail -1)
  P5=$(head -$I5 $T2 | tail -1)
  P9=$(head -$I9 $T2 | tail -1)
  P10=$(tail -n -1 $T2)
  echo "DateDistrib: ${P0}-${P1}-${P5}-${P9}-${P10}"
  
  cut -f 2 < $TMP | sort -n > $T2
  P0=$(head -1 $T2)
  P1=$(head -$I1 $T2 | tail -1)
  P5=$(head -$I5 $T2 | tail -1)
  PAVG=$(cat $T2| perl -e '$c=0;while(<>){$c++;$a+=$_}print int($a/$c)."\n"')
  P9=$(head -$I9 $T2 | tail -1)
  P10=$(tail -n -1 $T2)
  echo "SizeDistrib: ${P0}-${P1}-${PAVG}-${P9}-${P10}"
  fi

  rm -rf "$TMP" "$T2"
}

if [ "$#" = "0" ]; then
  echo "Usage: $0 [-d maxdepth] <directory> [<directory> ...]"
  echo "By default, maxdepth is 1, but you may use the -d option to set maxdepth to any arbitrary number."
  exit 1
fi
while [ "$1" ]; do
  arg="$1"
  shift
  if [ "$arg" = "-d" ]; then
    if [ "$1" ]; then
      N="$1"
      shift
      DEPTH=$((N+0))
    else
      echo "$0: -d requires depth argument" >&2
      exit 1
    fi
    continue
  fi
  if [ "$arg" = "-s" ]; then
    short=1
    continue
  fi
  if [ "$arg" = "-S" ]; then
    short=1
    cksum=1
    continue
  fi
  if [ -d "$arg/" ]; then
    snob "$arg/"
  else
    echo "Not a directory: $arg" >&2
  fi
done
