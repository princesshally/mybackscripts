#!/bin/bash
# PFLOCAL
# PFDISTRIB

MYSQLOPTS=""
while [ "$1" ]; do
  arg="$1"
  if echo "$1"| grep -q "^-" ; then
    if [ "$MYSQLOPTS" ]; then
      MYSQLOPTS="$MYSQLOPTS $1"
    else
      MYSQLOPTS="$1"
    fi
    shift
    continue
  fi
  DB="$1"
  shift
done


if [ "$DB" ]; then
#  mysql $MYSQLOPTS performance_schema -e "select substring_index(substr(FILE_NAME,instr(FILE_NAME,'/data/')+6),'/',1) as DB, SUM(COUNT_READ) as r_count, sum(SUM_NUMBER_OF_BYTES_READ) as r_bytes, SUM(COUNT_WRITE) as w_count, sum(SUM_NUMBER_OF_BYTES_WRITE) as w_bytes from file_summary_by_instance WHERE FILE_NAME not like '%.frm' AND FILE_NAME NOT LIKE '%data/mysql%' and FILE_NAME LIKE '%/data/${1}/%.%' group by DB order by DB asc;"
  mysql $MYSQLOPTS performance_schema -e "select DB as \`database\`,r_count,r_bytes,w_count,w_bytes,dbfiles from (select FILE_NAME, @f:=REPLACE(REPLACE(REPLACE(REPLACE(FILE_NAME,'/db/','/'),'/data/','/'),'/mysql/','/'),'/data01/','/') as f1, REPLACE(SUBSTRING_INDEX(@f,'/',2),'/','') as DB, COUNT(1) as dbfiles, SUM(COUNT_READ) as r_count, sum(SUM_NUMBER_OF_BYTES_READ) as r_bytes, SUM(COUNT_WRITE) as w_count, sum(SUM_NUMBER_OF_BYTES_WRITE) as w_bytes from performance_schema.file_summary_by_instance WHERE right(FILE_NAME,3) IN ('myi','myd','ibd','mai','mad') AND FILE_NAME not like '%/data/mysql/%' AND FILE_NAME like '%/$DB/%' group by DB order by DB) as t2;"
else
#  mysql $MYSQLOPTS performance_schema -e "select substring_index(substr(FILE_NAME,instr(FILE_NAME,'/data/')+6),'/',1) as DB, SUM(COUNT_READ) as r_count, sum(SUM_NUMBER_OF_BYTES_READ) as r_bytes, SUM(COUNT_WRITE) as w_count, sum(SUM_NUMBER_OF_BYTES_WRITE) as w_bytes from file_summary_by_instance WHERE FILE_NAME not like '%.frm' AND FILE_NAME NOT LIKE '%data/mysql%' and FILE_NAME LIKE '%/data/%/%.%'  group by DB order by DB asc;"
  mysql $MYSQLOPTS performance_schema -e "select DB as \`database\`,r_count,r_bytes,w_count,w_bytes,dbfiles from (select FILE_NAME, @f:=REPLACE(REPLACE(REPLACE(REPLACE(FILE_NAME,'/db/','/'),'/data/','/'),'/mysql/','/'),'/data01/','/') as f1, REPLACE(SUBSTRING_INDEX(@f,'/',2),'/','') as DB, COUNT(1) as dbfiles, SUM(COUNT_READ) as r_count, sum(SUM_NUMBER_OF_BYTES_READ) as r_bytes, SUM(COUNT_WRITE) as w_count, sum(SUM_NUMBER_OF_BYTES_WRITE) as w_bytes from performance_schema.file_summary_by_instance WHERE right(FILE_NAME,3) IN ('myi','myd','ibd','mai','mad') AND FILE_NAME not like '%/data/mysql/%'  group by DB order by DB) as t2;"
fi

