#!/bin/bash
# PFLOCAL
# pvc-5-install-procs

SAN_SSHOPTS="-q -l pureuser -i ${HOME}/.ssh/storage-admin"
HOST_SSHOPTS="-q -l root -i ${HOME}/.ssh/root_rsa"
CREATEFS_DEF="mkfs.ext4 -N 1048576"

# Exit codes:
# 0: All OK, all actions succeeded
# 1: Runtime or parameter error (commandline args)
# 2: Config file error (variables or templates)
# 3: SAN reported an error or there was an unexpected condition relating to SAN object(s)
# 4: Host reported an error or there was an unexpected condition relating to host object(s)
# 5: DB reported an error or there was an unexpected condition relating to configuring database object(s)

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
    echo "TESTONLY option selected (not making any changes on SAN or hosts)"
    sleep 1
    shift
    continue
  fi
  if [ "$1" = "-n" ]; then
    NOLINK=1
    echo "NOLINK option selected (not creating symlinks in mysql datadir to new databases)"
    sleep 1
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

# templates defined in gvc.conf:
#PROJECT galaxy
#DATASET search person
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
for VAR in PROJECT DATASET VERSION SANWWVNPREFIX MYSQLDATADIR MOUNTPOINTDIR BRIDGETABLES; do
  LINE=$(grep "^${VAR}\b" $CF | tr -s ' \t' ' ' | cut -d' ' -f2- | sed -e 's/ *$//g')
  echo "[DEBUG] $VAR = $LINE"
  if [ -z "$LINE" ] && [ "$VAR" != "BRIDGETABLES" ]; then
    echo "ERROR: Variable $VAR not defined in $CF"
    exit 2
  fi
  eval ${VAR}=\$LINE
done

for TPL in SANVOLNAME OSMAPNAME OSMOUNT OSVOLLABEL DBNAME BASEVOL; do
  LINE=$(grep "^${TPL}_TPL\b" $CF | head -1 | tr -s ' \t' ' ' | cut -d' ' -f2- | sed -e 's/ *$//g')
  if [ -z "$LINE" ] && [ "$TPL" != "BASEVOL" ]; then
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
      POSTMOUNT_CMD="$(echo "$LINE" | tr -s '\t ' ' ' | cut -d' ' -f 2-)"
    fi
    if echo "$LINE" | grep -q "^PROVISION [^ ]* .*[a-z]"; then
      SAN=$(echo $LINE | tr -s '\t ' ' ' |cut -d' ' -f 2)
      HOSTS=$(bash -c "eval echo '$LINE' | tr -s ' \t' '\t' | cut -f 3-" | tr -s '\t\n ' ' ')
#      HOSTS=$(echo $LINE | tr -s '\t ' ' ' |cut -d' ' -f 3-)
      echo "Provision $SAN for $HOSTS"
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
  echo "Ignoring BASEVOL_TPL because CREATEVOL is defined"
  BASEVOL_TPL=""
fi
ALLHOSTS=""
for SAN in $SANS; do
  echo "SAN:$SAN"
  HOSTS="${PROVARRAY[$SAN]}"
  if [ "$ALLHOSTS" ]; then
    ALLHOSTS="$ALLHOSTS $HOSTS"
  else 
    ALLHOSTS="$HOSTS"
  fi
done
ALLHOSTS=$(echo "$ALLHOSTS" | tr -s ' ' '\n' | sort |uniq | tr '\n' ' ')

# run for all hosts provisioned on all SANs
for HOST in $ALLHOSTS; do
  if isup.sh $HOST >/dev/null; then
    echo "  HOST:$HOST"
  else
    echo "  WARNING: Host $HOST is not online.  Skipping!"
    continue
  fi

  echo "    DATASET:$DATASET"
  for V in SANVOLNAME OSMAPNAME OSMOUNT OSVOLLABEL DBNAME BASEVOL; do
    TPLNAME="${V}_TPL"
#   echo "VAR:$V TPL:$TPLNAME"
    eval $V="${!TPLNAME}"
  done
#  echo "SAN:$SAN HOST:$HOST DATASET:$DATASET SANVOLNAME:$SANVOLNAME OSMAPNAME:$OSMAPNAME OSMOUNT:$OSMOUNT BASEVOL:$BASEVOL DBNAME:$DBNAME"

  if [ "$MYSQLDATADIR" = "." ] || [ "$DBNAME" = "." ] ; then
    echo "Not installing SQL scripts because either MYSQLDATADIR or DBNAME is blank"
    NOLINK=1
  else 
    if ping -i 0.2 -c1 -w1 ${HOST} 2>/dev/null >/dev/null ; then
      if [ "$TESTONLY" ]; then
#        RESP=$(ssh ${HOST_SSHOPTS} ${HOST} "cd ${MOUNTPOINTDIR}/${OSMOUNT}/meta && mysql-install-sql-scripts.sh -t -d $DBNAME || echo 'ERROR: could not install sql scripts in ${MOUNTPOINTDIR}/${OSMOUNT}/meta'" )
	echo "TESTONLY: not installing sql scripts"
      else
#        RESP=$(ssh ${HOST_SSHOPTS} ${HOST} "cd ${MOUNTPOINTDIR}/${OSMOUNT}/meta && mysql-install-sql-scripts.sh -d $DBNAME || echo 'ERROR: could not install sql scripts in ${MOUNTPOINTDIR}/${OSMOUNT}/meta'" )
        RESP=$(ssh ${HOST_SSHOPTS} ${HOST} "cd ${MOUNTPOINTDIR}/${OSMOUNT}/meta && if which mysql-deploy-db-tasks.sh >/dev/null; then mysql-deploy-db-tasks.sh; else mysql-install-sql-scripts.sh -d $DBNAME || echo 'ERROR: could not install sql scripts in ${MOUNTPOINTDIR}/${OSMOUNT}/meta'; fi " )
      fi
      echo "$RESP"
      if echo "$RESP" | grep -q ERROR; then
        ERR=5
      fi         
    else
      echo "Host $HOST was unreachable. Skipping."
    fi
  fi

# End of HOST loop
done
echo ""
if [ "$ERR" ]; then
  echo "Errors occurred.  Exiting."
  exit $ERR
fi

echo ""
if [ "$TESTONLY" ]; then
  echo "$PROGNAME completed tests.  If no errors, run again without the -t option:"
  echo "$CMDLINE" | sed -e 's/ -t//g'
else
  echo "Stored procedures installed to $ALLHOSTS"
  echo "$PROGNAME complete.  If no errors, proceed to next step."
fi
exit 0
