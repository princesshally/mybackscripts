#!/bin/bash
PATH=/sbin:/usr/sbin:$PATH

setfacl -d -m g::rx,o::rx /db/mysql/data

find /db/mysql/data -mindepth 1 -maxdepth 1 -type d | while read x; do
  chown -R mysql:mysql "$x"
  chmod g+rx "$x"
  setfacl -d -m g::rx,o::rx "$x"
done

find /db/mysql/data -mindepth 1 -maxdepth 1 -type l | while read x; do
  cd "$x" 2>/dev/null && chown -R mysql:mysql "$x" && chmod g+rx "$x"
done

exit 0

