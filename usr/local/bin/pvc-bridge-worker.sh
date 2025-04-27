#!/bin/bash
# PFLOCAL
# PFDISTRIB mysql

SAN_SSHOPTS="-q -l pureuser -i ${HOME}/.ssh/storage-admin"
HOST_SSHOPTS="-q -l root -i ${HOME}/.ssh/root_rsa"

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

if [ -x "/usr/local/bin/pvc-defaults.sh" ]; then
  . /usr/local/bin/pvc-defaults.sh
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
  if [ "$1" = "-v" ]; then
    VERBOSE=1
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
  if [ "$1" = "-B" ]; then
    shift
    if [ "$1" ] && echo "$1" | egrep -qi "^[a-z]*-*mysql[0-9a-z.-]*$"; then
      if isup.sh "$1" >/dev/null; then
        BRIDGEHOST="$1"
        shift
        continue
      else
        echo "ERROR: specified host to copy bridge tables doesn't appear to be up"
        exit 4
      fi
    else
      echo "-B requires hostname to launch bridge table copy operation on"
      exit 1
    fi
  fi
  echo "ERROR: Unknown parameter: $1"
  exit 1
done


if [ -z "$CF" ]; then
  echo "ERROR: Please specify a pvc config file."
  exit 1
fi
###EAS
#exit 0

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
    echo -n "$*" | tr -cs 'a-zA-Z0-9' '-'
  else
    tr -cs 'a-zA-Z0-9' '-'
  fi
}

# templates defined in pvc.conf:
#PROJECT galaxy
#DATASETS search person
#VERSION 20170303
#PROVISION pure3 galmysql07 galmysql09
#PROVISION pure4 galmysql06 galmysql08 galmysql10

#SANVOLNAME_TPL ${HOST}_db_$(echo $PROJECT | cut -c1-3)$(lc ${DATASET})_${VERSION}
#OSMAPNAME_TPL P$(echo $SAN|tr -dc 0-9|cut -c 1)SSD_db_gal${DATASET}_${VERSION}
#OSMAPNAME_TPL $(ucf ${PROJECT})_$(ucf ${DATASET})_${VERSION}
#OSMOUNT_TPL /db/$(ucf ${PROJECT})_$(ucf ${DATASET})_${VERSION}
#OSVOLLABEL_TPL $(echo $PROJECT | cut -c1)$(echo $DATASETS | cut -c1)_${VERSION}
#DBNAME_TPL $(ucf ${PROJECT})_$(ucf ${DATASET})_${VERSION}
#BASEVOL_TPL base_db_$(echo $PROJECT | cut -c1-3)$(lc ${DATASET})_${VERSION}

### Read important config variables from config file
declare -A PROVARRAY
for VAR in PROJECT DATASETS VERSION SANWWVNPREFIX MYSQLDATADIR MOUNTPOINTDIR BRIDGETABLES; do
  LINE=$(grep "^${VAR}\b" $CF | tr '\t' ' ' | cut -d' ' -f2-)
  [ "$DEBUG" ] && echo "[DEBUG] $VAR = $LINE"
  if [ -z "$LINE" ] && [ "$VAR" != "BRIDGETABLES" ]; then
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
    if echo "$LINE" | grep -q "^PROVISION pure[^ ]* .*[a-z]"; then
      SAN=$(echo $LINE | tr -s '\t ' ' ' |cut -d' ' -f 2)
      HOSTS=$(echo $LINE | tr -s '\t ' ' ' |cut -d' ' -f 3-)
#      echo "Provision $SAN for $HOSTS"
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
ALLHOSTS=""
for SAN in $SANS; do
#  echo "SAN:$SAN"
  HOSTS="${PROVARRAY[$SAN]}"
  if [ "$ALLHOSTS" ]; then
    ALLHOSTS="$ALLHOSTS $HOSTS"
  else 
    ALLHOSTS="$HOSTS"
  fi
done
ALLHOSTS=$(echo "$ALLHOSTS" | tr -s ' ' '\n' | sort |uniq | tr '\n' ' ')

if [ "$BRIDGEHOST" ]; then
  HOST=$(echo "$ALLHOSTS" | grep -oi "\b${BRIDGEHOST}\b")
else
  echo "$0 requires -B <hostname> option"
  exit 1
fi

# run for all hosts provisioned on all SANs
if [ "$HOST" ]; then
#  echo "  HOST:$HOST"
  for DATASET in $DATASETS; do
#    echo "    DATASET:$DATASET"
    for V in SANVOLNAME OSMAPNAME OSMOUNT OSVOLLABEL DBNAME BASEVOL; do
      TPLNAME="${V}_TPL"
#     echo "VAR:$V TPL:$TPLNAME"
      eval $V="${!TPLNAME}"
    done
#    echo "SAN:$SAN HOST:$HOST DATASET:$DATASET SANVOLNAME:$SANVOLNAME OSMAPNAME:$OSMAPNAME OSMOUNT:$OSMOUNT BASEVOL:$BASEVOL DBNAME:$DBNAME"

    if [ "$MYSQLDATADIR" = "." ] || [ "$DBNAME" = "." ] ; then
      echo "Not installing SQL scripts because either MYSQLDATADIR or DBNAME is blank"
      NOLINK=1
    else 
      BRIDGE_SRCDIR="${MOUNTPOINTDIR}/${OSMOUNT}/bridge"
      BRIDGE_DSTDIR="\$(dbdir poseidon)/data"
      BRIDGE_TABLES="\$(find '${BRIDGE_SRCDIR}' -name '*.frm' -printf '%f\n' | cut -d. -f1 | tr -s '\n' ' ')"
      if isup.sh ${HOST} 2>/dev/null >/dev/null ; then
        if [ "$TESTONLY" ]; then
           RESP=$(ssh ${HOST_SSHOPTS} ${HOST} "if [ -d \"${BRIDGE_SRCDIR}\" ] && [ -d \"${BRIDGE_DSTDIR}\" ] && cd \"${BRIDGE_SRCDIR}\"; then for t in ${BRIDGE_TABLES}; do echo \"Would copy table \${t} from ${BRIDGE_SRCDIR} to ${BRIDGE_DSTDIR}\"; done; else echo \"ERROR: cannot find bridge table source ($BRIDGE_SRCDIR) or destination directory ($BRIDGE_DSTDIR) on host $HOST\"; fi" </dev/null)
        else
           [ "$VERBOSE" ] && echo "INFO: connecting to $HOST to install bridge tables from $BRIDGE_SRCDIR"
           RESP=$(ssh ${HOST_SSHOPTS} ${HOST} "if [ -d \"${BRIDGE_SRCDIR}\" ] && [ -d \"${BRIDGE_DSTDIR}\" ] && cd \"${BRIDGE_SRCDIR}\"; then for t in ${BRIDGE_TABLES}; do echo \"${HOST}: Copying bridge table \${t} from ${BRIDGE_SRCDIR} to ${BRIDGE_DSTDIR} ...\"; chown -R mysql:mysql ${BRIDGE_SRCDIR}; rsync -a ${BRIDGE_SRCDIR}/\${t}[.#]* ${BRIDGE_DSTDIR}/ && mysql poseidon -ve \"flush tables \$t\" || echo "ERROR: failed to copy table \$t"; done; else echo \"ERROR: cannot find bridge table source ($BRIDGE_SRCDIR) or destination directory ($BRIDGE_DSTDIR) on host $HOST\"; fi" </dev/null)
        fi
        echo "$RESP"
        if echo "$RESP" | grep -q ERROR; then
          ERR=5
        fi         
        sleep 1
      else
        echo "Host $HOST was unreachable. Skipping."
      fi
    fi

  # End of DATASET loop
  done
else
  echo "ERROR: Specified host isn't in the PROVISION list"
  exit 1
fi
echo ""
if [ "$ERR" ]; then
  echo "Errors occurred.  Exiting."
  exit $ERR
fi
if [ "$TESTONLY" ]; then
  echo "TESTONLY: Complete.  Re-run without -t option to install bridge tables."
else
  echo "Complete.  Bridge tables copied and tables flushed on $HOST"
fi
exit 0

