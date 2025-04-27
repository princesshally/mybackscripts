#!/bin/bash
# PFLOCAL
# pvc-4-mount-filesystems

SAN_SSHOPTS="-q -l pureuser -i ${HOME}/.ssh/storage-admin"
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
DPREFIX=pvc-4
DEBUG=0
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
      dprint "ERROR: Unknown option: $1"
      exit 1
    else
      CF="$1"
    fi
    shift
    continue
  fi
  if [ "$1" = "-t" ]; then
    TESTONLY=1
    dprint "TESTONLY option selected (not making any changes on SAN or hosts)"
    sleep 1
    shift
    continue
  fi
  if [ "$1" = "-n" ]; then
    NOLINK=1
    dprint "NOLINK option selected (not creating symlinks in mysql datadir to new databases)"
    sleep 1
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
for VAR in PROJECT DATASET VERSION SANWWVNPREFIX MYSQLDATADIR MOUNTPOINTDIR; do
  LINE=$(grep "^${VAR}\b" $CF | tr -s ' \t' ' ' | cut -d' ' -f2- | sed -e 's/ *$//g' )
  dprint 4 " $VAR = $LINE"
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
    if echo "$LINE" | grep -q "^POSTMOUNT[_CMD]* .*[a-z]"; then
      POSTMOUNT_CMD="$(echo "$LINE" | tr -s '\t ' ' ' | cut -d' ' -f 2-)"
      dprint 1 "Found POSTMOUNT_CMD: $POSTMOUNT_CMD"
    fi
    if echo "$LINE" | grep -q "^PROVISION [^ ]* .*[a-z]"; then
      SAN=$(echo $LINE | tr -s '\t ' ' ' |cut -d' ' -f 2)
      HOSTS=$(bash -c "eval echo '$LINE' | tr -s ' \t' '\t' | cut -f 3-" | tr -s '\t\n ' ' ')
#      HOSTS=$(echo $LINE | tr -s '\t ' ' ' |cut -d' ' -f 3-)
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
  dprint "Ignoring BASEVOL_TPL because CREATEVOL is defined"
  BASEVOL_TPL=""
fi
sleep 1
for SAN in $SANS; do
  dprint 1 "SAN:$SAN"
  HOSTS="${PROVARRAY[$SAN]}"

### BEGIN check copyvols
  for HOST in $HOSTS; do
    ### Evaluate template variables
    for V in SANVOLNAME OSMAPNAME OSMOUNT OSVOLLABEL DBNAME BASEVOL; do
      TPLNAME="${V}_TPL"
        dprint 4 "VAR:$V TPL:$TPLNAME"
      eval $V="${!TPLNAME}"
    done
    if isup.sh $HOST >/dev/null; then
      dprint "Checking $SANVOLNAME on $SAN ..."
    else
      dprint "WARNING: Host $HOST is not online.  Skipping!"
      continue
    fi

    CONNECTVLUN=$(ssh ${SAN_SSHOPTS} ${SAN} purevol list --connect ${SANVOLNAME} |grep -v ^Name |head -1)
    if echo "$CONNECTVLUN" | grep -qi "does not exist"; then
      dprint "ERROR: $SAN reports that volume $SANVOLNAME does not exist.  Cannot proceed."
      exit 3
    fi
    if echo "$CONNECTVLUN" | grep -qi " .*\b$HOST\b"; then
      dprint 1 "INFO: $SAN reports that volume $SANVOLNAME already connected to $HOST."
    else
      if echo "$CONNECTVLUN" | grep -qi "[a-z].*[0-9].*[a-z]"; then
        if [ "$OK_IF_CONNECTED" = 1 ]; then
          dprint 1 "NOTICE: $SAN reports that volume $SANVOLNAME already connected to another host, but -f option was used.  Proceeding."
        else
          dprint "ERROR: $SAN reports that volume $SANVOLNAME already connected to another host.  Cannot proceed."
          dprint "If you're sure it's not mounted (or is mounted read-only) and want to proceed anyway, use the -f option on the commandline"
          dprint ""
          dprint "$SAN response for command: purevol list --connect ${SANVOLNAME}"
          dprint "$CONNECTVLUN"
          exit 3
        fi
      else
        dprint "ERROR: We expected to have ${SANVOLNAME} on ${SAN} connected to $HOST by this stage, but it's not."
        dprint  "ERROR: Cannot proceed."
        exit 3
      fi
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

    dprint 3 "    DATASET:$DATASET"
    for V in SANVOLNAME OSMAPNAME OSMOUNT OSVOLLABEL DBNAME BASEVOL; do
      TPLNAME="${V}_TPL"
      eval $V="${!TPLNAME}"
      #[ "$TESTONLY" ] && echo "VAR:$V TPL:$TPLNAME VALUE:$V"
    done
    [ "$TESTONLY" ] && dprint "SAN:$SAN HOST:$HOST DATASET:$DATASET SANVOLNAME:$SANVOLNAME OSMAPNAME:$OSMAPNAME OSMOUNT:$OSMOUNT BASEVOL:$BASEVOL DBNAME:$DBNAME"

    if [ "$MYSQLDATADIR" = "." ] || [ "$DBNAME" = "." ] ; then
      dprint 1 "Not creating links because MYSQLDATADIR or DBNAME are blank"
      NOLINK=1
    fi
    if ping -i 0.2 -c1 -w1 ${HOST} 2>/dev/null >/dev/null ; then
      if [ "$TESTONLY" ]; then
        [ "$CREATEFS_CMD" ] && dprint "TESTONLY: Would create filesystem on $OSMAPNAME with command $CREATEFS_CMD /dev/mapper/$OSMAPNAME"
        dprint "TESTONLY: Would set label $OSVOLLABEL on $OSMAPNAME on $HOST"
        dprint "TESTONLY: Would mount map $OSMAPNAME to ${MOUNTPOINTDIR}/$OSMOUNT on $HOST"
        ssh ${HOST_SSHOPTS} ${HOST} "grep '\b${OSMOUNT}\b' /etc/fstab && echo 'TESTONLY: OK: $OSMOUNT found in /etc/fstab' || echo 'WARNING: Could not find $OSMOUNT in /etc/fstab'"
        ssh ${HOST_SSHOPTS} ${HOST} "grep '\b${OSMOUNT}\b' /proc/mounts && echo 'TESTONLY: WARNING: $OSMOUNT already mounted (found in /proc/mounts)'"
        [ "$POSTMOUNT_CMD" ] && echo "TESTONLY: Would run this command in ${MOUNTPOINTDIR}/${OSMOUNT}: $POSTMOUNT_CMD"
        [ "$NOLINK" ] && echo "TESTONLY: SKIPPING database symlinks" || echo "TESTONLY: Would create symlink ${MYSQLDATADIR}/${DBNAME} -> ${MOUNTPOINTDIR}/${OSMOUNT}/data on $HOST"
      else
        if [ "$CREATEFS_CMD" ]; then
          dprint 1 "CREATEFS_CMD: $CREATEFS_CMD"
          MKFSCMD="if dd if=/dev/mapper/${OSMAPNAME} bs=1k count=16 2>/dev/null | tr -d '\0' | grep -qa .; then if dd if=/dev/mapper/${OSMAPNAME} bs=1k count=16 2>/dev/null | grep -q '${OSVOLLABEL}'; then echo 'CREATEFS: fs already created with label ${OSVOLLABEL}'; else echo 'ERROR: /dev/mapper/$OSMAPNAME already contains data'; fi; else ${CREATEFS_CMD} /dev/mapper/${OSMAPNAME} || echo 'ERROR: mkfs'; fi"
          RESP=$(echo "$MKFSCMD" | ssh ${HOST_SSHOPTS} ${HOST} )
#          if echo "$RESP" | grep ERROR; then
            dprint 1 "CREATEFS: $RESP"
#          fi
#          sleep 1
        fi
        RESP=$(ssh ${HOST_SSHOPTS} ${HOST} "systemctl daemon-reload")
        [ "$RESP" ] && dprint 1 "systemct daemon-reload response: $RESP"
#        sleep 1
#        RESP=$(ssh ${HOST_SSHOPTS} ${HOST} "[ -e /dev/mapper/${OSMAPNAME} ] && e2label /dev/mapper/${OSMAPNAME} ${OSVOLLABEL} && echo 'Set label $OSVOLLABEL on $OSMAPNAME' || echo 'ERROR: could not find map $OSMAPNAME on $HOST'")
        RESP=$(ssh ${HOST_SSHOPTS} ${HOST} "[ -e /dev/mapper/${OSMAPNAME} ] || echo 'ERROR: could not find map $OSMAPNAME on $HOST'")
        dprint "$RESP"
        if echo "$RESP" | grep "ERROR:"; then
          dprint "Exiting.  Please fix the unfortunate situation on $HOST, then re-run this step."
          exit 4
        fi

	if [ "$OSVOLLABEL" ]; then
		ssh ${HOST_SSHOPTS} ${HOST} "e2label /dev/mapper/${OSMAPNAME} ${OSVOLLABEL} 2>/dev/null && echo 'Set label $OSVOLLABEL on $OSMAPNAME' || echo 'Warning: could not set label for $OSMAPNAME to ${OSVOLLABEL} on $HOST (safe to ignore)'"
	fi
	
        RESP=$(ssh ${HOST_SSHOPTS} ${HOST} "grep -q '\b${OSMOUNT}\b' /proc/mounts || if [ -e '/dev/mapper/${OSMAPNAME}' ] && grep -qv ${OSMOUNT} /proc/mounts; then mount ${MOUNTPOINTDIR}/${OSMOUNT} && echo 'Successfully mounted ${MOUNTPOINTDIR}/$OSMOUNT' || echo 'ERROR: Could not mount ${MOUNTPOINTDIR}/$OSMOUNT on $HOST'; else echo 'ERROR: map or mount error on $HOST'; fi")
        if echo "$RESP" | grep "ERROR:"; then
          dprint "Exiting. Please fix the unfortunate situation on $HOST, then re-run this step."
          exit 4
        fi
        if [ "$POSTMOUNT_CMD" ]; then
          echo "POSTMOUNT_CMD: $POSTMOUNT_CMD"
#          sleep 1
          CMD="if grep -q '\b${OSMOUNT}\b' /proc/mounts && cd '${MOUNTPOINTDIR}/${OSMOUNT}'; then (${POSTMOUNT_CMD}) && echo 'POSTMOUNT: OK' || echo 'Error: ${POSTMOUNT_CMD} failed'; else echo 'Error: Could not chdir to ${OSMOUNT}'; fi"
          RESP=$(echo "$CMD" | ssh ${HOST_SSHOPTS} ${HOST} )
#          if echo "$RESP" | grep ERROR; then
            dprint 1 "POSTMOUNT: $RESP"
#          fi
#            sleep 1
        fi
        if [ "$NOLINK" ] ; then
          dprint 1 "SKIPPING database symlinks for ${DBNAME} on ${HOST}"
        else
### This routine will replace existing symlinks in MySQL data directory for given database
          RESP=$(ssh ${HOST_SSHOPTS} ${HOST} "if [ -d '${MOUNTPOINTDIR}/${OSMOUNT}/data' ]; then chown -R mysql:mysql '${MOUNTPOINTDIR}/${OSMOUNT}/'; [ -L '${MYSQLDATADIR}/${DBNAME}' ] && rm -f ${MYSQLDATADIR}/${DBNAME} && echo 'Replacing existing symbolic link for DB ${DBNAME} in ${MYSQLDATADIR}'; ln -s ${MOUNTPOINTDIR}/${OSMOUNT}/data ${MYSQLDATADIR}/${DBNAME}; else echo 'ERROR: ${MOUNTPOINTDIR}/$OSMOUNT/data does not appear to exist on $HOST'; fi")
          if [[ "$RESP" =~ ERROR ]]; then
            dprint "$RESP"
            exit 4
          fi
        fi
      fi
#      sleep 1
    else
      dprint "Host $HOST was unreachable. Skipping."
    fi

  # Wait for new VLUNs to register with HBA/SAN
  # End of HOST loop
  done

# End of SAN loop
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


