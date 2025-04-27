#!/bin/bash
# PFLOCAL
# PFDISTRIB all

# detach-multipath.sh by Erik Schorr <erik@peoplefinders.com>
# Initial release: unknown
# Revisions:
# 20201116 Fixed parsing of fuser output, fixing false detection of open files/sessions on mounted volume

MTMP=$(mktemp /tmp/mtmp-XXXXXX)

cleanexit() {
  rm -rf $MTMP
  exit $1
}

while [ "$1" ]; do
  ARG=$1
  shift
  if [ -e "/dev/mapper/$ARG" ]; then
    MAP=$ARG
    echo "Found map $MAP"
    continue
  fi
done

if [ -z "$MAP" ]; then
  echo "Map not found or not supplied"
  cleanexit 1
fi

cat /proc/mounts |grep "/dev/mapper/$MAP\b" > $MTMP
#/dev/mapper/P4SSD_galperson_20161114 /db/galaxy_person_20161114 ext4 rw,relatime,stripe=1024,data=ordered 0 0

MOUNTED=0
MOUNTPOINTS=""
while read DEV MOUNTPOINT TMP; do
  MOUNTED=$((MOUNTED+1))
  OPENFILES=$(fuser -vm "$MOUNTPOINT" 2>&1 | egrep -v "USER|kernel mount|${MOUNTPOINT}\b:" | wc -l)
  if [ "$OPENFILES" = "0" ]; then
    echo "Safe to umount $MOUNTPOINT"
  else
    echo "Mountpoint $MOUNTPOINT has $OPENFILES open or active files.  Cannot continue."
    cleanexit 1
  fi
  if [ "$MOUNTPOINTS" ]; then
    MOUNTPOINTS="$MOUNTPOINTS $MOUNTPOINT"
  else
    MOUNTPOINTS="$MOUNTPOINT"
  fi
done < $MTMP

echo "Mountpoints to unmount: $MOUNTPOINTS"

sleep 2

UMOUNTED=0
while read DEV MOUNTPOINT TMP; do
  if umount "$MOUNTPOINT"; then
    UMOUNTED=$((UMOUNTED+1))
  else
    echo "Could not umount $MOUNTPOINT - Exiting."
    cleanexit 1
  fi
done < $MTMP

echo M:$MOUNTED U:$UMOUNTED

if [ "$MOUNTED" = "$UMOUNTED" ]; then
  echo "All mountpoints unmounted"
else
  echo "Number of successful umounts does not match number of mounts for this map.  Exiting."
  cleanexit 1
fi

DEVICES=$(multipath -l $MAP | grep -o '\bsd[a-z][a-z]*\b' | tr -s "\n" ' ')
echo "Will detach devices after removing map: $DEVICES"
echo "Map description: $(multipath -ll $MAP | head -1)"
sleep 1

echo "Removing map $MAP ..."
sleep 1
echo "remove map $MAP" | multipathd -k
RET=$?
echo "Multipathd -k returned $RET"

echo ""
echo "Removing block devices belonging to map"
sleep 1
for BLOCKDEV in $DEVICES; do
  echo "1" > "/sys/block/$BLOCKDEV/device/delete"
done

echo "Removed map and associated block devices"
cleanexit 0
