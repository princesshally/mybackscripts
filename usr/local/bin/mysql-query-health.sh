#!/bin/bash
# PFLOCAL
# PFDISTRIB mysql
#DEBUG=1
SSHOPTS="-q -l root"

# tasks:
# (for each target host)
# 0) check if host is up.  Error if not up: "Cannot proceed if any target hosts are offline or unavailable"
# 1) save remote mysql processlist to tmpfile
# 2) in tmpfile, look for "Query.*waiting.*metadata" - Error if >0 - "Cannot proceed due to metadata locks - possible storage engine contention"
# 3) in tmpfile, look for "Killed" queries more than 1000 seconds old - Error if >0 - "too many queries stuck in Killed state - mysql service may need draining+restart"
# 4) in tmpfile, look for "[0-9][0-9][0-9].Query" - Warn if >5 - "Some queries have been running more than 100 seconds"
# 5) Sleep if errors or warnings present
# 6) Exit with error code if any errors present

declare -g TEMPFILE

isup() {
  if ping -i 0.2 -c1 -w1 $1 >/dev/null 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

get_remote_processlist() {
  RH="$1"
  if isup $RH; then
    if [ -z "$TEMPFILE" ]; then
      TEMPFILE=$(mktemp /tmp/grp-XXXXXXXX)
      [ "$DEBUG" ] && echo TF:$TEMPFILE >&2
      if [ -z "$TEMPFILE" ]; then
        return 37
      fi
    fi
    [ "$DEBUG" ] && echo TF2:$TEMPFILE >&2
    ssh $SSHOPTS $RH "mysql -Be 'show full processlist'" >$TEMPFILE 2>&1
    if head -1 $TEMPFILE | grep -q "^Id"; then
      [ "$DEBUG" ] && echo "--- $RH has $(cat $TEMPFILE | wc -l) processes" >&2
      echo "$TEMPFILE"
    else
      echo "Could not get processlist on $RH" >&2
      exit 3
    fi
  else
#    echo "get_remote_processlist: host $RH not up" >&2
    echo "ERROR: host $RH not up"
    return 112
  fi
}

parse_processlist() {
  INFILE="$1"
  _ERR=""
  _WARN=""
  if [ -f "$INFILE" ]; then
    c=$(grep -ci "query.*waiting.*metadata.*lock" "$INFILE")
    if [ "$c" -gt 0 ]; then
      echo "ERROR: Remote mysql server has $c pending metadata lock requests"
      _ERR=1
    fi
    c=$(grep -Eac "Query.[1-9]{3,}" "$INFILE")
    if [ "$c" -gt 0 ]; then
      echo "WARNING: Remote mysql server has $c long-running queries:"
      grep -Ea "Query.[1-9]{3,}" "$INFILE" | head | cut -c 1-158
      _WARN=1
    fi
    c=$(grep -Eaci "[0-9]{3,}.Killed" "$INFILE")
    if [ "$c" -gt 0 ]; then
      echo "ERROR: Remote mysql server has $c stuck killed processes"
      _ERR=1
    fi
    if [ "${_ERR}" ]; then
      echo "ERROR"
      return 1
    fi
    if [ "${_WARN}" ]; then
      echo "WARNING"
      return 0
    fi
    echo "OK"
    return 0
  fi
}

cleanexit() {
  if [ "$TEMPFILE" ] && [[ $TEMPFILE =~ /tmp/ ]]; then rm -f "$TEMPFILE"; fi
  if [ "$1" ]; then
    exit $1
  fi
  exit 0
}


TARGETS=""
while [ "$1" ]; do
  ARG="$1"; shift
  if [[ $ARG =~ ^[a-zA-Z] ]]; then
    TARGETS="${TARGETS}${TARGETS:+ }$ARG"
    continue
  fi
done

if [ "$TARGETS" ]; then
  [ "$DEBUG" ] && echo "targets: [${TARGETS}]"
  for HOST in $TARGETS; do
    [ "$DEBUG" ] && echo "Checking $HOST ..." >&2
    F=$(get_remote_processlist $HOST)
    if [ "${F:0:3}" = "ERR" ]; then
      echo "$F" >&2
      cleanexit 3
    fi
    if [ "${F:0:4}" = "WARN" ]; then
      echo "$F" >&2
      continue
    fi
    [ "$DEBUG" ] && echo "F: $F" >&2
    if [ -f "$F" ]; then
      parse_processlist $F
      [ "$DEBUG" ] && echo pp-exit for $HOST: $?
    fi
  done
fi
cleanexit 0


