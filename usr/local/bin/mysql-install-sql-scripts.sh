#!/bin/bash
# PFLOCAL
# PFDISTRIB mysql

usage() {
  echo "Usage:"
  echo "$0 -d <dbname> [-t] [datespec] [file1.sql] ... [fileN.sql]"
  echo "-d dbname argument required"
  echo "-t prevents script from installing anything - testing only"
  echo "Without other args, this program finds the most recent set of files, no more than 30 days old, named like "*-YYYYMMDD.sql" and installs them as sql scripts into dbname"
}

while [ "$1" ]; do
  arg="$1"; shift
  if [ "$arg" = "-d" ]; then
    if ls -ld "/db/mysql/data/$1" >/dev/null 2>/dev/null; then
      db="$1"
      shift
    else
      echo "ERROR: Specified database (-d $1) doesn't exist"
      sleep 1
      exit 1
    fi
    continue
  fi
  if [ "$arg" = "-t" ]; then
    TESTONLY=1
    continue
  fi
  if echo "$arg" | grep "^20[0-9][0-9][0-9][0-9][0-9][0-9]$"; then
    date="$arg"
    continue
  fi
  if [ -f "$arg" ]; then
    files="$files $arg"
    continue
  fi
  usage
  exit 1
done

if [ -z "$db" ]; then
  usage
  exit 1
fi

if [ -z "$date" ] && [ -z "$files" ]; then
  if [ -f "get-sprocs.cfg" ]; then
    files=$(cat get-sprocs.cfg | grep ^SPROC | cut -d' ' -f 2- | tr -s '\t ' '\n' | sed -e 's/http:.*\///' -e 's/\.sql$//' |  while read sp; do find . -name "${sp}-*-20*.sql" | sed -e 's/\.sql//' -e 's/\.\///' -e 's/^\(.*\)-\(20[0-9][0-9][0-9][0-9][0-9][0-9]\)$/\2 \1/' | sort -nr | head -1 | sed -e 's/^\([0-9][0-9]*\) \(.*\)$/\2-\1.sql/'; done | tr '\n' ' ')
  else
    echo "ERROR: get-sprocs.cfg must exist in this directory ($(/bin/pwd)) and have sprocs defined in order for this script to work"
    sleep 1
    exit 1
  fi
fi
if [ -z "$date" ] && [ -z "$files" ]; then
  echo "ERROR: No date specified or no recent dated sql files found"
  exit 1
fi
if [ -z "$files" ]; then
  files=$(find . -type f -iname "${date}.sql")
fi
if [ -z "$files" ]; then
  echo "ERROR: No files found matching *${date}.sql"
  exit 1
fi

err=''
for f in $files; do
  if [ -f "$f" ]; then
    if [ "$TESTONLY" ]; then
      echo "TESTONLY: mysql -c $db < $f"
    else
      if mysql -c "$db" < "$f" ; then
        echo "Load $f into $db: OK"
      else
        echo "Load $f into $db: ERROR"
        err=1
      fi
    fi
  else
    echo "$f not found"
    err=1
  fi
done
if [ "$err" ]; then
  echo "ERROR: There were errors when loading specied files into $db"
  sleep 1
  exit 1
fi
echo "Done."
exit 0
