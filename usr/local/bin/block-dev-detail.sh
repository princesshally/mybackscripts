#!/bin/bash

# PFLOCAL
# PFDISTRIB
# block-dev-detail.sh - shows devname/size/wwn/mapname of all attached block devices
# Author: Erik Schorr <erik@peoplefinders.com>
# Version: 1.1
# 20190221 ES - bugfix to properly detect virtual floppy and report sizes even if not running as superuser
# 20190620 ES - add LUN to SAN:WWW column

#D=1

sandetect() {
  (if [ "$1" ]; then
    echo $1
  else
    cat
  fi) | sed \
  -e 's/^\(3624a937030f849b8\)/pure1:\1/i' \
  -e 's/^\(3624a9370390dd232\)/pure2:\1/i' \
  -e 's/^\(3624a937053db1b20\)/pure3:\1/i' \
  -e 's/^\(3624a93704edc7a8d\)/pure4:\1/i' \
  -e 's/^\(3624a93707217baf0\)/pure5:\1/i' \
  -e 's/^\(3624a9370\)/PureFA:\1/i' \
  -e 's/:3624a9370/:/' \
  -e 's/^\(350002ac.*082b\)/inserv2:\1/i' \
  -e 's/^\(350002ac.*3804\)/inserv3:\1/i' \
  -e 's/^\(360002ac.*b070\)/inserv4:\1/i' \
  -e 's/^\(360002ac.*635f\)/inserv5:\1/i' \
  -e 's/^\(360002ac\)/HP3PAR:\1/i' \
  -e 's/^\(36782bcb0\)/PERC_RAID:/i' \
  -e 's/:3600/:600/' \
  -e 's/:3500/:500/'
}

PATH=/sbin:/usr/sbin:/usr/local/sbin:/usr/local/bin:/usr/lib/udev:/lib/udev:$PATH; export PATH
#DEVLIST=/dev/sd*[a-z]
DEVLIST=$(find /dev/ -maxdepth 1 -type b -name 'sd[a-z]' | sort; find /dev/ -maxdepth 1 -type b -name 'sd[a-z][a-z]' | sort)

while [ "$1" ]; do
  arg="$1"; shift
  if [ "$arg" = "-h" ]; then
    echo "Usage:"
    echo "$0 [-h] [sdX]"
    echo "Shows table with the following info:"
    echo "devnode	sizeGB	SAN:WWVN:LUN	Mfr,Model,Rev	/dev/mapper/mapname"
    exit 0
  # sdjm    2300    PureFA:30f849b87e8d6ac60002562a:1 PURE,FlashArray,8888    /dev/mapper/census-20180321
  fi
  if [ "$arg" = "-p" ]; then
    paths=1
    continue
  fi
done
SCSIIDPATH=$(PATH=/usr/lib/udev:/lib/udev:$PATH which scsi_id 2>/dev/null)
if [ -z "$SCSIIDPATH" ]; then
  echo "$0: the scsi_id command is not installed on this system.  Cannot continue."
  exit 1
fi
if [ "$1" ]; then
  DEVLIST=$*
fi
for DEV in $DEVLIST; do
  DEVNAME=$(echo $DEV |rev | cut -d/ -f1 | rev)
  SYSPATH=/sys/block/${DEVNAME}/device
  # Get LUN from device symlink - is there a better/reliable way to do this without relying on /sys?
  LUN=$(ls -ld "$SYSPATH"  |grep -o ':[0-9][0-9]*$')
  SIZEBYTES=$(blockdev --getsize64 /dev/${DEVNAME} 2>/dev/null)
  [ "$D" ] && echo "SIZEBYTES:$SIZEBYTES"
  if [ -z "$SIZEBYTES" ]; then
    if [ -e "/sys/block/${DEVNAME}/size" ]; then
      SIZEBYTES=$(cat /sys/block/${DEVNAME}/size)
      SIZEBYTES=$(echo ${SIZEBYTES}*512 | bc)
    fi
    if [ -z "$SIZEBYTES" ]; then
      SIZEBYTES=0
    fi
  fi
  SIZEGB=$(echo "scale=3;a=${SIZEBYTES}/1048576/1024;a-(a%1)" | bc | sed -e 's/\.000$//')
  WWN=$(PATH=/usr/lib/udev:/lib/udev:$PATH scsi_id -g "/dev/$DEVNAME")
  [ "$D" ] && echo "WWN:$WWN"
  if [ "$WWN" ]; then
    WWN=$(sandetect "$WWN")${LUN}
  else
    WWN="NA"
  fi
  VMR="$(grep -oi '[0-9a-z].*[0-9a-z]' $SYSPATH/vendor),$(grep -oi '[0-9a-z].*[0-9a-z]' $SYSPATH/model),$(grep -oi '[0-9a-z].*[0-9a-z]' $SYSPATH/rev)"
  VMR=$(echo "$VMR" | sed -e 's/^,/NA,/')
  [ "$D" ] && echo "VMR:$VMR"
  DH=$(cat $SYSPATH/dh_state 2>/dev/null)
  HOLDER=$(ls -1 /sys/block/${DEVNAME}/holders)
  [ "$D" ] && echo "HOLDER:$HOLDER"
  if [ "$HOLDER" ]; then
    MAP=$(find /dev/mapper -ls |grep "\b${HOLDER}\b" | rev |cut -d' ' -f3 | rev | tr -s '\n' ','| sed -e 's/,$//')
  else
    MAP=""
  fi
  echo -e "${DEVNAME}\t${SIZEGB}\t${WWN}\t${VMR}\t${MAP}"
done | \
if [ "$paths" ]; then
	cut -f 2,3,5 | sort -k 2 | uniq -c
else
	cat
fi
exit 0
