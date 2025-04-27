#!/bin/bash
# PFLOCAL
# pvc-3-connect-volumes-to-hosts

SAN_SSHOPTS="-l pureuser -i ${HOME}/.ssh/storage-admin"
HOST_SSHOPTS="-q -l root -i ${HOME}/.ssh/root_rsa"
CREATEFS_DEF="mkfs.ext4 -N 1048576"
PAUSE=2

# Exit codes:
# 0: All OK, all actions succeeded
# 1: Runtime or parameter error (commandline args)
# 2: Config file error (variables or templates)
# 3: SAN reported an error or there was an unexpected condition relating to SAN object(s)
# 4: Host reported an error or there was an unexpected condition relating to host object(s)

### NO USER-SERVICEABLE PARTS BELOW THIS LINE
DEBUGLOG=/var/log/pvc/pvc-$(date +%Y%m%d).log
DPREFIX=pvc-3
DEBUG=0
OK_IF_CONNECTED=0
CF=""
CMDLINE="$0 $*"

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
  if [[ "$1" =~ -D ]]; then
    shift
    continue
  fi
  echo "ERROR: Unknown parameter: $1"
  exit 1
done

if [ -z "$CF" ]; then
  echo "ERROR: Please specify a gvc config file."
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

# templates defined in gvc.conf:
#PROJECT galaxy
#DATASET Galaxy_Search
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
for VAR in PROJECT DATASET VERSION SANWWVNPREFIX; do
  LINE=$(grep "^${VAR}\b" $CF | tr -s ' \t' ' ' | cut -d' ' -f2- | sed -e 's/ *$//g' )
  if [ -z "$LINE" ]; then
    dprint "ERROR: Variable $VAR not defined in $CF"
    exit 2
  fi
  eval ${VAR}=\$LINE
done

for TPL in SANVOLNAME OSMAPNAME OSMOUNT OSVOLLABEL DBNAME BASEVOL; do
  LINE=$(grep "^${TPL}_TPL\b" $CF | head -1 | tr -s ' \t' ' ' | cut -d' ' -f2- | sed -e 's/ *$//g' )
  if [ -z "$LINE" ] && [ "$TPL" != "BASEVOL" ]; then
    dprint "ERROR: Template ${TPL}_TPL not defined in $CF"
    exit 2
  fi
  dprint 4 "Template $TPL -> $LINE"
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
    if echo "$LINE" | grep -q "^PROVISION [^ ]* .*[a-z]"; then
      SAN=$(echo $LINE | tr -s '\t ' ' ' |cut -d' ' -f 2)
      HOSTS=$(bash -c "eval echo '$LINE' | tr -s ' \t' '\t' | cut -f 3-" | tr -s '\t\n ' ' ')
#      HOSTS=$(echo $LINE | tr -s '\t ' ' ' |cut -d' ' -f 3-)
      dprint 0 "Provision $SAN for $HOSTS"
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
  dprint 1 "Ignoring BASEVOL_TPL because CREATEVOL is defined"
  BASEVOL_TPL=""
fi
sleep 1
for SAN in $SANS; do
  dprint 1 "SAN:$SAN"
  HOSTS=${PROVARRAY[$SAN]}

### BEGIN check copyvols
  for HOST in $HOSTS; do
    ### Evaluate template variables
    for V in SANVOLNAME OSMAPNAME OSMOUNT OSVOLLABEL DBNAME BASEVOL; do
      TPLNAME="${V}_TPL"
       dprint 4 "VAR:$V TPL:$TPLNAME"
      eval $V="${!TPLNAME}"
    done
    if isup.sh $HOST >/dev/null; then
      dprint 1 "Checking $SANVOLNAME on $SAN for $HOST ..."
    else
      dprint 0 "  WARNING: Host $HOST is not online.  Skipping!"
      continue
    fi

    CONNECTVLUN=$(ssh ${SAN_SSHOPTS} ${SAN} "purevol list --connect ${SANVOLNAME} 2>&1" |grep -v ^Name |head -1)
    if echo "$CONNECTVLUN" | grep -qi "does not exist"; then
      dprint "ERROR: $SAN reports that volume $SANVOLNAME does not exist.  Cannot proceed."
      exit 3
    fi
    if echo "$CONNECTVLUN" | grep -qi "[a-z].*[0-9].*[a-z]"; then
      if echo "$CONNECTVLUN" | grep -qi " .*\b$HOST\b"; then
        dprint 0 "INFO: $SAN reports that volume $SANVOLNAME already connected to $HOST."
      else
        if [ "$OK_IF_CONNECTED" = 1 ]; then
          dprint 1 "NOTICE: Volume $SANVOLNAME already attached on $SAN, but -f option was used.  Proceeding."
        else
          dprint 0 "ERROR: $SAN reports that volume $SANVOLNAME is connected to another host.  Please disconnect this volume before proceeding."
          echo "If you're sure it's not mounted (or is mounted read-only) and want to proceed anyway, use the -f option on the commandline"
          echo ""
          echo "Response from $SAN command: purevol list --connect ${SANVOLNAME}"
          echo "$CONNECTVLUN"
          exit 3
        fi
      fi
    else
      dprint 1 "INFO: ${SANVOLNAME} on ${SAN} ready to be connected."
    fi
    [ "$PAUSE" ] && sleep $PAUSE
  done
### END check copyvols

  for HOST in $HOSTS; do
    if isup.sh $HOST >/dev/null; then
      dprint 1 "  HOST:$HOST"
    else
      dprint 0 "  WARNING: Host $HOST is not online.  Skipping!"
      continue
    fi

    dprint 1 "    DATASET:$DATASET"
    for V in SANVOLNAME OSMAPNAME OSMOUNT OSVOLLABEL DBNAME BASEVOL; do
      TPLNAME="${V}_TPL"
      dprint 4 "VAR:$V TPL:$TPLNAME"
      eval $V="${!TPLNAME}"
    done
#    echo "SAN:$SAN HOST:$HOST DATASET:$DATASET SANVOLNAME:$SANVOLNAME OSMAPNAME:$OSMAPNAME OSMOUNT:$OSMOUNT BASEVOL:$BASEVOL DBNAME:$DBNAME"

### GET WWVNs
    dprint 1 "Finding wwvn for $SANVOLNAME on $SAN ..."
    dprint 2 "ssh ${SAN_SSHOPTS} ${SAN} purevol list ${SANVOLNAME} | egrep -io '\b[0-9A-F]{24}\b' | tr A-Z a-z"
    sleep 2
    rm -f /tmp/q9
    ssh ${SAN_SSHOPTS} ${SAN} purevol list ${SANVOLNAME} | egrep -i "\b[0-9A-F]{24}\b" | tr A-Z a-z | tee /tmp/q9
    [ "$PAUSE" ] && sleep $PAUSE
    WWVN=$(cat /tmp/q9 | egrep -io '\b[0-9A-F]{24}\b' | tr A-Z a-z)
#    WWVN=$(ssh ${SAN_SSHOPTS} ${SAN} purevol list ${SANVOLNAME} | egrep -io "\b[0-9A-F]{24}\b" | tr A-Z a-z)
    dprint 1 "$SANVOLNAME wwvn:$WWVN"
    if [ "$WWVN" ]; then
      if [ "$TESTONLY" ]; then
        dprint 0 "TESTONLY: Would connect $SANVOLNAME on $SAN to $HOST"
      else
        C="purevol connect --host $HOST $SANVOLNAME"
        dprint 4 "purecmd: $C"
        R=$(ssh ${SAN_SSHOPTS} ${SAN} "$C" </dev/null 2>&1)
        if [ "$R" ]; then dprint 3 "$R"; fi
      fi
    else
      dprint 0 "ERROR: Could not find volume $SANVOLNAME on $SAN"
      exit 3
    fi
    [ "$PAUSE" ] && sleep $PAUSE
###

  # Wait for new VLUNs to register with HBA/SAN
    if [ "$TESTONLY" ]; then
      dprint 0 "TESTONLY: Would tell host $HOST to rescan scsi bus"
    else
      dprint 1 "INFO: telling $HOST to rescan FC/SCSI bus"
      if  ping -i 0.2 -c1 -w1 $HOST >/dev/null 2>/dev/null ; then
        #ssh ${HOST_SSHOPTS} $HOST "rescan-scsi-bus.sh >/dev/null 2>/dev/null"
        ssh ${HOST_SSHOPTS} $HOST "find /sys/class/fc_host -name 'host*' -printf '%f\n' | while read fchost; do echo '- - -' > /sys/class/scsi_host/\${fchost}/scan; done"
      else
        dprint 0 "WARNING: $HOST unreachable. Skipping"
        sleep 1
      fi
    fi
  # End of HOST loop
  done

# End of SAN loop
done
if [ "$TESTONLY" ]; then
  dprint 0 "$_0 completed tests.  If no errors, run again without the -t option:"
  dprint 0 "# $CMDLINE" | sed -e 's/ -t//g'
else
  dprint 0 "$PROGNAME complete.  If no errors, proceed to next step."
fi
exit 0
