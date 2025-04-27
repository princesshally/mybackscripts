#!/bin/bash
# PFLOCAL
ARRAYS=$(echo smf3-pure{1..6}.pfnetwork.net)
OPTARRAYS=""
while [ "$1" ]; do
  arg="$1"; shift
  if [ "${arg:0:1}" = "-" ]; then
    opts=${arg:1}
    if [[ $opts =~ v ]]; then
      opts=${opts/v/}
      VERBOSE=1
    fi
    if [[ $opts =~ d ]]; then
      opts=${opts/d/}
      DISABLE=1
    fi
    if [ "$opts" ]; then
      echo "Unknown option(s) $opts"
    fi
    continue
  fi 
  if [[ $arg =~ pure ]]; then
    if [ "$OPTARRAYS" ]; then
      OPTARRAYS="$OPTARRAYS $arg"
    else
      OPTARRAYS="$arg"
    fi
  fi
done
if [ "$OPTARRAYS" ]; then
  ARRAYS="$OPTARRAYS"
fi

[ "$VERBOSE" ] && echo "Enabling RA on $ARRAYS"

for ARRAY in $ARRAYS; do
  if [ "$OPTARRAYS" ] && [ "$DISABLE" ]; then
    [ "$VERBOSE" ] && echo "Disabling RA on $ARRAY"
    R=$(:|ssh pureuser@$ARRAY 'purearray remoteassist --disconnect' 2>&1)
    echo "$R"
    continue
  fi
  R=$(:|ssh pureuser@$ARRAY 'purearray remoteassist --status' 2>&1)
  [ "$VERBOSE" ] && echo ">>> $R"  
  if [[ $R =~ "enabled" ]] || [[ $R =~ " connected " ]]; then
    [ "$VERBOSE" ] && echo "RA already connected on $ARRAY"
    continue
  fi
  R=$(:|ssh pureuser@$ARRAY 'purearray remoteassist --connect' 2>&1)
  [ "$VERBOSE" ] && echo ">>> $R"  
  tries=5
  while [ "$tries" -gt 0 ]; do
    R=$(:|ssh pureuser@$ARRAY 'purearray remoteassist --status' 2>&1)
    if [[ $R =~ "enabled" ]] || [[ $R =~ " connected " ]]; then
      [ "$VERBOSE" ] && echo "RA connected on $ARRAY"
      continue
    fi
    tries=$((tries-1))
  done
  echo "Enable RA on $ARRAY failed:"
  echo ">>> $R"
done
     
