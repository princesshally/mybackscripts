#!/bin/bash
# PFLOCAL
# PFDISTRIB mysql sysadmin

# pvc-menu.sh Erik Schorr 2017
# Rev: 20200626: added -s <version> option to set new version id in CF file.

declare -a CFS

getlist() {
  find . -iname 'pvc-*.conf' | sort | cut -d- -f2 | cut -d. -f1 | sort | uniq -c | while read a b; do
    if [ "$a" -ge 3 ]; then
      echo $b
    fi
  done
}

usage() {
  echo "Usage:"
  echo "$0 [-y] [ projectname | pvc-conf ]"
  echo "options:"
  echo " -h : this help"
  echo " -y : assume yes on all prompts, run non-interactively"
  echo " -s <YYYYMMDD> : change/set VERSION number in pvc config before running deployment"
  echo ""
}

DBLIST=$(getlist)

while [ "$1" ]; do
  arg="$1"; shift
  if [ "${arg:0:1}" = "-" ]; then
    if [ "$arg" = "-y" ]; then
      NONINTERACTIVE=1
      continue
    fi
    if [ "$arg" = "-h" ]; then
      usage
      exit 0
    fi
    if [ "$arg" = "-s" ]; then
      if echo "$1" | grep -iq "20[0-9]\{6\}[a-z0-9]*"; then
        SETVERSION="$1"
        shift
        continue
      else
        echo "-s set version option requires version timestamp (e.g. 20201225)"
        exit 1
      fi
    fi
    echo "Unknown option: $arg"
    exit 1
  fi
  if [ -f "$arg" ]; then
    CF="$arg"
    echo "Using $CF"
    continue
  fi
  if [ -z "$PROJECT" ]; then
    echo "SET PROJECT TO $arg"
    PROJECT="$arg"
    continue
  fi
  echo "Unknown arg: $arg"
  exit 1
done

if [ "$CF" ]; then
  echo "Using deployment config file $CF ..."
else
  if [ "$PROJECT" ]; then
    CFLIST=$(find . -type f -iname "pvc-${PROJECT}-*.conf" -printf "%f\n" | sort)
    if [ -z "$CFLIST" ]; then
      echo "No pvc deployment config files found in this directory for $PROJECT"
      exit 1
    fi
    echo ""
    echo "Available pvc configs for $PROJECT:"
    I=0
    echo "Item Deployment-conf-file"
    for q in $CFLIST; do
      I=$((I+1))
      echo -e "$I    $q"
      CFS[$I]=$q
    done
    while [ -z "$SELECTION" ]; do
      read -p "Please select from one of the above (1-${I}): " SELECTION
      if [ "$SELECTION" -ge 1 ] && [ "$SELECTION" -le "$I" ]; then
        CF=${CFS[$SELECTION]}
        echo "Using config $CF"
      else
        SELECTION=""
      fi
    done
  else
    echo "$0: needs project name from the following list:";
    getlist | tr '\n' ' '
    echo ""
    exit 0
  fi
fi

if [ "$SETVERSION" ]; then
  echo "Setting new version ID in $CF to $SETVERSION"
  sed -i "$CF" -e "/^VERSION/s/20[0-9]\{6\}[a-z0-9]*/${SETVERSION}/"
fi
if echo "$CF" | egrep -q "dev.*new"; then
  CMDSEQ="pvc-1-create-vol.sh pvc-2-host-cfg.sh pvc-3-connect-vlun.sh pvc-4-mount-fs.sh"
fi
if echo "$CF" | egrep -q "dev.*qa"; then
  CMDSEQ="pvc-1-create-vol.sh pvc-2-host-cfg.sh pvc-3-connect-vlun.sh pvc-4-mount-fs.sh"
fi
if echo "$CF" | egrep -q "(qa|base).*prod"; then
  CMDSEQ="pvc-1-create-vol.sh pvc-2-host-cfg.sh pvc-3-connect-vlun.sh pvc-4-mount-fs.sh pvc-5-install-sprocs.sh"
fi
if echo "$CF" | egrep -q "qa.*base"; then
  CMDSEQ="pvc-make-basevol.sh"
  if grep -iq '^SRC' "$CF"; then
    if grep -q "^BASE" "$CF"; then
      echo "Found both SRC* and BASE* directives in $CF, but these options aren't compatible"
      echo "When creating a base volume without using SRC* directives SANVOLNAME_TPL specifies the source volume, and BASEVOL_TPL specifies the name of the volume to create.  pvc-make-basevol.sh uses this method."
      echo "When using SRC* directives, the SANVOLNAME_TPL directive specifies the target/new volume.  pvc-1-create-vol.sh uses this method for creating base volumes (for deployment to prod)"
      exit 2
    else
      echo "Found SRC* directives in $CF, so we can use pvc-1-create-vol.sh instead of pvc-make-basevol.sh"
      CMDSEQ="pvc-1-create-vol.sh"
    fi
  fi
fi
if [ -z "$CMDSEQ" ]; then
  echo "This config file isn't named in a way that describes its source/target environments"
  echo "TODO: would implement a way to find pvc command sequences inside the pvc*.conf file - ES"
  exit 1
fi

if [ "$NONINTERACTIVE" ]; then
  echo "Running this command sequence (with pre-flight tests), non-interactively.  All commands will proceed without confirmation, unless an error occurs."
  echo "CMDSEQ: $CMDSEQ"
else
  echo "Running this command sequence (with pre-flight tests):"
  echo "CMDSEQ: $CMDSEQ"
  echo ""
  echo "How would you like to run these steps?"
  echo "1) non-interactively, running all the steps without requiring user input, or"
  echo "2) interactively, where each step requires confirmation?"
  while :; do
    read -p "(1 or 2) " OPT
    if [ "$OPT" = "1" ]; then
      NONINTERACTIVE=1
      TMOUT=1
      break
    fi
    if [ "$OPT" = "2" ]; then
      unset NONINTERACTIVE
      unset TMOUT
      break
    fi
  done
  if grep -q "^VERSION " "$CF"; then
    CFVERS=$(grep "^VERSION " "$CF" | grep -o '20[0-9]\{6\}[a-z0-9]*')
    echo "Version found in $CF is $CFVERS"
  fi
fi
if [ "$NONINTERACTIVE" ]; then
  TMOUT=2
  echo ""
  echo "Prompts will automatically assume (Y) after $TMOUT second(s)"
  echo "Starting in 3 seconds..."
  sleep 3
fi

for CMD in $CMDSEQ; do
  echo "----------------------------------------"
  echo "Testing: $CMD -t $CF"
  echo "----------------------------------------"
  sleep 1
  OK=0
  while [ "$OK" = 0 ]; do
#    sh -c "echo ~~~ $CMD -t $CF"; RC=$?
    sh -c "$CMD -t $CF"; RC=$?
    if [ "$RC" = 0 ]; then
      sleep 1
      echo "Pre-flight testing $CMD succeeded."
      echo "Would you like to commit this operation and re-run the command without the testonly option?"
      [ "$TMOUT" ] && echo "Continuing automatically after $TMOUT seconds with no input."
      while :; do
#        read -t2 -p '(Y/n) ' XXX
        read -p '(Y/n) ' XXX
        echo ""
        if [ -z "$XXX" ] || [ "${XXX:0:1}" = "Y" ] || [ "${XXX:0:1}" = "y" ]; then
          OK=1
          break
        fi
        if [ "${XXX:0:1}" = "N" ] || [ "${XXX:0:1}" = "n" ]; then
          echo "Exiting."
          exit 0
        fi
      done
    else
      echo "$CMD test returned error code $RC.  Please rectify the issue."
      echo "Hit <ENTER> to repeat the test, or <CTRL-C> to exit"
      read XXX
    fi
  done
  sleep 1

  echo "----------------------------------------"
  echo "Commit: $CMD $CF"
  echo "----------------------------------------"
  sleep 1
  OK=0
  while [ "$OK" = 0 ]; do
    sh -c "$CMD $CF"; RC=$?
    if [ "$RC" = 0 ]; then
      echo "$CMD succeeded.  Hit <ENTER> to proceed or <CTRL-C> to interrupt."
      [ "$TMOUT" ] && echo "Continuing automatically after $TMOUT seconds with no input."
      read -p '(<enter> or <ctrl-c>) ' XXX
      echo ""
      OK=1
    else
      echo "command $CMD returned error code $RC.  Please rectify the issue."
      echo "Hit <ENTER> to repeat, or <CTRL-C> to exit"
      read XXX
    fi
  done
  sleep 1
done
