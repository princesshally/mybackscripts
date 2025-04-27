#!/bin/bash
# PFLOCAL
# pvc-2-mp-bindings-mounts.sh
# adds WWVN entries to multipath bindings and fs mounts to fstab

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
DPREFIX=pvc-2
DEBUG=0
SKIPMPHEALTH=0
OK_IF_CONNECTED=0
CF=""
CMDLINE="$0 $*"
PROGNAME=$(echo "$0" | sed -e 's/^.*\///g')

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
  if [ "$1" = "-s" ]; then
    SKIPMPHEALTH=1
    shift
    continue
  fi
  if [ "$1" = "-t" ]; then
    echo "TESTONLY: No modifications will be made"
    TESTONLY=1
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
  echo "ERROR: Unknown parameter: $1"
  exit 1
done

if [ -z "$CF" ]; then
  dprint "ERROR: Please specify a config file."
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

# templates defined in conf file:
#PROJECT galaxy
#DATASET search person
#VERSION 20170303
#PROVISION pure3 galmysql07 galmysql09
#PROVISION pure4 galmysql06 galmysql08 galmysql10
# SOURCEHOST must be specified for initial copy from dev (when SOURCEVOL_TPL used)
# pvc-1 script connects to this host to initiate flush/sync/fstrim commands
#SOURCEHOST devmysql01

#SANVOLNAME_TPL ${HOST}_db_$(echo $PROJECT | cut -c1-3)$(lc ${DATASET})_${VERSION}
#OSMAPNAME_TPL P$(echo $SAN|tr -dc 0-9|cut -c 1)SSD_db_gal${DATASET}_${VERSION}
#OSMAPNAME_TPL $(ucf ${PROJECT})_$(ucf ${DATASET})_${VERSION}
#OSMOUNT_TPL /db/$(ucf ${PROJECT})_$(ucf ${DATASET})_${VERSION}
#OSVOLLABEL_TPL $(echo $PROJECT | cut -c1)$(echo $DATASET | cut -c1)_${VERSION}
#DBNAME_TPL $(ucf ${PROJECT})_$(ucf ${DATASET})_${VERSION}
#BASEVOL_TPL base_db_$(echo $PROJECT | cut -c1-3)$(lc ${DATASET})_${VERSION}
#SOURCEVOL_TPL ${SOURCEHOST}-db-${PROJECT}

### Read important config variables from config file
declare -A PROVARRAY
for VAR in PROJECT DATASET VERSION SANWWVNPREFIX; do
  LINE=$(grep "^${VAR}\b" $CF | tr -s ' \t' ' ' | cut -d' ' -f2- | sed -e 's/ *$//g')
  if [ -z "$LINE" ]; then
    dprint "ERROR: Variable $VAR not defined in $CF"
    exit 2
  fi
  eval ${VAR}=\$LINE
done

for TPL in SANVOLNAME OSMAPNAME OSMOUNT OSVOLLABEL DBNAME BASEVOL; do
  LINE=$(grep "^${TPL}_TPL\b" $CF | head -1 | tr -s ' \t' ' ' | cut -d' ' -f2- | sed -e 's/ *$//g')
  if [ -z "$LINE" ] && [ "$TPL" != "BASEVOL" ]; then
    dprint "ERROR: Template ${TPL}_TPL not defined in $CF"
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
    if echo "$LINE" | grep -q "^PROVISION [^ ]* .*[a-z]"; then
      SAN=$(echo $LINE | tr -s '\t ' ' ' |cut -d' ' -f 2)
#      HOSTS=$(echo $LINE | tr -s '\t ' ' ' |cut -d' ' -f 3-)
      HOSTS=$(bash -c "eval echo '$LINE' | tr -s ' \t' '\t' | cut -f 3-" | tr -s '\t\n ' ' ')
      dprint "Provision $SAN for $HOSTS"
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
  dprint 1 echo "SAN:$SAN"
  HOSTS=${PROVARRAY[$SAN]}

  MPERROR=""
  if [ "$SKIPMPHEALTH" ]; then
    echo "WARNING: Skipping multipath healthcheck"
    sleep 1
  else
    for HOST in $HOSTS; do
      if isup.sh $HOST >/dev/null; then
        dprint 1 "  HOST:$HOST"
      else
        dprint "  WARNING: Host $HOST is not online.  Skipping multipath-healthcheck!"
        continue
      fi

      RESP=$(ssh ${HOST_SSHOPTS} ${HOST} "multipath-healthcheck.sh")
      if echo "$RESP" | egrep 'CRITICAL|ERROR'; then
        dprint "ERROR: multipath-healthcheck.sh failed on ${HOST}."
        dprint "Please re-run multipath-healthcheck.sh on that system to see details, then fix the problem before continuing."
        MPERROR=1
      fi
    done
  fi
  if [ "$MPERROR" ]; then
    dprint "Exiting."
    exit 4
  fi

# ssh -q pureuser@smf3-pure3 'purevol list *workplace-20230308' | sed -e 's/^\([^ ]*\) .* \([0-9A-F]\{24\}\)$/\1 \2/g'
#Name                                   Size  Source                   Created                  Serial
#base-db-workplace-20230308 53DB1B20241287BC000AE96D
#qa-posmysql02-db-workplace-20230308 53DB1B20241287BC000AE961
#smf3-posmysql01-db-workplace-20230308 53DB1B20241287BC000AE96E
#smf3-posmysql02-db-workplace-20230308 53DB1B20241287BC000AE96F
#smf3-posmysql03-db-workplace-20230308 53DB1B20241287BC000AE970
#smf3-posmysql04-db-workplace-20230308 53DB1B20241287BC000AE971


### BEGIN check copyvols
  for HOST in $HOSTS; do
    for V in SANVOLNAME OSMAPNAME OSMOUNT OSVOLLABEL DBNAME BASEVOL; do
      TPLNAME="${V}_TPL"
      dprint 3 "VAR:$V TPL:$TPLNAME"
      eval $V="${!TPLNAME}"
    done
    if isup.sh $HOST >/dev/null; then
      dprint "Checking $SANVOLNAME on $SAN for $HOST ..."
    else
      dprint "  WARNING: Host $HOST is not online.  Skipping!"
      continue
    fi

    CONNECTVLUN=$(ssh ${SAN_SSHOPTS} ${SAN} "purevol list --connect ${SANVOLNAME} 2>&1" |grep -v ^Name |head -1)
    if echo "$CONNECTVLUN" | grep -qi "does not exist"; then
      dprint "ERROR: ${SAN} reports that volume $SANVOLNAME does not exist.  Cannot proceed."
      exit 3
    fi
    if echo "$CONNECTVLUN" | grep -qi "[a-z].*[0-9].*[a-z]"; then
      if echo "$CONNECTVLUN" | grep -qi " .*\b$HOST\b"; then
        dprint "INFO: Volume $SANVOLNAME already connected on $SAN to $HOST."
      else
        if [ "$OK_IF_CONNECTED" = 1 ]; then
          dprint "NOTICE: Volume $SANVOLNAME already attached on $SAN, but -f option was used.  Proceeding."
        else
          dprint "ERROR: $SAN reports that volume $SANVOLNAME already attached to another host.  Please disconnect this volume before proceeding."
          dprint "If you're sure it's not mounted (or is mounted read-only) and want to proceed anyway, use the -f option on the commandline"
          dprint "$SAN response to command: purevol list --connect ${SANVOLNAME}"
          dprint "$CONNECTVLUN"
          echo ""
          exit 3
        fi
      fi
    else
      dprint 1 "INFO: ${SANVOLNAME} on ${SAN} ready to be attached."
    fi
    sleep 2
  done
### END check basevols

  for HOST in $HOSTS; do
    if isup.sh $HOST >/dev/null; then
      dprint 1 "  HOST:$HOST"
    else
      dprint "  WARNING: Host $HOST is not online.  Skipping!"
      continue
    fi

    dprint 1 "    DATASET:$DATASET"
    for V in SANVOLNAME OSMAPNAME OSMOUNT OSVOLLABEL DBNAME BASEVOL; do
      TPLNAME="${V}_TPL"
      dprint 2 "VAR:$V TPL:$TPLNAME"
      eval $V="${!TPLNAME}"
    done
    dprint 3 "SAN:$SAN HOST:$HOST DATASET:$DATASET SANVOLNAME:$SANVOLNAME OSMAPNAME:$OSMAPNAME OSMOUNT:$OSMOUNT BASEVOL:$BASEVOL DBNAME:$DBNAME"

### GET WWVNs
    sleep 2
    WWVN=$(ssh ${SAN_SSHOPTS} ${SAN} purevol list ${SANVOLNAME} | egrep -io "\b[0-9A-F]{24}\b" | tr A-Z a-z)
    dprint 1 "$SANVOLNAME wwvn: $WWVN"
    if [ "$WWVN" ]; then
      OSWWVN="${SANWWVNPREFIX}${WWVN}"
      if [ "$TESTONLY" ]; then
        dprint "TESTONLY: would add $WWVN ($OSWWVN) to $HOST bindings with map name $OSMAPNAME"
      else
        if isup.sh ${HOST} >/dev/null; then
          # Add multipath map to bindings (and removing prior entries for same WWVN)
          dprint 1 "Running commands on ${HOST} ..."
          ssh ${HOST_SSHOPTS} ${HOST} "sed -e '/${WWVN}$/d' -i /etc/multipath/bindings; sed -e '\$s/\$/\n${OSMAPNAME} ${OSWWVN}/' -i /etc/multipath/bindings"
          # Add fstab entry (and removing prior entries for same OSMAPNAME or OSWWVN)
          #ssh ${HOST_SSHOPTS} ${HOST} "sed -e '/^\/.*\b${OSMAPNAME}\b/d' -i /etc/fstab; sed -e '/^\/.*${OSWWVN}\b/d' -i /etc/fstab; sed -e '\$s/\$/\n\/dev\/disk\/by-id\/dm-uuid-mpath-${OSWWVN} \/db\/${OSMOUNT} ext4 nofail 1 2/' -i /etc/fstab"
          ssh ${HOST_SSHOPTS} ${HOST} "sed -e '/^\/.*\b${OSMAPNAME}\b/d' -i /etc/fstab; sed -e '/^\/.*${OSWWVN}\b/d' -i /etc/fstab; sed -e '\$s/\$/\n\/dev\/mapper\/${OSMAPNAME} \/db\/${OSMOUNT} ext4 nofail 1 2/' -i /etc/fstab"
          # Create mountpoint
#          echo "ssh step 3:"
          ssh ${HOST_SSHOPTS} ${HOST} "mkdir -p /db/${OSMOUNT} 2>/dev/null"
        else
          dprint "ERROR: host $HOST is not responding or not online"
          exit 3
        fi
      fi
    else
      echo "ERROR: Weird.  Couldn't find volume $SANVOLNAME on $SAN."
      echo "Please be sure step 1 was completed with same config file $CF"
      exit 3
    fi
  done

# Restart multipathd on all hosts so new bindings will be read
  if [ "$TESTONLY" ]; then
    dprint 1 "TESTONLY: would restart multipathd on each of $HOSTS"
  else
    for HOST in $HOSTS; do
      #ssh ${HOST_SSHOPTS} ${HOST} "service multipathd restart" 
      ssh ${HOST_SSHOPTS} ${HOST} "multipathd -kreconfigure"
    done
  fi
done
echo ""
if [ "$TESTONLY" ]; then
  dprint "$PROGNAME completed tests.  If no errors, run again without the -t option:"
  dprint "# $CMDLINE" | sed -e 's/ -t//g'
else
  dprint "Verify on hosts that mountpoints and fstab entries were created properly."
  dprint "$PROGNAME complete.  If no errors, proceed to next step."
fi
exit 0

