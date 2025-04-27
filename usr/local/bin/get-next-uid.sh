#!/bin/bash
# PFLOCAL
# PFDISTRIB linux

SERVERS="$@"
SSHOPTS="-q -o ConnectTimeout=5"
MINUID=500  # minimum uid to consider valid for new user


PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin; export PATH
if [ -z "$SERVERS" ]; then
  SERVERS="jump smf3-posmysql01 smf3-posmysql02 qa-posmysql01 devgalmysql01 qa-galmongo01 smf3-galmongo11 smf3-galmongo15 prodmongo01 prodmongo04 qa-galmysql01 devmysql04 devmysql05 sandmysql01 localhost smfgate01.hadoop.cco smf3gate02 blaze.cco smf3-galmysql01 smf3-galmysql02 smf3mongo-pf4log01 smf3mongo-phcache01 smf3mongo-pf4cf01"
fi

MAXUID=$MINUID
  for H in $SERVERS; do 
    if isup.sh $H >/dev/null; then
      echo "Connecting to $H ..." >&2
      #X=$(ssh $SSHOPTS $H "cut -d: -f 3 /etc/passwd | grep -v '[6][0-9][0-9][0-9][0-9]' | sort -rn | head -1")
      X=$(ssh $SSHOPTS $H "cut -d: -f 3 /etc/passwd | egrep '^([1-9][0-9][0-9]|[1-9][0-9][0-9][0-9])$' | sort -rn | head -1")
      echo "Highest UID on $H: $X" >&2
      if [ $X -gt $MAXUID ]; then
        MAXHOST=$H
        MAXUID=$X
        echo "New MAXUID $MAXUID ($MAXHOST)" >&2
      fi
    else
      echo "!!! $H is not up or doesn't exist" >&2
    fi
  done
  NEXTUID=$((MAXUID+1))
  echo "Verifying new UID isn't used anywhere ..."
  for H in $SERVERS; do
    if isup.sh $H >/dev/null; then
      Y=$(ssh $SSHOPTS $H "cut -d: -f 3 /etc/passwd | grep '^${NEXTUID}$'")
      if [ "$Y" ]; then
        echo "Oops, uid $NEXTUID found active on $H" >&2
        exit 1
      fi
    fi
  done
  echo "NEXT $NEXTUID"
exit 0
