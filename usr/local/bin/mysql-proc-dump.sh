#!/bin/bash
# PFLOCAL
# PFDISTRIB
if [ "$1" ]; then
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    progname=$(echo "$0" | rev | cut -d/ -f1 | rev)
    echo "$progname dumps a sorted list of mysql procedures and functions, helpful for comparing installed procs/functions between mysql/mariadb servers"
    echo "usage: $progname [dbname [procname]]"
    echo ""
    echo "note: displayed 'content' line is compressed and truncated only for comparison purposes, and should not be considered accurate"
    exit 0
  fi
  if [ "$2" ]; then
    mysqldump --skip-extended-insert -ct -w "db='$1' AND name='$2'" mysql proc | sed -e 's/^INSERT /REPLACE /g' | grep ^REPLACE | sort
  else
    mysqldump --skip-extended-insert -ct -w "db='$1'" mysql proc | sed -e 's/^INSERT /REPLACE /g' | grep ^REPLACE | sort
  fi
else
  mysqldump --skip-extended-insert -ct mysql proc | sed -e 's/^INSERT /REPLACE /g' | grep ^REPLACE | sort
fi
