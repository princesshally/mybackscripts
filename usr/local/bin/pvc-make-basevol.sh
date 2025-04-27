#!/bin/bash
# PFLOCAL
# pvc-make-basevol-from-qa.sh
# Connects to qa mysql host, flushes database, trims fs, clones vol to base-db-DBNAME-VERSION.sh
# DB must already have version/date ID on source QA DB host ("workplace_20181109" vs "workplace")
# and VERSION id needs to be defined in specified pvc config file

SAN_SSHOPTS="-l pureuser -i ${HOME}/.ssh/storage-admin"
HOST_SSHOPTS="-q -l root -i ${HOME}/.ssh/root_rsa"
CREATEFS_DEF="mkfs.ext4 -N 1048576"


# Exit codes:
# 0: All OK, all actions succeeded
# 1: Runtime or parameter error (commandline args)
# 2: Config file error (variables or templates)
# 3: SAN reported an error or there was an unexpected condition relating to SAN object(s)
# 4: Host reported an error or there was an unexpected condition relating to host object(s)

### NO USER-SERVICEABLE PARTS BELOW THIS LINE
OK_IF_CONNECTED=0
CF=""
CMDLINE="$0 $*"
PROGNAME=$(echo "$0" | sed -e 's/^.*\///g')

if [ -x "/usr/local/bin/pvc-defaults.sh" ]; then
  . /usr/local/bin/pvc-defaults.sh
fi

if [ "${BASH_VERSINFO[0]}" -lt "4" ]; then
  echo "ERROR: $0 requires bash4 to function"
  exit 1
fi

# Parse commandline parameters
while [ "$1" ]; do
  if [ -f "$1" ]; then
    if [ "$CF" ]; then
      echo "ERROR: Unknown option: $1"
      exit 1
    else
      CF="$1"
    fi
    shift
    continue
  fi
  if [ "$1" = "-t" ]; then
    TESTONLY=1
    shift
    continue
  fi
  if [ "$1" = "-f" ]; then
    OK_IF_CONNECTED=1
    shift
    continue
  fi
  echo "ERROR: Unknown parameter: $1"
  exit 1
done

if [ -z "$CF" ]; then
  echo "ERROR: Please specify a pvc config file."
  exit 1
fi

### Define functions to be used in template expansion
# lc: Lower-case all characters
lc() {
  if [ "$1" ]; then
    echo "$*" | tr A-Z a-z
  else
    tr A-Z a-z
  fi
}

# uc: Upper-case all characters
uc() {
  if [ "$1" ]; then
    echo "$*" | tr a-z A-Z
  else
    tr a-z A-Z
  fi
}

# ucf: Upper-case first character per word
ucf() {
  if [ "$1" ]; then
    echo "$*" | sed -e "s/\b\(.\)/\u\1/g"
  else
    sed -e "s/\b\(.\)/\u\1/g"
  fi
}

# ul: convert non-alphanum to underlines
ul() {
  if [ "$1" ]; then
    echo "$*" | tr -cs 'a-zA-Z0-9\n' '_'
  else
    tr -cs 'a-zA-Z0-9\n' '_'
  fi
}

# hy: convert non-alphanum to hyphen
hy() {
  if [ "$1" ]; then
    echo "$*" | tr -cs 'a-zA-Z0-9\n' '-'
  else
    tr -cs 'a-zA-Z0-9\n' '-'
  fi
}

# templates defined in pvc config:
#PROJECT galaxy
#DATASET search
#VERSION 20170303
#PROVISION pure3 galmysql07 galmysql09
#PROVISION pure4 galmysql06 galmysql08 galmysql10

#SANVOLNAME_TPL ${HOST}_db_$(echo $PROJECT | cut -c1-3)$(lc ${DATASET})_${VERSION}
#OSMAPNAME_TPL P$(echo $SAN|tr -dc 0-9|cut -c 1)SSD_db_gal${DATASET}_${VERSION}
#OSMAPNAME_TPL $(ucf ${PROJECT})_$(ucf ${DATASET})_${VERSION}
#OSMOUNT_TPL /db/$(ucf ${PROJECT})_$(ucf ${DATASET})_${VERSION}
#OSVOLLABEL_TPL $(echo $PROJECT | cut -c1)$(echo $DATASET | cut -c1)_${VERSION}
#DBNAME_TPL $(ucf ${PROJECT})_$(ucf ${DATASET})_${VERSION}
#BASEVOL_TPL base_db_$(echo $PROJECT | cut -c1-3)$(lc ${DATASET})_${VERSION}

### Read important config variables from config file
declare -A PROVARRAY
for VAR in MOUNTPOINTDIR PROJECT DATASET VERSION SANWWVNPREFIX; do
  LINE=$(grep "^${VAR}\b" $CF | tr '\t' ' ' | cut -d' ' -f2-)
  if [ -z "$LINE" ]; then
    echo "ERROR: Variable $VAR not defined in $CF"
    exit 2
  fi
  eval ${VAR}=\$LINE
done

for TPL in SANVOLNAME OSMAPNAME OSMOUNT OSVOLLABEL DBNAME BASEVOL; do
  LINE=$(grep "^${TPL}_TPL\b" $CF | head -1 | tr '\t' ' ' | cut -d' ' -f2-)
  if [ -z "$LINE" ]; then
    echo "ERROR: Template ${TPL}_TPL not defined in $CF"
    exit 2
  fi
#  echo "Template $TPL -> $LINE"
  eval ${TPL}_TPL="\$LINE"
done

while read LINE; do 
  if echo "$LINE" | grep -q "^[A-Za-z]"; then
    if echo "$LINE" | grep -q "^CREATEVOL  *[0-9][0-9]*[MGT]"; then
      CREATEVOL_SIZE="$(echo $LINE | tr -s '\t ' ' ' | cut -d' ' -f 2)"
      if echo "$LINE" | grep -q "^CREATEVOL  *[0-9][0-9]*[MGT]  *mkfs"; then
        CREATEFS_CMD="$(echo $LINE | tr -s '\t ' ' ' | cut -d' ' -f 3-)"
      else
        CREATEFS_CMD="$CREATEFS_DEF"
      fi
    fi
    if echo "$LINE" | grep -q "^POSTMOUNT .*[a-z]"; then
      POSTMOUNT_CMD="$(echo $LINE | tr -s '\t ' ' ' | cut -d' ' -f 2-)"
    fi
    if echo "$LINE" | grep -q "^PROVISION .*pure[^ ]* .*[a-z]"; then
      SAN=$(echo $LINE | tr -s '\t ' ' ' |cut -d' ' -f 2)
      HOSTS=$(bash -c "eval echo '$LINE' | tr -s ' \t' '\t' | cut -f 3-" | tr -s '\t\n ' ' ')
#      HOSTS=$(echo $LINE | tr -s '\t ' ' ' |cut -d' ' -f 3-)
      echo "Provision $SAN for $HOSTS"
      if [ "$SANS" ]; then
        echo "ERROR: $0 expects exactly one PROVISION line with one SAN and one HOST in $CF"
        exit 2
        SANS="$SANS $SAN"
      else
        SANS=$SAN
      fi
      if [ "${PROVARRAY[$SAN]}" ]; then
        echo "ERROR: $0 expects exactly one PROVISION line with one SAN and one HOST in $CF"
        exit 2
        PROVARRAY[$SAN]="${PROVARRAY[$SAN]} $HOSTS"
      else
        PROVARRAY[$SAN]="$HOSTS"
      fi
      PROVARRAY[$SAN]=$(echo ${PROVARRAY[$SAN]} | tr ' ' '\n' | sort |uniq | tr '\n' ' ' | sed -e 's/ $//')
    fi
  fi
done < $CF
echo ""
if [ -z "$BASEVOL_TPL" ]; then
  echo "$0 requires BASEVOL_TPL to be defined"
  exit 2
fi
sleep 1
declare -A PREPAREVOL
for SAN in $SANS; do
  echo "SAN:$SAN"
  HOSTS=${PROVARRAY[$SAN]}


### BEGIN check source vols
  for HOST in $HOSTS; do
    for V in SANVOLNAME OSMAPNAME OSMOUNT OSVOLLABEL DBNAME BASEVOL; do
      TPLNAME="${V}_TPL"
#     echo "VAR:$V TPL:$TPLNAME"
      eval $V="${!TPLNAME}"
    done
    echo "Checking $SANVOLNAME on $SAN ..."
    HD="${HOST}_${DATASET}"
    CONNECTVLUN=$(ssh ${SAN_SSHOPTS} ${SAN} "purevol list --connect ${SANVOLNAME} 2>&1" |grep -v ^Name |head -1)
    if echo "$CONNECTVLUN" | grep -qi "does not exist"; then
      echo "ERROR: ${SAN} reports that source volume $SANVOLNAME does not exist.  Cannot proceed."
      exit 3
    fi
    if echo "$CONNECTVLUN" | grep -qi "[a-z].*[0-9].*[a-z]"; then
      if echo "$CONNECTVLUN" | grep -qi " .*\b$HOST\b"; then
        echo "INFO: Volume $SANVOLNAME already connected on $SAN to $HOST.  Will flushdb/trim/sync before cloning."
        PREPAREVOL[$HD]=1
      else
        if [ "$OK_IF_CONNECTED" = 1 ]; then
          echo "NOTICE: Volume $SANVOLNAME already attached on $SAN, but -f option was used.  Proceeding."
          PREPAREVOL[$HD]=1
        else
          echo "ERROR: $SAN reports that volume $SANVOLNAME is attached to a host other than $HOST.  Please disconnect this volume before proceeding."
          echo "If you're sure it's not mounted (or is mounted read-only) and want to proceed anyway, use the -f option on the commandline"
          echo ""
          echo "$SAN response to command: purevol list --connect ${SANVOLNAME}"
          echo "$CONNECTVLUN"
          exit 3
        fi
      fi
    else
      echo "INFO: ${SANVOLNAME} on ${SAN} ready to be cloned."
    fi
  done
### END check source vols


  for HOST in $HOSTS; do
    echo "  HOST:$HOST"
    HD="${HOST}_${DATASET}"
    echo "    DATASET:$DATASET"
    for V in SANVOLNAME OSMAPNAME OSMOUNT OSVOLLABEL DBNAME BASEVOL; do
      TPLNAME="${V}_TPL"
#      echo "VAR:$V TPL:$TPLNAME"
      eval $V="${!TPLNAME}"
    done
#    echo "SAN:$SAN HOST:$HOST DATASET:$DATASET SANVOLNAME:$SANVOLNAME OSMAPNAME:$OSMAPNAME OSMOUNT:$OSMOUNT BASEVOL:$BASEVOL DBNAME:$DBNAME"

    if [ "${PREPAREVOL[$HD]}" ]; then
      echo "flush/trim/sync ${HOST}:${MOUNTPOINTDIR}/${OSMOUNT} ..."
      CMD="mysql-flush-db.sh ${DBNAME} && sync && fstrim -v \$(dbdir $DBNAME) && mysql-flush-db.sh ${DBNAME} && sync && sync && echo OK || echo ERROR \$?"
      if [ "$TESTONLY" ]; then
        echo "Would run this command on $HOST: $CMD"
      else
        RESP=$(ssh ${HOST_SSHOPTS} ${HOST} "${CMD}")
        if echo "$RESP" | grep -q ERROR; then
          echo "ERROR running this command on $HOST: $CMD"
          exit 4
        else
          echo OK
        fi
      fi
    fi
    echo "clone ${SANVOLNAME} to ${BASEVOL} on ${SAN} ..."
    CMD="purevol copy --overwrite ${SANVOLNAME} ${BASEVOL}"
    if [ "$TESTONLY" ]; then
      echo "Would run this command on $SAN: $CMD"
    else
      RESP=$(ssh ${SAN_SSHOPTS} ${SAN} "${CMD}")
      if echo "$RESP" | grep -qi error; then
        echo "ERROR running this command on $SAN: $CMD"
        exit 3
      else
        echo OK
      fi
    fi
  done
done
echo ""
if [ "$TESTONLY" ]; then
  echo "$PROGNAME completed tests.  If no errors, run again without the -t option:"
  echo "# $CMDLINE" | sed -e 's/ -t//g'
else
  echo "$PROGNAME complete.  New base volume $BASEVOL on $SAN created."
fi
exit 0

