#!/bin/bash
# PFLOCAL
# PFDISTRIB
export LC_ALL=C
export LANG=C
SOURCETABLES=""
PARTLIST=""
TMPLOG=$(mktemp /tmp/mysql-table-copy-out-XXXXXX)
FLUSHTIMEOUT=120
#gzcmd="lzop -1U"

usage() {
  echo "$0 copies one or more raw table files from a database to a local or remote destination directory, given source database and table name(s)."
  echo "Usage samples:"
  echo "$0 [-z] -d DBNAME -e /path/to/destdir tablename1 [tablenameN ...]"
  echo "$0 -d DBNAME -e root@remotehost:/remotepath tablename1 [tablenameN ...]"
  echo "$0 -d DBNAME -e root@remotehost:/remotepath ALL"
  echo ""
  echo "Specifying ALL for tablename causes this script to copy all MyISAM tables and view definitions found in specified database."
  echo "This script WILL NOT WORK for InnoDB or CSV tables!"
}

run_mysql_cmd() {
  SQL="$*"
  _OUT=$(mktemp /tmp/mysql_cmd_XXXXXX)

#  [ "$TESTONLY" ] && echo "SQL: $SQL" >&2
  mysql ${MYSQL_OPTS} -r -s -e "$SQL" >${_OUT} 2>&1
  RET=$?
#  echo "mysql exit code: $RET"
#  echo "results in $_OUT"
  cat $_OUT
  rm -f $_OUT
  return $RET
}


if tail --help | grep -q PID; then
  echo "Yay!  we have modern tail" >/dev/null
else
  echo "This script requires a modern version of the tail command that supports the --pid option"
  exit 1
fi

while [ "$1" ]; do
  arg="$1"
  shift
  if [ "$arg" = "-r" ]; then
    FORCE_RSYNC=1
    continue
  fi
  if [ "$arg" = "-h" ]; then
    usage
    exit 0
  fi
  if [ "$arg" = "-test" ] || [ "$arg" = "-n" ]; then
    TESTONLY=1
    echo "Testing only.  No actions will be taken." >&2
    continue
  fi
  if [ "$arg" = "-z" ]; then
    gzcmd="lzop -v1U"
  fi
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
  if [ "$arg" = "-i" ]; then
    if [ "$1" ]; then
      if [ -f "$1" ]; then
        RSAIDFILE="$1"
        shift
      else
        echo "-i requires readable file containing ssh private key"
        exit 1
      fi
    fi
    continue
  fi
  if [ "$arg" = "-p" ]; then
    if [ "$1" ]; then
      PARTLIST="$PARTLIST $1"
      shift
    else
      echo "-p requires PARTITIONID id"
      exit 1
    fi
    continue
  fi
  if [ "$arg" = "-t" ]; then
    if [ "$1" ]; then
      t=$1
      t=$(echo "$SOURCETABLE" | cut -d. -f1 | cut -d"#" -f1)
      if [ "$SOURCETABLES" ]; then
        SOURCETABLES="$SOURCETABLES $t"
      else
        SOURCETABLES="$T"
      fi
      shift
    else
      echo "-t requires SOURCETABLE table name"
      exit 1
    fi
    continue
  fi
  if echo "$arg" | grep -q "^[a-zA-Z0-9][a-zA-Z0-9_-]"; then
    t=$(echo "$arg" | cut -d. -f1 | cut -d"#" -f1)
    [ "$TESTONLY" ] && echo "Adding table $t to list" >&2
    if [ "$SOURCETABLES" ]; then
      SOURCETABLES="$SOURCETABLES $t"
    else
      SOURCETABLES="$t"
    fi
    continue
  fi
  echo "Unknown option: $arg" >&2
done

if [ -z "$DBNAME" ]; then
  echo "Need -d DBNAME argument" >&2
  usage
fi
if [ -z "$DBEXPORT" ]; then
  echo "Need -e DBEXPORT directory argument" >&2
  usage
fi

if [ "$SOURCETABLES" ]; then
  SOURCETABLES=$(echo "$SOURCETABLES" | tr " " "\n" | sort | uniq )
  if [ "$SOURCETABLES" = "ALL" ]; then
    echo "Finding all tables in $DBNAME" >&2
#    SOURCETABLES=$(run_mysql_cmd "SELECT TABLE_NAME AS t FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE in ('BASE TABLE','VIEW') AND TABLE_SCHEMA='${DBNAME}' AND (ENGINE='MyISAM' OR ENGINE IS NULL)" | tail -n +1)
    SOURCETABLES=$(run_mysql_cmd "SELECT TABLE_NAME AS t FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE in ('BASE TABLE') AND TABLE_SCHEMA='${DBNAME}' AND (ENGINE='MyISAM' OR ENGINE IS NULL)" | tail -n +1)
#    run_mysql_cmd "SELECT TABLE_NAME AS t FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE in ('BASE TABLE','VIEW') AND TABLE_SCHEMA='${DBNAME}' AND (ENGINE='MyISAM' OR ENGINE IS NULL)"
    SOURCETABLES=$(echo "$SOURCETABLES" | tr " " "\n" | sort | uniq  | tr '\n' ' ' )
    echo "Found tables: $SOURCETABLES"
  fi
  TABLECOUNT=$(echo "$SOURCETABLES" | wc -w)
  if [ "$TABLECOUNT" -ne 1 ] && [ "$PARTLIST" ]; then
    echo "Partition list cannot be used with multiple tables.  Exiting." >&2
    exit 1
  fi
else
  echo "Need [-t] SOURCETABLE argument" >&2
fi

if [ -z "$DBNAME" ] || [ -z "$DBEXPORT" ] || [ -z "$SOURCETABLES" ]; then
  exit 1
fi

#DBDATA=${DBVOL}/data

#DBDATA=/db/mysql/data/swap_test
echo "DBNAME:$DBNAME SOURCETABLE:$SOURCETABLE DBEXPORT:$DBEXPORT PARTLIST:$PARTLIST"
sleep 2
MYSQLDATADIR=$(find /db*/mysql /home/mysql /var/lib/mysql /data*/mysql -name user.frm 2>/dev/null | grep mysql.user.frm | head -1 | sed -e 's/mysql.user.frm//')
if cd $MYSQLDATADIR/${DBNAME}; then
  DBDATA=$(/bin/pwd)
  echo "Found data directory for $DBNAME: $DBDATA"
else
  echo "Could not find database directory (zero or more than one found)" >&2
  exit 1
fi

export MYSQL_OPTS="-u root $DBNAME"

if echo "$DBEXPORT" | grep -iq "[:@]"; then
  REMOTE=1
  if echo "$DBEXPORT" | grep -q "@"; then
    remoteuser=$(echo $DBEXPORT | cut -d'@' -f1)
  else
    remoteuser=`whoami`
  fi
  sshcmd="ssh -q -l $remoteuser -o compressionlevel=1 -o cipher=none"
  if [ -f "${HOME}/.ssh/id_rsa" ]; then
    sshcmd="$sshcmd -i ${HOME}/.ssh/id_rsa"
  fi
  if [ -f "/root/.ssh/id_rsa" ]; then
    sshcmd="$sshcmd -i /root/.ssh/id_rsa"
  fi
  #sshcmd=$(echo "$sshcmd" | sed -e 's/ /\\ /g')
  export RSYNC_RSH="$sshcmd"
  cpcmd="rsync -av"
  echo "Exporting to remote directory $DBEXPORT via rsync ($cpcmd)" >&2
else
  LOCAL=1
  cpcmd="cp -av"
  if [ "$FORCE_RSYNC" ]; then
    cpcmd="rsync -av"
  fi
  if mkdir -p $DBEXPORT; then
    echo "Exporting to local directory $DBEXPORT" >&2
  else
    echo "Error creating $DBEXPORT directory" >&2
    exit 1
  fi
fi

run_mysql_pipe() {
  _PIPE=$1
  _OUT=$2
  if [ "$1" ] && [ "$2" ]; then
    echo "Starting mysql command pipe from $_PIPE to $_OUT ..." >&2
    ( tail --pid=$$ -F $_PIPE | mysql -r -s -n ${MYSQL_OPTS} >${_OUT} 2>&1 & echo $! > ${_PIPE}.pid )
    sleep 1
    PID=$(cat ${_PIPE}.pid)
    if [ "$PID" ]; then
      echo "Async persistent mysql client pid is $PID" >&2
      return 0
    else
      echo "Async persistent mysql client didn't generate a PID!" >&2
      return 1
    fi
  fi
}
  

for SOURCETABLE in $SOURCETABLES; do
  echo "Checking existence of $SOURCETABLE and that it's not locked already ..."
  if run_mysql_cmd "SHOW TABLES LIKE '${SOURCETABLE}'" | grep -q "${SOURCETABLE}"; then
    echo "OK: source ${SOURCETABLE} exists" >&2
  else
    echo "ERR: source $SOURCETABLE does not exist.  Exiting." >&2
    exit 1
  fi

  if run_mysql_cmd "show open tables where In_Use > 0" | grep -q "^${DBNAME}\b.*\b${SOURCETABLE}\b"; then
    echo "ERR: Source table $SOURCETABLE is locked.  Cannot proceed." >&2
    exit 1
  else
    echo "OK: $SOURCETABLE is not locked.  Proceeding." >&2
  fi
done

if [ "$TESTONLY" ]; then
  echo "Testonly.  Exiting."
  exit 0
fi
PIPE=$(mktemp /tmp/mysql_in_XXXXXX)
OUT=$(mktemp /tmp/mysql_out_XXXXXX)

echo "Starting async mysql pipeline" >&2
run_mysql_pipe $PIPE $OUT

PID=$(cat ${PIPE}.pid)

SOURCETABLES2=$(echo "$SOURCETABLES" | tr -s " \n" "," | sed -e "s/,$//")
echo "*** Flushing tables ${SOURCETABLES2} with ${FLUSHTIMEOUT} second timeout ..." >&2
echo "FLUSH TABLES ${SOURCETABLES2} WITH READ LOCK;" >> $PIPE
echo "SELECT 'READY1';" >> $PIPE
X=$FLUSHTIMEOUT; OK=""
while [ $X -gt 0 ]; do
  X=$((X-1))
  if grep -q READY1 $OUT; then
    OK=1
    break
  fi
  if grep -q ERROR $OUT; then
    echo "ERR: Got error from mysql command:"
    cat $OUT
    kill -HUP $PID
    exit 1
  fi
  sleep 1
done

if [ "$OK" = "1" ]; then
  echo "OK: FLUSH TABLES completed" >&2
else
  echo "ERR: Timeout waiting for FLUSH TABLES to complete" >&2
  kill -HUP $PID
  exit 1
fi

for SOURCETABLE in $SOURCETABLES; do
  if [ "$PARTLIST" ]; then
    PARTLIST=$(echo $PARTLIST | sed -e 's/^ *//g' -e 's/ *$//g')
    for PARTITIONID in $PARTLIST; do
      echo ""
      echo "*** Copying ${SOURCETABLE}:${PARTITIONID} to $DBEXPORT" >&2
      sh -c "${cpcmd} ${DBDATA}/${SOURCETABLE}#P#${PARTITIONID}.* ${DBEXPORT}/" | tee -a $TMPLOG
      if [ "$LOCAL" ] && [ "$gzcmd" ]; then
        sh -c "${gzcmd} ${DBEXPORT}/${SOURCETABLE}[#.]*" | tee -a $TMPLOG
      fi
    done
  else
    echo ""
    echo "*** Copying $SOURCETABLE to $DBEXPORT" >&2
    sh -c "${cpcmd} ${DBDATA}/${SOURCETABLE}[#.]* ${DBEXPORT}/" | tee -a $TMPLOG
    if [ "$LOCAL" ] && [ "$gzcmd" ]; then
      sh -c "${gzcmd} ${DBEXPORT}/${SOURCETABLE}[#.]*" | tee -a $TMPLOG
    fi
  fi
done

echo ""
echo "*** Unlocking table(s)" >&2
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
  echo "OK: UNLOCK TABLES completed" >&2
else
  echo "ERR: Timeout waiting for FLUSH TABLES to complete" >&2
  kill -HUP $PID
  exit 1
fi


echo "Quitting mysql pipeline" >&2
echo "\\q" >> $PIPE
sleep 1

#if [ "$LOCAL" ]; then
#  count=$(ls -ld ${DBEXPORT}/${SOURCETABLE}[#.]* | wc -l)
#fi
#count=$(cat $TMPLOG | wc -l)
echo "OK: finished exporting ${TABLECOUNT} tables to ${DBEXPORT}" >&2

rm $TMPLOG
exit 0
