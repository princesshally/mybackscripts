#!/bin/bash
# PFLOCAL
# PFDISTRIB ALL

if [ "$1" = "-q" ]; then
  quiet=1
  shift
fi
if [ "$1" ]; then
  host=$1
else
  echo "$0 need hostname"
  exit 2
fi

if ping -i 0.2 -c1 -w1 $host >/dev/null 2>/dev/null; then
  [ "$quiet" ] || echo "UP"
  exit 0
else
  [ "$quiet" ] || echo "DOWN"
  exit 1
fi
