#!/bin/bash
# PFLOCAL
# PFDISTRIB mysql

# mysql-flush-db.sh
# Erik Schorr
# rev 2017-10-19 fix truncation, allow list and/or like for DB name lookups
# rev 2018-01-31 add -D -D to drop tables instead of flush

usage() {
  echo "Usage:"
  echo "$0 [-L 'likepattern'] DBname1 [DBname2] [DBnameN...]"
  exit
}

DROP=0
DB_BLACKLIST="'mysql','performance_schema','information_schema','test'"
TABLE_BLACKLIST=""
DB_LIST=""
while [ "$1" ]; do
  arg="$1"; shift
  if [ "$arg" = "-h" ]; then
    usage
    exit
  fi
  if [ "$arg" = "-x" ] && [ "$1" ]; then
    if [ "$TABLE_BLACKLIST" ]; then
      TABLE_BLACKLIST="$TABLE_BLACKLIST,'$1'"
      shift
    else
      TABLE_BLACKLIST="'$1'"
    fi
    continue
  fi
  if [ "$arg" = "-v" ]; then
    VERBOSE=1
    continue
  fi
  if [ "$arg" = "-D" ]; then
    DROP=$((DROP+1))
    continue
  fi
  if [ "$arg" = "-t" ]; then
    TESTONLY=1
    continue
  fi
  if [ "$arg" = "-L" ] && [ "$1" ]; then
    DB_LIKE="$1"; shift
    continue
  fi
  if [ "$DB_LIST" ]; then
    DB_LIST="${DB_LIST},'$arg'"
  else
    DB_LIST="'$arg'"
  fi
done

if [ -z "$DB_LIST" ] && [ -z "$DB_LIKE" ]; then
  usage
  exit
fi

if [ "$VERBOSE" ]; then
  echo "Excluding tables: $TABLE_BLACKLIST"
fi
QUERY="SET SESSION group_concat_max_len = 1000000;"
if [ "$DROP" -gt 1 ]; then
	QUERY="$QUERY SELECT concat('DROP TABLE IF EXISTS ',group_concat(concat(TABLE_SCHEMA,'.',TABLE_NAME)),';') AS flush_cmd FROM information_schema.TABLES WHERE TABLE_TYPE='BASE TABLE'"
else
	QUERY="$QUERY SELECT concat('FLUSH TABLES ',group_concat(concat(TABLE_SCHEMA,'.',TABLE_NAME)),';') AS flush_cmd FROM information_schema.TABLES WHERE TABLE_TYPE='BASE TABLE'"
fi
if [ "$DB_LIKE" ]; then QUERY="$QUERY AND TABLE_SCHEMA LIKE '$DB_LIKE'"; fi
if [ "$DB_LIST" ]; then QUERY="$QUERY AND TABLE_SCHEMA IN ($DB_LIST)"; fi
if [ "$DB_BLACKLIST" ]; then
  QUERY="$QUERY AND TABLE_SCHEMA NOT IN ($DB_BLACKLIST)"
fi
if [ "$TABLE_BLACKLIST" ]; then
  QUERY="$QUERY AND TABLE_NAME NOT IN ($TABLE_BLACKLIST)"
fi

[ "$VERBOSE" ] && echo "Query: $QUERY"
MYSQLCMD=$(mysql -B information_schema -e "$QUERY" | tail -n +2)
if [ "$MYSQLCMD" = "NULL" ] || [ "$MYSQLCMD" = "" ]; then
  echo "No such database or no tables eligible for flushing in requested database(s)" >&2
  exit 1
else
  echo "Running secondary query:"
  echo "$MYSQLCMD"
  if [ "$TESTONLY" ]; then
    echo "TESTONLY: Skipped execution"
    exit 0
  else
    if mysql "$DB" -e "$MYSQLCMD"; then
      echo "Succeeded"
      exit 0
    else
      echo "Failed"
      exit $?
    fi
  fi
fi
