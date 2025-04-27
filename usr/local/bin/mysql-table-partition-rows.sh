#!/bin/bash
# PFLOCAL
# PFDISTRIB

###
# mysql-table-partition-rows.sh v1.0
#
# Author: Erik Schorr <erik@peoplefinders.com>
# Description: Dumps tabular table showing row counts for tables and table partitions found in supplied database.
# Usage: mysql-table-partition-rows.sh [ -d <delimiter> ] DatabaseName
#
###

DELIMITER=$(echo -e "\t")
usage() {
    echo ""
    echo "Usage: $0 [ -s ] [ -d <delimiter> ] [ -o \"<mysqlopts>\" ] DatabaseName"
    echo "  Optional -s parameter suppresses dbname in output."
    echo "  Optional -d delimiter should be one character, and will be used as column separator instead of tabs."
    echo "  Optional -o parameter should contain mysql commandline options, if needed:"
    echo "  $0 -o \"-uUser -pPass -hHost\"" DatabaseName
    echo ""
}

while [ "$1" ]; do
  if [ "$1" = "-d" ]; then
   shift
   if [ "$1" ] && echo "$1" | grep -q "^.$"; then
      DELIMITER="$1"
      shift
    else
      usage
      exit 1
    fi
    continue
  fi

  if [ "$1" = "-o" ]; then
    shift
    if [ "$1" ]; then
      MYSQLOPTS="$1"
      shift
    else
      usage
      exit 1
    fi
    continue
  fi

  if [ "$1" = "-s" ]; then
    shift
    SUPPRESSDB=1
    continue
  fi

  if echo "$1" | grep -q "^-"; then
    echo "Unknown option: $1"
    usage
    exit 1
  fi
  DB=$1
  shift
done

if [ -z "$DB" ]; then
  usage
  exit 0
fi

mysql $MYSQLOPTS -NB -e "show variables like 'hostname'" | sed -e 's/^hostname/# dbserver/' -e 's/\t/:/'
if [ "$SUPPRESSDB" ]; then
  echo "# database:$DB"
  mysql $MYSQLOPTS -B information_schema -e "SELECT TABLE_NAME AS \`TABLE\`, '#N/A#' AS \`PARTITION\`, TABLE_ROWS AS ROWS FROM PARTITIONS WHERE TABLE_SCHEMA='$DB' AND PARTITION_NAME IS NULL UNION SELECT TABLE_NAME, PARTITION_NAME,TABLE_ROWS FROM PARTITIONS WHERE TABLE_SCHEMA='$DB' AND PARTITION_NAME IS NOT NULL UNION SELECT TABLE_NAME, '#TOTAL#', SUM(TABLE_ROWS) FROM PARTITIONS WHERE TABLE_SCHEMA='$DB' AND PARTITION_NAME IS NOT NULL GROUP BY TABLE_SCHEMA,TABLE_NAME ORDER BY \`TABLE\`,\`PARTITION\`" | tr "\t" "$DELIMITER"
else
  mysql $MYSQLOPTS -B information_schema -e "SELECT TABLE_SCHEMA AS \`DATABASE\`, TABLE_NAME AS \`TABLE\`, '#N/A#' AS \`PARTITION\`, TABLE_ROWS AS ROWS FROM PARTITIONS WHERE TABLE_SCHEMA='$DB' AND PARTITION_NAME IS NULL UNION SELECT TABLE_SCHEMA, TABLE_NAME, PARTITION_NAME,TABLE_ROWS FROM PARTITIONS WHERE TABLE_SCHEMA='$DB' AND PARTITION_NAME IS NOT NULL UNION SELECT TABLE_SCHEMA, TABLE_NAME, '#TOTAL#', SUM(TABLE_ROWS) FROM PARTITIONS WHERE TABLE_SCHEMA='$DB' AND PARTITION_NAME IS NOT NULL GROUP BY TABLE_SCHEMA,TABLE_NAME ORDER BY \`DATABASE\`,\`TABLE\`,\`PARTITION\`" | tr "\t" "$DELIMITER"
fi

exit $?

