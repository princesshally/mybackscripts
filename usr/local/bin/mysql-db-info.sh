#!/bin/bash
# PFLOCAL
# PFDISTRIB
PID=$$
#ls -l /proc/${PID}/fd/1
if ls -l /proc/${PID}/fd/1 | grep -q pts; then
  SC1='\x1b[1m'
  SC2='\x1b[0m'
fi
DB=".*"
if [ "$1" ] && echo "$1" | grep -qv "^-"; then
  DB="$1"
fi

cd /db/mysql/data 2>/dev/null || cd /data01/mysql/data 2>/dev/null || cd /var/lib/mysql 2>/dev/null || exit 1

du */ | grep / | sort -n | grep '^[0-9][0-9][0-9]' | egrep -vi '(test|mysql)' | cut -d/ -f1 | tr -s ' \t' '\t' | cut -f2 | sort | grep "\b$DB\b" | while read q; do
  echo -e "--- ${SC1}${q}${SC2} ---"
  find $q/ -type f \( -iname '*.MY*' -o -iname '*ibd' \) -printf '%TY-%Tm-%Td\t%H\t%f\n' | sort -n | tail -5
  du -BG ${q}/ | tail -n -1; echo ""
done
