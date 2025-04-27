#!/bin/bash
if [ -f /db/mysql/data/ibdata1 ] && pidof mysqld >/dev/null; then
  TF=$(mktemp /tmp/UNCOMFORTABLYSMOOTHPANGOLIN-XXXXXX)
else
  echo "This script must be run on a mysql server with primary data directory /db/mysql/data"
  exit 1 
fi

cleanexit() {
  rm $TF
  exit $*
}

#TF=$(tty)
find /db/mysql/data /db/mysql/data/*/ /db/*/ -xdev -type d -name data | sort |uniq | while read x; do
  echo "DATADIR $x" >> $TF
  echo "DATAPAT $(echo $x | sed -e 's/20[0-9][0-9][01][0-9][0-3][0-9]/20[0-9][0-9][01][0-9][0-3][0-9]/g')" >> $TF
done

cat $TF | grep '^DATADIR' | while read tmp x; do 
  cd $x
  if find . -type d ! -user mysql | grep -q .; then
    chown mysql:mysql "$x"
    echo "Fixed directory perms: $x"
  fi
  if find . -type f ! -user mysql | grep -q . ; then
    find $x/ -type f ! -user mysql -printf "Fixed file perms: %p\n" -exec chown mysql:mysql {} \;
  fi
done

# Find all data directories that appear to have multiple dated copies
cat $TF | grep ^DATAPAT | cut -d' ' -f 2  | sort | uniq -c | sed -e 's/^ *//g' | grep -v '^1 ' | sed -e 's/^[0-9]* /DUPEPAT /g' >> $TF

# Find all data directories that are targets of symlinks in mysql datadir
find /db/mysql/data/* -maxdepth 0 -type l -ls | sed -e 's/^.*-> /LINKED /g' >> $TF

# Find all data directories actually in use by mysqld
lsof -nP -p $(pidof mysqld) | egrep '(DIR|REG).*/data' | sed -e 's/^.* \//\//g' -e '/\.[a-zA-Z0-9]*$/s/\/[^/]*$//g' | sort |uniq | while read x; do [ -d "$x" ] && echo INUSE $x ; done >> $TF

# Find all mount points that aren't used
grep "^DATADIR " $TF | cut -d' ' -f 2 | cut -d/ -f 1-3 | sort |uniq | while read x; do
  if [ ! -L "$x" ]; then
    egrep "(INUSE|LINKED) ${x}/" $TF | grep -q . || echo "OK TO UNMOUNT $x"
  fi
done

if grep -q '^DUPEPAT' $TF; then
  echo "### Redundant data directories found:"
  grep ^DUPEPAT $TF |while read x y; do 
    egrep "^DATADIR $y" $TF | while read tmp z; do
      egrep "^(INUSE|LINKED) ${z}$" $TF | grep -q . || echo "UNUSED $z"
    done
  done
fi


#echo $TF
cleanexit
