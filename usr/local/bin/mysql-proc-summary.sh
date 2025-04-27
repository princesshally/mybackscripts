#!/bin/bash
# PFLOCAL
# PFDISTRIB
if [ "$1" ]; then
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    progname=$(echo "$0" | rev | cut -d/ -f1 | rev)
    echo "$progname dumps a sorted list of mysql procedures and functions, helpful for comparing installed procs/functions between mysql/mariadb servers"
    echo "usage: $progname [dbname]"
    echo ""
    echo "note: displayed 'content' line is compressed and truncated only for comparison purposes, and should not be considered accurate"
    exit 0
  fi
  mysql -B mysql -e "select concat('DB:',db,' ',type,':',name,' [',security_type,':',definer,'] ') as identity, sql_mode, concat(length(body),': ',left(replace(replace(replace(replace(body,'\t',''),'\r',''),'\n',''),' ',''),1000)) as content from proc WHERE db='$1' order by db,name,type\G" | sed -e 's/^\*.*\*$//g' -e 's/\*\*\**/**/g' |cut -c1-120
else
  mysql -B mysql -e "select concat('DB:',db,' ',type,':',name,' [',security_type,':',definer,'] ') as identity, sql_mode, concat(length(body),': ',left(replace(replace(replace(replace(body,'\t',''),'\r',''),'\n',''),' ',''),1000)) as content from proc order by db,name,type\G" | sed -e 's/^\*.*\*$//g' -e 's/\*\*\**/**/g' | cut -c1-120
fi
