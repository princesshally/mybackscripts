#!/bin/bash
# PFLOCAL

PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/lib/udev:/lib/udev:/usr/local/bin; export PATH
for q in /dev/sd*[a-z]; do
  scsi_id -g $q
done | sort | uniq
