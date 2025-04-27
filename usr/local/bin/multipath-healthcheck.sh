#!/bin/bash
# PFLOCAL
# PFDISTRIB mylsq all

# multipath-healthcheck.sh
# Erik Schorr <erik@peoplefinders.com>
# Verifies that all multipath slave devs are healthy
# history:
# 2022xxxx initial release
# 20241020 fixed enumerating of multipath master devs, ignoring partitions

#DEBUG=1
PROGNAME="multipath-healthcheck.sh"
PATH=/sbin:/usr/sbin:/usr/local/sbin:/lib/udev:/usr/lib/udev:$PATH; export PATH
MPEXEC=$(which multipath 2>/dev/null)
if [ -z "$MPEXEC" ]; then
  echo "$PROGNAME ERROR: multipath executable not found on $HOSTNAME"
  exit 3
fi
TF=$(mktemp --tmpdir koala-XXXXXX)
nmpaths=$(cd /dev/mapper && ls -nf1 $1 | grep -i "^[a-z0-9]" | egrep -v 'p[0-9]|-part[0-9][0-9]*' | sort | uniq | wc -l)
echo "$PROGNAME: scanning $nmpaths multipath devs ..." >&2
WARNCOUNT=0
ERRCOUNT=0
EXCODE=0
usage() {
  echo "Usage:"
  echo "$0 [mpname]"

}

while [ "$1" ]; do
  arg="$1"
  shift
  if [ "$arg" = "-h" ]; then
    usage
    exit 0
  fi
  if [ "$arg" = "-D" ]; then
    DEBUG=1
    continue
  fi
  if [ "${arg:0:1}" = "-" ]; then
    echo "Bad arg: $arg"
    exit 1
  fi
  if [ -z "$MAP" ]; then
    MAP="$arg"
    continue
  fi
done
if [ "$MAP" ]; then
  MPMAPS="$MAP"
else
  MPMAPS=$(find /sys/devices/virtual/block/dm* -path '*slaves*' -name 'sd*' | grep -o 'dm-[0-9]*' | sort | uniq | while read x; do cat /sys/devices/virtual/block/${x}/dm/name; done | sort)
fi
MAPCOUNT=0
for x in $MPMAPS; do
  MAPCOUNT=$((MAPCOUNT+1))
  MAPERR=''
  MAPWARN=''
  [ "$DEBUG" ] && echo "Checking map ${MAPCOUNT}: $x"
  PRINT=""
  multipath -l $x > $TF
  mp_wwn=$(grep "^${x}\b" $TF | egrep -o '[a-f0-9]{17,}')
  act_wwn=$(scsi_id -g /dev/mapper/$x)
  mpathsize=$(blockdev --getsize64 /dev/mapper/$x)
  totalpaths=$(grep -o '\bsd[a-z][a-z]*\b' $TF | wc -l)
  activepaths=$(grep '\bsd[a-z].*\bactive\b' $TF | wc -l)
  failedpaths=$(grep '\bsd[a-z].*\bfailed\b' $TF | wc -l)
  sdlist=$(egrep -o '\bsd[a-z][a-z0-9]*\b' $TF | tr '\n' ' ' | sed -e 's/ $//g')
  targetlist=$(egrep -o '\b([0-9]*:){3}[0-9]*\b' $TF | tr '\n' ' ' | sed -e 's/ $//g' )
  lunlist=$(egrep -o '\b([0-9]*:){3}[0-9]*\b' $TF | cut -d: -f 4 | tr '\n' ' ' | sed -e 's/ $//g')
  nluns=$(egrep -o '\b([0-9]*:){3}[0-9]*\b' $TF | cut -d: -f 4 | sort | uniq | wc -l )
  if [ $failedpaths -gt 1 ] && [ $failedpaths -lt $totalpaths ]; then
    echo "WARNING: map ${x}: some paths are marked as failed ($failedpaths of $totalpaths)"
    MAPWARN=1
  fi
  if [ $activepaths == 0 ] || [ $failedpaths == $totalpaths ]; then
    echo ""
    echo "ERROR: map $x has no active paths or all paths are in failed state!"
    MAPERR=1
    mountpoints=$(grep "mapper.${x}\b" /proc/mounts  | cut -d' ' -f 2 | tr -s '\n' ' ' | sed -e 's/ $//g')
    if [ "$mountpoints" ]; then
      echo "\`-- mountpoint(s): $mountpoints"
      for mount in $mountpoints; do
        f=$(fuser -vm ${mount}/ 2>&1 | egrep -v 'COMMAND|kernel|:')
        if [ -z "$f" ]; then f="No processes found - safe to umount $mount"; fi
        echo "   \`-- $f"
      done
    else
      echo "\`-- Not mounted - safe to detach-multipath.sh $x"
    fi
    
    PRINT=1
    EXCODE=3
  else
    if [ "$mp_wwn" != "$act_wwn" ]; then
      echo "CRITICAL: map $x has new devs with incorrect volume wwn!"
      echo "Were the underlying LUNs detached before old mpath map was unmounted/destroyed?"
      echo "OS expects wwvn:   $mp_wwn"
      echo "SAN presents wwvn: $act_wwn"
      echo "To recover: detach map $x on host $HOSTNAME and rescan scsi devs, or re-attach old volume to same LUNs."
      PRINT=1
      EXCODE=3
      MAPERR=1
    else
      for s in $sdlist; do
        sdsize=$(blockdev --getsize64 /dev/$s)
        if [ "$sdsize" != "$mpathsize" ]; then
          echo "ERROR: map $x has scsidev of wrong size: $s ($sdsize) != $mpathsize"
          MAPERR=1
        fi
      done
    fi
  fi
  [ "$DEBUG$PRINT" ] && echo "$x active:$activepaths failed:$failedpaths uniqueluns:$nluns" && echo "   targets:($targetlist)" && echo "   luns:($lunlist)" && echo ""
#  if grep -q failed $TF; then echo "$
  if [ "$MAPERR" ]; then
    ERRCOUNT=$((ERRCOUNT+1))
  fi
  if [ "$MAPWARN" ]; then
    WARNCOUNT=$((WARNCOUNT+1))
  fi
done
rm -f "$TF"
if [ "$ERRCOUNT" != 0 ]; then
  echo "Maps with errors: $ERRCOUNT"
fi
if [ "$WARNCOUNT" != 0 ]; then
  echo "Maps with warnings: $WARNCOUNT"
fi
if [ "${WARNCOUNT}${ERRCOUNT}" = "00" ]; then
  echo "No problems found."
fi
exit $EXCODE

