#!/bin/bash
# PFLOCAL
# pvc-1-create-vol.sh
# Creates or clones volumes on storage array

SAN_SSHOPTS="-q -l pureuser -i ${HOME}/.ssh/storage-admin"
HOST_SSHOPTS="-q -l root -i ${HOME}/.ssh/root_rsa"
CREATEFS_DEF="mkfs.ext4 -N 1048576"

# Exit codes:
# 0: All OK, all actions succeeded
# 1: Runtime or parameter error (commandline args)
# 2: Config file error (variables or templates)
# 3: SAN reported an error or there was an unexpected condition relating to SAN object(s)
# 4: Host reported an error or there was an unexpected condition relating to host object(s)

### NO USER-SERVICEABLE PARTS BELOW THIS LINE
DEBUGLOG=/var/log/pvc/pvc-$(date +%Y%m%d).log
DPREFIX=pvc-1
DEBUG=1
OK_IF_CONNECTED=0
CF=""
CMDLINE="$0 $*"
PROGNAME=$(echo "$0" | sed -e 's/^.*\///g')
PAUSE=2

if [ "${BASH_VERSINFO[0]}" -lt "4" ]; then
  echo "ERROR: $0 requires bash4 to function"
  exit 1
fi

if [ -x "/usr/local/bin/pvc-defaults.sh" ]; then
  . /usr/local/bin/pvc-defaults.sh
fi
if [ -e "/usr/local/bin/pvc-lib.sh" ]; then
  . /usr/local/bin/pvc-lib.sh
else
  echo "could not find /usr/local/bin/pvc-lib.sh - exiting"
  exit 1
fi

# Parse commandline parameters
while [ "$1" ]; do
  if [ -f "$1" ]; then
    if [ "$CF" ]; then
      dprint "ERROR: Unknown option: $1"
      exit 1
    else
      CF="$1"
    fi
    shift
    continue
  fi
  if [ "$1" = "-t" ]; then
    dprint "TESTONLY: No modifications will be made"
    sleep 1
    TESTONLY=1
    shift
    continue
  fi
  if [ "$1" = "-v" ]; then
    DEBUG=3
    shift
    continue
  fi

# Allow override if we detect that specified base volume is connected to a host
  if [ "$1" = "-f" ]; then
    OK_IF_CONNECTED=1
    shift
    continue
  fi
  if [[ "$1" =~ -D ]]; then
    shift
    continue
  fi
  dprint "ERROR: Unknown parameter: $1"
  exit 1
done

if [ -z "$CF" ]; then
  dprint "ERROR: Please specify a pvc config file."
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
#DATASET search person
#VERSION 20170303
#PROVISION pure3 galmysql07 galmysql09
#PROVISION pure4 galmysql06 galmysql08 galmysql10
# SRCHOST must be specified for initial copy from dev (when SOURCEVOL_TPL used)
# pvc-1 script connects to this host to initiate flush/sync/fstrim commands
#SRCHOST devmysql01

# New volume name template for Galaxy:
#SANVOLNAME_TPL ${HOST}-db-gal${DATASET,,}-${VERSION}
# New volume name template for Poseidon datasets:
#SANVOLNAME_TPL ${HOST}-db-${PROJECT}-${VERSION}

#OSMAPNAME_TPL P${SAN:4:1}SSD_db_gal${DATASET}_${VERSION}
#OSMAPNAME_TPL ${PROJECT^}_${DATASET^}_${VERSION}
#OSMOUNT_TPL /db/${PROJECT^}_${DATASET^}_${VERSION}
#OSVOLLABEL_TPL ${$DATASET:0:4}${VERSION}
#DBNAME_TPL ${DATASET}_${VERSION}
#BASEVOL_TPL base-db-${PROJECT}-${VERSION}
#SRCVOL_TPL ${SRCHOST}-db-${PROJECT}
#SRCDB_TPL ${DATASET}_${VERSION:0:8}
#SRCDB_TPL ${DATASET}

### Read important config variables from config file
declare -A PROVARRAY
for VAR in MOUNTPOINTDIR PROJECT DATASET VERSION SRCHOST SANWWVNPREFIX; do
  LINE=$(grep "^${VAR}\b" $CF | tr -s ' \t' ' ' | cut -d' ' -f2- | sed -e 's/ *$//g')
  if [ -z "$LINE" ] && [ "$VAR" != "SRCHOST" ]; then
    dprint "ERROR: Variable $VAR not defined in $CF"
    exit 2
  fi
  eval ${VAR}=\$LINE
  [ "$TESTONLY" ] && dprint 2 "CFG $VAR = $LINE"
done

for TPL in SANVOLNAME OSMAPNAME OSMOUNT OSVOLLABEL DBNAME BASEVOL SRCVOL SRCDB; do
  LINE=$(grep "^${TPL}_TPL\b" $CF | head -1 | tr -s ' \t' ' ' | cut -d' ' -f2- | sed -e 's/ *$//g')
  if [ -z "$LINE" ] && [ "$TPL" != "BASEVOL" ] && [ "$TPL" != "SRCVOL" ] && [ "$TPL" != "SRCDB" ]; then
    dprint "ERROR: Template ${TPL}_TPL not defined in $CF"
    exit 2
  fi
#  echo "Template $TPL -> $LINE"
  eval ${TPL}_TPL="\$LINE"
  [ "$TESTONLY" ] && dprint 2 "TEMPLATES: set ${TPL}_TPL to $LINE"
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
    if echo "$LINE" | grep -q "^PROVISION [^ ]* .*[a-z]"; then
      if echo "$LINE" | fgrep -q '*'; then
        dprint "ERROR: PROVISION line cannot include wildcards (but can employ sequences like {01..19}"
        exit 2
      fi
      SAN=$(echo $LINE | tr -s '\t ' ' ' |cut -d' ' -f 2)
      echo "$SAN" |grep -viq pure && echo "Warning: SAN specified on PROVISION line is not a purestorage array"
#      HOSTS=$(echo $LINE | tr -s '\t ' ' ' |cut -d' ' -f 3-)
      HOSTS=$(bash -c "eval echo '$LINE' | tr -s ' \t' '\t' | cut -f 3-" | tr -s '\t\n ' ' ')
      dprint 1 "Provision $SAN for $HOSTS"
      if [ "$SANS" ]; then
        SANS="$SANS $SAN"
      else
        SANS=$SAN
      fi
      if [ "${PROVARRAY[$SAN]}" ]; then
        PROVARRAY[$SAN]="${PROVARRAY[$SAN]} $HOSTS"
      else
        PROVARRAY[$SAN]="$HOSTS"
      fi
      PROVARRAY[$SAN]=$(echo ${PROVARRAY[$SAN]} | tr ' ' '\n' | sort |uniq | tr '\n' ' ' | sed -e 's/ $//')
    fi
  fi
done < $CF
echo ""
if [ "$BASEVOL_TPL" ] && [ "$CREATEVOL_SIZE" ]; then
  dprint 1 "Ignoring BASEVOL_TPL and SOURCEVOL_TPL because CREATEVOL is defined"
  BASEVOL_TPL=""
fi
if [ "$SRCVOL_TPL" ] && [ "$CREATEVOL_SIZE" ]; then
  dprint 1 "Ignoring BASEVOL_TPL and SOURCEVOL_TPL because CREATEVOL is defined"
  BASEVOL_TPL=""
  SRCVOL_TPL=""
fi
if [ "$SRCVOL_TPL" ] && [ -z "$SRCHOST" ]; then
  dprint "SRCVOL_TPL and SRCHOST must be specified together"
  exit 1
fi
if [ -z "$SRCVOL_TPL" ] && [ "$SRCHOST" ]; then
  dprint "SRCVOL_TPL and SRCHOST must be specified together"
  exit 1
fi
if [ "$SRCVOL_TPL" ] && [ "$BASEVOL_TPL" ]; then
  dprint "SRCVOL_TPL and BASEVOL_TPL are mutually exclusive"
  exit 1
fi
#echo "SRCVOL_TPL: $SRCVOL_TPL"
sleep 1

declare -A PREPAREVOL
for SAN in $SANS; do
  dprint 1 "SAN:$SAN"
  HOSTS=${PROVARRAY[$SAN]}


  if [ "$BASEVOL_TPL" ] || [ "$SRCVOL_TPL" ]; then
### BEGIN check base or src vols
# check for existence of base volume on array
###  BASEVOL="base-db-DBNAME-YYYYMMDD"
    if [ "$BASEVOL_TPL" ]; then
      eval BASEVOL="${BASEVOL_TPL}"
      [ "$TESTONLY" ] && dprint 1 "#1# SAN:$SAN DATASET:$DATASET BASEVOL_TPL:$BASEVOL_TPL BASEVOL:$BASEVOL SRCVOL:$SRCVOL"
    fi
    if [ "$SRCVOL_TPL" ]; then
      eval BASEVOL="${SRCVOL_TPL}"
      eval SRCVOL="${SRCVOL_TPL}"
      [ "$TESTONLY" ] && dprint 1 "#2# BASEVOL:$BASEVOL SRCVOL:$SRCVOL"
    fi
    if [ "$SRCDB_TPL" ]; then
      eval SRCDB="${SRCDB_TPL}"
      [ "$TESTONLY" ] && dprint 1 "#3# SRCDB:$SRCDB"
    fi
    eval OSMOUNT="${OSMOUNT_TPL}"
    dprint "Looking for $BASEVOL on $SAN ..."
    HD="${HOST}_${DATASET}"
    CONNECTVLUN=$(ssh ${SAN_SSHOPTS} ${SAN} "purevol list --connect ${BASEVOL} 2>&1" |grep -v ^Name |head -1)
    if echo "$CONNECTVLUN" | grep -qi "does not exist"; then
      dprint "ERROR: $SAN reports that volume $BASEVOL does not exist.  Cannot proceed."
      exit 3
    fi
    if echo "$CONNECTVLUN" | grep -qi "[a-z].*[0-9].*[a-z]"; then
      if [ "$OK_IF_CONNECTED" = 1 ] || [ "$SRCHOST" ]; then
        if [ "$SRCVOL" ]; then
          if [ -z "$SRCDB" ]; then
            SRCDB="$DATASET"
          fi
          dprint 1 "Will flushdb $SRCDB and sync/trim $SRCVOL on $SRCHOST before cloning."
          PREPAREVOL[$HD]=1
        else
          echo "NOTICE: Source volume $BASEVOL already attached on $SAN, but -f option was used.  Proceeding."
        fi
      else
        if [[ $CONNECTVLUN =~ repl ]]; then
          echo "Source volume $BASEVOL attached to replication target; okay to proceed"
        else
          echo "#############################################################################"
          echo "# ERROR: Source volume $BASEVOL already attached on $SAN.  Please disconnect"
          echo "# this volume from source host before proceeding."
          echo "# If you're sure it's not mounted (or is 'clean') and want to proceed anyway,"
          echo "# use the -f option on the commandline"
          echo "# after running this command on the source system (where $BASEVOL is mounted):"
          echo "# mysql-flush-db.sh $DATASET && sync && fstrim -v /db/${DATASET}*"
          echo "#############################################################################"
          echo ""
          sleep 2
          TESTONLY=1
        fi
      fi
      dprint 1 "Response from $SAN command: purevol list --connect ${BASEVOL}"
      dprint 1 "$CONNECTVLUN"
    else
      dprint "Found ${BASEVOL} on ${SAN}, ready to clone."
    fi
  fi
### END check basevols


  for HOST in $HOSTS; do
    if isup.sh $HOST >/dev/null; then
      dprint 1 "  HOST:$HOST"
    else
      dprint "Host $HOST is not online.  Skipping!"
      sleep 1
      continue
    fi
    dprint 1 "    DATASET:$DATASET"
    for V in SANVOLNAME OSMAPNAME OSMOUNT OSVOLLABEL DBNAME; do
      TPLNAME="${V}_TPL"
#      dprint 3 "VAR:$V TPL:$TPLNAME"
      eval $V="${!TPLNAME}"
    done
    [ "$TESTONLY" ] && dprint "     SANVOLNAME:$SANVOLNAME OSMAPNAME:$OSMAPNAME OSMOUNT:$OSMOUNT BASEVOL:$BASEVOL DBNAME:$DBNAME"
### Copy base volumes to per-host volumes here

    CONNECTVLUN=$(ssh ${SAN_SSHOPTS} ${SAN} purevol list ${SANVOLNAME} 2>/dev/null |grep -v ^Name |head -1)
    if echo "$CONNECTVLUN" | grep -qi "[a-z].*[0-9].*[a-z]"; then
      dprint "Target volume ${SAN}:${SANVOLNAME} already exists (skipping)"
      dprint 1 "${SAN}:$CONNECTVLUN"
    else
### createvol
      if [ "$CREATEVOL_SIZE" ]; then
        if [ "$TESTONLY" ]; then
          dprint "TESTONLY: would create volume ${SANVOLNAME} on $SAN for $HOST"
          WWVN="TEST_WWVN_NOT_REAL"
        else
          WWVN=$(ssh ${SAN_SSHOPTS} ${SAN} purevol create --size ${CREATEVOL_SIZE} ${SANVOLNAME} | grep "\b${SANVOLNAME}\b" | egrep -o '[A-F0-9]{24}' | tr A-Z a-z )
          dprint "New volume ${SANVOLNAME} has WWVN ${WWVN}"
        fi
      else
        if [ "$TESTONLY" ]; then
          dprint "TESTONLY: would connect to $SAN and clone $BASEVOL to $SANVOLNAME"
          WWVN="TEST_WWVN_NOT_REAL"
        else
### begin prepvol
          if [ "${PREPAREVOL[$HD]}" ]; then
            dprint 1 "flush/trim/sync ${SRCHOST}:\$(dbdir ${SRCDB}) ..."
            echo "Preparing source volume for cloning (flushdb/sync/fstrim) ..."
            #CMD="mysql-flush-db.sh ${SRCDB} && /usr/bin/aria_chk --zerofill /db/business_v3/data/business_search_w && sync && fstrim -v \$(dbdir ${SRCDB}) && mysql-flush-db.sh ${SRCDB} && mysql-flush-db.sh ${SRCDB} && /usr/bin/aria_chk --zerofill /db/business_v3/data/business_search_w && sync && echo OK || echo ERROR \$?"
            CMD="mysql-flush-db.sh ${SRCDB} && sync && fstrim -v \$(dbdir ${SRCDB}) && mysql-flush-db.sh ${SRCDB} && sync && echo OK || echo ERROR \$?"
            dprint 2 "CMD: $CMD"
            if [ "$TESTONLY" ]; then
              dprint "Would run this command on $SRCHOST: $CMD"
            else
              RESP=$(ssh ${HOST_SSHOPTS} ${SRCHOST} "${CMD}")
              if echo "$RESP" | grep -q ERROR; then
                dprint "ERROR: failed command on $SRCHOST: $CMD"
                exit 4
              else
                dprint 1 OK
              fi
            fi
          fi
### end prepvol
          TRIES=5
          PSAVE=$PAUSE
          while [ "$TRIES" -gt 0 ]; do
            dprint "Cloning ${BASEVOL} to ${SANVOLNAME} on ${SAN}"
            WWVN=$(ssh ${SAN_SSHOPTS} ${SAN} purevol copy ${BASEVOL} ${SANVOLNAME} | grep "\b${SANVOLNAME}\b" | egrep -o '[A-F0-9]{24}' | tr A-Z a-z )
            if [ "$WWVN" ]; then
              dprint 1 "New volume has WWVN ${WWVN}"
              break
            else
              dprint "Clone cmd failed on ${SAN}.  Trying again and increasing pause time ..."
            fi
            [ "$PAUSE" ] && sleep $PAUSE
            if [ "$PAUSE" ]; then
              PAUSE=$((PAUSE+3))
            else
              PAUSE=1
            fi
            TRIES=$((TRIES-1))
          done
          if [ -z "$WWVN" ]; then
            dprint "ERROR: Cloning ${BASEVOL} to ${SANVOLNAME} on ${SAN} failed.  Exiting."
            exit 4
          fi
          PAUSE=$PSAVE
        fi
      fi
    fi
    echo

###
  done  # HOST
done  # SAN
echo ""
if [ "$TESTONLY" ]; then
  dprint "$PROGNAME test-run complete.  If no errors, run again without the -t option:"
  dprint "# $CMDLINE" | sed -e 's/ -t//g'
else
  dprint "$PROGNAME complete.  If no errors, proceed to next step."
fi
exit 0

