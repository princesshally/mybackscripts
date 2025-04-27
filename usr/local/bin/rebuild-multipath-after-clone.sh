#!/bin/bash
# PFLOCAL
# PFDISTRIB

INFILE=/etc/multipath.conf.template
OUTFILE=/etc/multipath.conf
TMPFILE=$(mktemp)
echo "Temp file: $TMPFILE" >&2
rootdev=$(df / | grep -v ^File | head -1 | awk '{print $1}')
rootwwn=""
if [ "$rootdev" ]; then
  for wwn in $(ls /dev/disk/by-id/dm-uuid*mpath-* | egrep -o "[a-f0-9]{12,}" | sort |uniq ); do
    if echo "$rootdev" | grep -q "/${wwn}"; then
      rootwwn=$wwn
    fi
  done
  if [ -z "$rootwwn" ]; then
    rootwwn=$(/usr/lib/udev/scsi_id -g $rootdev)
  fi
  if [ "$rootwwn" ]; then
    echo "found root device $rootdev with WWN $rootwwn"
  else
    echo "Could not find WWN for $rootdev"
    exit 1
  fi
else
  echo "Could not find root dev from df output"
  exit 1
fi
sleep 1

while read LINE; do
  if echo "$LINE" | grep -q "#MULTIPATHS"; then
    /usr/local/bin/list-san-wwns.sh | while read WWN; do
      echo "multipath {"
      echo "  wwid $WWN"
      echo "  path_selector \"round-robin 0\""
      echo "}"
    done
  else
    echo "$LINE"
  fi
done < $INFILE > $TMPFILE
if grep -v '^#' $TMPFILE | grep -q "wwid [0-9]"; then
  mv $OUTFILE ${OUTFILE}.bak
  mv $TMPFILE $OUTFILE
  /usr/local/bin/list-san-wwns.sh | sed -e 's/^/\//g' -e 's/$/\//g' > /etc/multipath/wwids
  sed -e 's/^mpath/#mpath/g' -e 's/^OS/#OS/g' -i /etc/multipath/bindings
  echo "OS $rootwwn" >> /etc/multipath/bindings
  echo "Running dracut to update initramfs with new multipath configs"
  dracut -v --force --add multipath --include /etc/multipath.conf /etc/multipath.conf --include /etc/multipath/wwids /etc/multipath/wwids --include /etc/multipath/bindings /etc/multipath/bindings

 else
  echo "There was a problem processing the multipath.conf.template file or inserting WWNs"
  echo "Please see the outputfile at $TMPFILE and the output from the list-san-wwns.sh command"
fi


