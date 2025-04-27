#!/bin/bash
if [ "$COLUMNS" ]; then
  W=$((COLUMNS-10))
  echo "W: $W"
fi
W=70
l=1
e=$(cat $1 | wc -l)
while [ "$l" -le "$e" ]; do
  len=$(head -$l $1 | tail -1 | wc -c)
  if [ "$W" ]; then
    p=$(head -$l $1 | tail -1 | cut -c1-${W})
    printf "%0.2d %0.6d %s\n" $l $len "$p"
  else
    echo "$l $len"
  fi
  l=$((l+1))
done
  
