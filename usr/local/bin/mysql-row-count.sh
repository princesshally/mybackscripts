#!/bin/bash
# PFLOCAL
# PFDISTRIB mysql

MYSQLOPTS=""

usage() {
  echo "Usage:"
  echo "$0 DbName [TableName] [TableName ...]"
  exit
}


TABLELIST=""
if [ "$1" ]; then
  while [ "$1" ]; do
    if [ "$1" = "-M" ]; then
      shift
      MYSQLOPTS="$1"
      shift
      continue
    fi

    if [ -z "$DB" ]; then
      DB="$1"
      shift
      continue
    fi

    if [ "$TABLELIST"]; then
      TABLELIST="${TABLELIST},'$1'"
    else
      TABLELIST="'$1'"
    fi
    shift
  done 
else
  usage
  exit 1
fi

QUERY="select TABLE_NAME as tablename,IF(TABLE_TYPE='VIEW','#VIEW#',TABLE_ROWS) as rowcount from tables WHERE TABLE_SCHEMA='${DB}'"
if [ "$TABLELIST" ]; then
  QUERY="${QUERY} AND TABLE_NAME IN (${TABLELIST})"
fi
QUERY="${QUERY} order by TABLE_NAME;"
mysql ${MYSQLOPTS} -NB "information_schema" -e "${QUERY}"
exit 0

