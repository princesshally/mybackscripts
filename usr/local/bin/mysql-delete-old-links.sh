#!/bin/bash
# PFLOCAL
# PFDISTRIB mysql
# This script finds old links to non-existent places in /db/mysql/data, and removes them

find /db/mysql/data/ -maxdepth 1 -mindepth 1 -mtime +30 -type l | while read x; do
  ls -d $x/ >/dev/null 2>/dev/null || rm $x
done


