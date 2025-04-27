#!/bin/bash
# PFLOCAL
# PFDISTRIB mysql

TS=$(date +"%Y%m%d.%H%M%S")
count=$(mysql -e 'show processlist'  | grep -i 'Query.*[0-9]\{3,\}.*INSERT INTO tmp'| cut -f1  | while read x; do echo $x; mysql -e "kill $x"; done | wc -l )
if [ "$count" -gt 0 ]; then
	echo "$TS $count queries killed"
fi
