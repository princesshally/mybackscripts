#!/bin/bash
find -L /sys/block/sd* -maxdepth 3 -path '*/scsi_disk/*' -iname '[0-9]*:[0-9]*:[0-9]' 2>/dev/null | grep -o '[0-9]\+:[0-9]\+:[0-9]\+:[0-9]\+' | while read STGT; do
  if [ -f "/sys/class/scsi_disk/${STGT}/device/rescan" ]; then
    echo 1 > /sys/class/scsi_disk/${STGT}/device/rescan
    echo "$STGT" | cut -d: -f1
    echo "Refreshed $STGT" >&2
  fi
done | sort | uniq | while read HOST; do
  echo '- - -' > /sys/class/scsi_host/host${HOST}/scan
  echo "Triggered device scan on host${HOST}" >&2
done
