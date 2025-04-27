#!/bin/bash
# PFLOCAL
# PFDISTRIB
# mfilestats.sh - Erik Schorr 2016-04-25

DEFAULTPATHS="."
PATHS=""
DEFAULTTYPE="-type f"
TYPE=""
DEFAULTOPTS="-xdev"
OPTS="-xdev"



while [ -n "$1" ]; do
  ARG=$1; shift
  if [ -e "$ARG" ]; then
#    echo "adding $ARG to PATHS" >&2
    if [ -n "$PATHS" ]; then
      PATHS="$PATHS '$ARG'"
    else
      PATHS="'$ARG'"
    fi
    continue
  fi
  if echo "$ARG" | grep -q "^-type"; then
    if echo "$1" | egrep -q "^(f|d|s|l)$" ; then
      TYPE="-type $1"
      shift
      continue
    else
      echo "type option requires a type arg (f|d|s|l)" >&2
      exit 1
    fi
  fi
  if [ "$ARG" = "-test" ] || [ "$ARG" = "-n" ]; then
    TESTONLY=1
    continue
  fi
  if [ "$ARG" = "-i" ]; then
    INODE=1
    continue
  fi
  if echo "$1" | grep -q "^-"; then
    echo "Unknown arg: $ARG"
  fi
done

if [ -z "$PATHS" ]; then
  PATHS="$DEFAULTPATHS"
fi
if [ -z "$TYPE" ]; then
  TYPE="$DEFAULTTYPE"
fi

CMD="find"
FORMAT="-printf '%TY%Tm%Td|%s|%h|%f\n'"
if [ "$INODE" ]; then
  FORMAT="-printf '%TY%Tm%Td|%s|%h|%f|%i|%n\n'"
fi



EXEC="$CMD $PATHS $OPTS $TYPE $FORMAT"
if [ -n "$TESTONLY" ]; then
  echo "EXEC=$EXEC"
  /bin/bash -c "echo $EXEC"
else
  /bin/bash -c "$EXEC" | sed -e 's/\|\.\///g'
fi
