#!/bin/bash
# PFLOCAL
# PFDISTRIB
opts=""
if [ "$1" ]; then
  database=$1
else
  echo "Usage: $0 dbname" >&2
  exit 1
fi

sqlcmd="SELECT GROUP_CONCAT(table_name SEPARATOR ', ') AS table_list FROM tables WHERE table_schema NOT IN ('sys','performance_schema','information_schema','mysql') AND table_type='base table' AND table_schema='$database' ORDER BY table_schema,table_name;"


tables=`/usr/bin/mysql --batch -qN $opts information_schema -e "$sqlcmd"`

flushsql="FLUSH TABLES $tables FOR EXPORT;"
echo $flushsql

sqlcmd="SELECT table_name AS table_list FROM tables WHERE table_schema NOT IN ('sys','performance_schema','information_schema','mysql') AND table_schema='$database' AND table_type='view' ORDER BY table_schema,table_name;"
views=`/usr/bin/mysql --batch -qN $opts information_schema -e "$sqlcmd"`
echo -n "lock tables "
x=0
for q in $views; do
  if [ "$x" = "0" ]; then
    x=1
  else
    echo -n ", "
  fi
  echo -n " $q read "
done
echo ""
