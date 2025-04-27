#!/bin/bash
# PFLOCAL

if find /db/mysql/data/ /db/audit/ -maxdepth 1 -type f -name 'server_audit.log*' -mtime -1 2>/dev/null | grep -q .; then
  mkdir -p /var/log/mysql/last-access 2>/dev/null
  /usr/local/bin/mysql-active-databases2.pl >> /var/log/mysql/last-access/ERRORS 2>&1
else
  echo "$(date) $0: Stale or missing server_audit log files" >>/var/log/mysql/last-access/ERRORS 2>&1
fi
