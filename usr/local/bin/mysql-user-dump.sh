#!/bin/bash
# PFLOCAL
# PFDISTRIB
if [ "$1" ]; then
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    progname=$(echo "$0" | rev | cut -d/ -f1 | rev)
    echo "$progname dumps a sorted list of mysql users, helpful for comparing user permissions between mysql/mariadb servers"
    echo "usage: $progname [username]"
    exit 0
  fi
  echo "-- mysql.user table from $HOSTNAME on $(date)"
  mysqldump --skip-extended-insert -ct -w "user='$1'" mysql user | sed -e 's/^INSERT /REPLACE /g' | grep ^REPLACE | sort
  echo "-- mysql.db table from $HOSTNAME on $(date)"
  mysqldump --skip-extended-insert -ct -w "user='$1'" mysql db | sed -e 's/^INSERT /REPLACE /g' | grep ^REPLACE | sort
else
  echo "-- mysql.user table from $HOSTNAME on $(date)"
  mysqldump --skip-extended-insert -ct mysql user | sed -e 's/^INSERT /REPLACE /g' | grep ^REPLACE | sort
  echo "-- mysql.db table from $HOSTNAME on $(date)"
  mysqldump --skip-extended-insert -ct mysql db | sed -e 's/^INSERT /REPLACE /g' | grep ^REPLACE | sort
fi
