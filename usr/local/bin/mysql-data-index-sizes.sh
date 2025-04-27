#!/bin/bash
# PFLOCAL
# PFDISTRIB mysql

# mysql-data-index-sizes.sh
# Author: Erik Schorr <erik@peoplefinders.com>
# Version: 1.2
# Rev: 20190213 added rowcount and data-per-row and index-per-row sizes

# No user-serviceable parts

if [ "$1" ] && cd /db/mysql/data/$1/ 2>/dev/null; then
  echo "Table data and index statistics for $1"
  DATABASE="$1"
else
  echo "Must specify database name"
  exit 1
fi

numfmt() {
  a=$1
  if [ -z "$a" ]; then
    echo 0
    return
  fi
  s=1
  if [ "$a" -ge 1000000000000 ]; then
    if [ "$a" -ge 10000000000000 ]; then s=0; fi
    echo $(echo "scale=$s;$a/(10^12)" | bc)T
    return
  fi
  if [ "$a" -ge 1000000000 ]; then
    if [ "$a" -ge 10000000000 ]; then s=0; fi
    echo $(echo "scale=$s;$a/(10^9)" | bc)G
    return
  fi
  if [ "$a" -ge 1000000 ]; then
    if [ "$a" -ge 10000000 ]; then s=0; fi
    echo $(echo "scale=$s;$a/(10^6)" | bc)M
    return
  fi
  if [ "$a" -ge 1000 ]; then
    if [ "$a" -ge 10000 ]; then s=0; fi
    echo $(echo "scale=$s;$a/(10^3)" | bc)K
    return
  fi
  echo $((a+0))
  return
}

tables=$(ls -1 | grep '\.frm' | sort | cut -d. -f1 | tr '\n' ' ')
if [ "$tables" ]; then
  echo -e 'Rows\tData\tIndex\tDb/row\tIXb/row\tTable'
  echo -e '-------\t-------\t-------\t-------\t-------\t---------------'
  for T in $tables; do
    C=$(echo "select count(1) from $T" |mysql -sB $DATABASE)
    D=$(du -shc ${T}[.#]*M?D 2>/dev/null | tail -n -1 | cut -f1)
    if [ "$C" != 0 ] && [ "$D" != 0 ]; then
      DB=$(du -bc ${T}[#.]*M?D | tail -n -1 | cut -f1)
      DBPR=$((DB/C))
    else
      DBPR=0
    fi
    I=$(du -shc ${T}[.#]*M?I 2>/dev/null | tail -n -1 | cut -f1)
    if [ "$C" != 0 ] && [ "$I" != 0 ]; then
      IB=$(du -bc ${T}[#.]*M?I | tail -n -1 | cut -f1)
      IBPR=$((IB/C))
    else
      IBPR=0
    fi
    CH=$(numfmt $C)
    echo -e "$CH\t$D\t$I\t$DBPR\t$IBPR\t$T"
  done
fi
