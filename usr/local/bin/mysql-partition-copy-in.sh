#!/bin/bash
export LC_ALL=C
export LANG=C

while [ "$1" ]; do
  arg="$1"
  shift
  if [ "$arg" = "-d" ]; then
    if [ "$1" ]; then
      DBNAME=$1
      shift
    else
      echo "-d requires DBNAME argument"
      exit 1
    fi
    continue
  fi
  if [ "$arg" = "-i" ]; then
    if [ "$1" ]; then
      DBIMPORT=$1
      shift
    else
      echo "-e requires DBIMPORT directory argument"
      exit 1
    fi
    continue
  fi
  if [ "$arg" = "-t" ]; then
    if [ "$1" ]; then
      DESTTABLE=$1
      shift
    else
      echo "-t requires DESTTABLE table name"
      exit 1
    fi
    continue
  fi
  if [ "$arg" = "-p" ]; then
    if [ "$1" ]; then
      if echo "$1" | grep -q "^p[0-9][0-9]*$"; then
        PARTITIONID="$1"
      else
        echo "-p requires partition id formatted like p###"
        exit 1
      fi
    else
      echo "-p requires partition id formatted like p###"
      exit 1
    fi
    continue
  fi
done

if [ -z "$DBNAME" ]; then
  echo "Need -d DBNAME argument"
  exit 1
fi
if [ -z "$DBIMPORT" ]; then
  echo "Need -i DBIMPORT argument"
  exit 1
fi
if [ -z "$DESTTABLE" ]; then
  echo "Need -t DESTTABLE argument"
  exit 1
fi
if [ -z "$PARTITIONID" ]; then
  echo "Need -p PARTITIONID (p###) argument"
  exit 1
fi

echo "DBNAME:$DBNAME DESTTABLE:$DESTTABLE PARTITIONID:$PARTITIONID DBIMPORT:$DBIMPORT"
sleep 5

find /db/mysql/data/*/ -name "${DESTTABLE}[.#]*" | grep "\b${DBNAME}\b" | rev | cut -d/ -f2- | rev |uniq > /tmp/f.$$
if cat /tmp/f.$$ | wc -l | grep "^1$"; then
  DBDATA=$(cat /tmp/f.$$)
  echo "Found database directory $DBDATA"
  rm -f /tmp/f.$$
else
  echo "Could not find database directory (zero or more than one found)"
  exit 1
fi

IMPORTTABLE="${DESTTABLE}_${PARTITIONID}"

export MYSQL_OPTS="-u root $DBNAME"

run_mysql_cmd() {
  SQL="$*"
  _OUT=$(mktemp /tmp/mysql_cmd_XXXXXX)

  mysql ${MYSQL_OPTS} -r -s -e "$SQL" >${_OUT} 2>&1
  RET=$?
#  echo "mysql exit code: $RET"
#  echo "results in $_OUT"
  cat $_OUT
  rm -f $_OUT
  return $RET
}

run_mysql_pipe() {
  _PIPE=$1
  _OUT=$2
  if [ "$1" ] && [ "$2" ]; then
    echo "Starting mysql command pipe from $_PIPE to $_OUT ..."
    ( tail -f $_PIPE | mysql -r -s -n ${MYSQL_OPTS} >${_OUT} 2>&1 & echo $! > ${_PIPE}.pid )
    sleep 1
    PID=$(cat ${_PIPE}.pid)
    if [ "$PID" ]; then
      echo "Async persistent mysql client pid is $PID"
      return 0
    else
      echo "Async persistent mysql client didn't generate a PID!"
      return 1
    fi
  fi
}
  

echo "Checking existence of $DESTTABLE"
if run_mysql_cmd "SHOW TABLES LIKE '${DESTTABLE}'" | grep -q "${DESTTABLE}"; then
  echo "OK: source ${DESTTABLE} exists"
else
  echo "ERR: source $DESTTABLE does not exist."
  exit 1
fi

echo "Checking existence of $IMPORTTABLE"
if run_mysql_cmd "SHOW TABLES LIKE '${IMPORTTABLE}'" | grep -q "${IMPORTTABLE}"; then
  echo "ERR: ${IMPORTTABLE} exists.  Refusing to overwrite existing table."
  exit 1
else
  echo "OK: $IMPORTTABLE does not exist"
fi

echo "Checking source table"
N=$(ls -l ${DBIMPORT}/${IMPORTTABLE}.* | wc -l)
if [ "$N" = "3" ]; then
  echo "OK: Found import table files"
else
  echo "Didn't find import table files"
  exit 1
fi

echo "Copying source table to $DBDATA"
if cp -av ${DBIMPORT}/${IMPORTTABLE}.* ${DBDATA}/; then
  echo "OK: Copy finished."
else
  echo "ERR: Copy failed."
  exit 1
fi

chown -R mysql:mysql ${DBDATA}/${IMPORTTABLE}.*

echo "Exchanging partition $PARTITIONID"
run_mysql_cmd "ALTER TABLE ${DESTTABLE} EXCHANGE PARTITION ${PARTITIONID} WITH TABLE ${IMPORTTABLE}"
if [ "$?" -ne "0" ]; then
  echo "ERR: ALTER TABLE ${DESTTABLE} EXCHANGE PARTITION ${PARTITIONID} WITH TABLE ${IMPORTTABLE} failed"
  exit
fi

#echo "Dropping temp table"
#run_mysql_cmd "DROP TABLE ${IMPORTTABLE}"
#if [ "$?" -ne "0" ]; then
#  echo "ERR: DROP TABLE ${IMPORTTABLE} failed"
#  exit
#fi

echo "OK: finished importing ${DESTTABLE} partition ${PARTITIONID} to ${IMPORTTABLE}"
echo "Old partition swapped out to table should be okay to delete:"
ls -ld ${DBDATA}/${IMPORTTABLE}*

exit 0
