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
  if [ "$arg" = "-e" ]; then
    if [ "$1" ]; then
      DBEXPORT=$1
      shift
    else
      echo "-e requires DBEXPORT directory argument"
      exit 1
    fi
    continue
  fi
  if [ "$arg" = "-t" ]; then
    if [ "$1" ]; then
      SOURCETABLE=$1
      shift
    else
      echo "-t requires SOURCETABLE table name"
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
if [ -z "$DBEXPORT" ]; then
  echo "Need -e DBEXPORT argument"
  exit 1
fi
if [ -z "$SOURCETABLE" ]; then
  echo "Need -t SOURCETABLE argument"
  exit 1
fi
if [ -z "$PARTITIONID" ]; then
  echo "Need -p PARTITIONID (p###) argument"
  exit 1
fi

#DBDATA=${DBVOL}/data

#DBDATA=/db/mysql/data/swap_test
echo "DBNAME:$DBNAME SOURCETABLE:$SOURCETABLE PARTITIONID:$PARTITIONID DBEXPORT:$DBEXPORT"
sleep 2
find /db/mysql/data/*/ -name "${SOURCETABLE}[.#]*" | grep "\b${DBNAME}\b" | rev | cut -d/ -f2- | rev |uniq > /tmp/f.$$
if cat /tmp/f.$$ | wc -l | grep "^1$"; then
  DBDATA=$(cat /tmp/f.$$)
  echo "Found database directory $DBDATA"
  rm -f /tmp/f.$$
else
  echo "Could not find database directory (zero or more than one found)"
  exit 1
fi

EXPORTTABLE="${SOURCETABLE}_${PARTITIONID}"

export MYSQL_OPTS="-u root $DBNAME"

if mkdir -p $DBEXPORT; then
  echo "Export directory: $DBEXPORT"
else
  echo "Error creating $DBEXPORT directory"
  exit 1
fi

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
    ( tail -F $_PIPE | mysql -r -s -n ${MYSQL_OPTS} >${_OUT} 2>&1 & echo $! > ${_PIPE}.pid )
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
  

echo "Checking existence of $SOURCETABLE"
if run_mysql_cmd "SHOW TABLES LIKE '${SOURCETABLE}'" | grep -q "${SOURCETABLE}"; then
  echo "OK: source ${SOURCETABLE} exists"
else
  echo "ERR: source $SOURCETABLE does not exist."
  exit 1
fi

echo "Checking existence of $EXPORTTABLE"
if run_mysql_cmd "SHOW TABLES LIKE '${EXPORTTABLE}'" | grep -q "${EXPORTTABLE}"; then
  echo "ERR: ${EXPORTTABLE} exists.  Refusing to overwrite existing table."
  exit 1
else
  echo "OK: $EXPORTTABLE does not exist"
fi

echo "Making sure tables aren't locked"
if run_mysql_cmd "show open tables where In_Use > 0" | grep -q "^${DBNAME}\b.*\b${SOURCETABLE}\b"; then
  echo "ERR: Source table $SOURCETABLE is locked.  Cannot proceed."
  exit 1
else
  echo "OK: $SOURCETABLE is not locked.  Proceeding."
fi

echo "Creating $EXPORTTABLE like $SOURCETABLE"
run_mysql_cmd "CREATE TABLE ${EXPORTTABLE} LIKE ${SOURCETABLE}"
if [ "$?" -ne "0" ]; then
  echo "ERR: CREATE TABLE ${EXPORTTABLE} LIKE ${SOURCETABLE} failed"
  exit
fi

echo "Removing partitions from $EXPORTTABLE"
run_mysql_cmd "ALTER TABLE ${EXPORTTABLE} REMOVE PARTITIONING"
if [ "$?" -ne "0" ]; then
  echo "ERR: ALTER TABLE ${EXPORTTABLE} REMOVE PARTITIONING failed"
  exit
fi

echo "Exchanging partition $PARTITIONID"
run_mysql_cmd "ALTER TABLE ${SOURCETABLE} EXCHANGE PARTITION ${PARTITIONID} WITH TABLE ${EXPORTTABLE}"
if [ "$?" -ne "0" ]; then
  echo "ERR: ALTER TABLE ${SOURCETABLE} EXCHANGE PARTITION ${PARTITIONID} WITH TABLE ${EXPORTTABLE} failed"
  exit 1
else
  echo "OK: Exchange partition succeeded"
fi

PIPE=$(mktemp /tmp/mysql_in_XXXXXX)
OUT=$(mktemp /tmp/mysql_out_XXXXXX)

echo "Starting async mysql pipeline"
run_mysql_pipe $PIPE $OUT

PID=$(cat ${PIPE}.pid)

echo "Flushing and locking $EXPORTTABLE"
echo "FLUSH TABLES ${EXPORTTABLE} WITH READ LOCK;" >> $PIPE
echo "SELECT 'READY1';" >> $PIPE
X=60; OK=""
while [ $X -gt 0 ]; do
  X=$((X-1))
  if grep -q READY1 $OUT; then
    OK=1
    break
  fi
  sleep 1
done
if [ "$OK" = "1" ]; then
  echo "OK: FLUSH TABLES completed"
else
  echo "ERR: Timeout waiting for FLUSH TABLES to complete"
  kill -HUP $PID
  exit 1
fi

echo "Copying $EXPORTTABLE to $DBEXPORT"
cp -av ${DBDATA}/${EXPORTTABLE}.* ${DBEXPORT}/

echo "Unlocking table"
echo "UNLOCK TABLES;" >> $PIPE
echo "SELECT 'READY2';" >> $PIPE
X=60; OK=""
while [ $X -gt 0 ]; do
  X=$((X-1))
  if grep -q READY2 $OUT; then
    OK=1
    break
  fi
  sleep 1
done
if [ "$OK" = "1" ]; then
  echo "OK: UNLOCK TABLES completed"
else
  echo "ERR: Timeout waiting for FLUSH TABLES to complete"
  kill -HUP $PID
  exit 1
fi


echo "Quitting mysql pipeline"
echo "\\q" >> $PIPE
sleep 1

echo "Swapping partition back"
run_mysql_cmd "ALTER TABLE ${SOURCETABLE} EXCHANGE PARTITION ${PARTITIONID} WITH TABLE ${EXPORTTABLE}"
if [ "$?" -ne "0" ]; then
  echo "ERR: ALTER TABLE ${SOURCETABLE} EXCHANGE PARTITION ${PARTITIONID} WITH TABLE ${EXPORTTABLE} failed"
  exit
fi

echo "Dropping temp table"
run_mysql_cmd "DROP TABLE ${EXPORTTABLE}"
if [ "$?" -ne "0" ]; then
  echo "ERR: DROP TABLE ${EXPORTTABLE} failed"
  exit
fi

echo "OK: finished exporting ${SOURCETABLE} partition ${PARTITIONID} to ${EXPORTTABLE}"
ls -ld ${DBEXPORT}/${EXPORTTABLE}*

exit 0
