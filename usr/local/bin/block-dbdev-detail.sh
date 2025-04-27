#!/bin/bash
#PFLOCAL
#PFDISTRIB mysql
#REQUIRES dbdir

# block-dbdev-detail.sh
# show relations between databases, db datastores, mp maps, and underlying SAN volumes
# 20230911: Initial Release, Erik Schorr <erik@enformion.com>
# 20230920: added -s option to run command on remote server (with same installed, using ssh key auth)


SSHOPTS="-o PasswordAuthentication=no -o ConnectTimeout=5 -q -l root"
TF=$(mktemp dbdev-XXXXXX)
if [ -z "$TF" ]; then
	echo "Could not allocate tempfile"
	exit 3
fi

cleanexit() {
	rm -f "$TF"
	exit $1
}
signalexit() {
	echo "Caught signal" >&2
	rm -f "$TF"
	exit 1
}
trap "signalexit" 1 2 3 6 7 11 13 14 15 16 17 29 30

dbdir() {
  for MYSQLDBDIR in /db/mysql/data /data01/mysql/data /drbd/mysql/data /var/lib/mysql /var/lib/mariadb; do
    if [ -d "${MYSQLDBDIR}/$1" ]; then
      if cd "${MYSQLDBDIR}/$1"; then
        cd $(/bin/pwd)/..
        /bin/pwd
        return
      fi
    fi
  done
}

wwvn2san() {
  echo "$1" | sed \
  -e 's/^\(36782bcb0\)/PERC:/i' \
  -e 's/^\(360002ac0\)/HP3PAR:/g' \
  -e 's/^\(3624a9370\)/PUREFA:/g' \
  -e 's/^\(PUREFA:\)\?30f849b8.*$/smf3-pure1/i' \
  -e 's/^\(PUREFA:\)\?390dd232.*$/smf3-pure2/i' \
  -e 's/^\(PUREFA:\)\?53db1b20.*$/smf3-pure3/i' \
  -e 's/^\(PUREFA:\)\?4edc7a8d.*$/smf3-pure4/i' \
  -e 's/^\(PUREFA:\)\?7217baf0.*$/smf3-pure5/i' \
  -e 's/^\(PUREFA:\)\?4f1679cf.*$/smf3-pure6/i' \
  -e 's/^\(HP3PAR:\)\?.*00b070$/inserv4/i' \
  -e 's/^\(HP3PAR:\)\?.*00635f$/inserv5/i' \
  -e 's/:3600/:600/' \
  -e 's/:3500/:500/' \
  -e 's/:$//'
}

selftest() {
	echo "dbdir:"
	for db in debt mardiv criminal criminal_v2 fis mysql information_schema poseidon; do
		echo "$db -> $(dbdir $db)"
	done
	echo ""
	echo "wwvn2san:"
	for wwvn in 360002ac000000000000005cf0000635f 360002ac000000000000000c10000b070 3624a937053db1b20241287bc00092130 3624a937053db1b20241287bc000ae8dd 3624a93707217baf05efe883d0003cc1a 53db1b20241287bc00091da8 3624a937053dX1b20241287bc000ae8dd; do
		echo "$wwvn -> $(wwvn2san $wwvn)"
	done
	cleanexit
}

while [ "$1" ]; do
	arg="$1"; shift
	if [ "$arg" = "-csv" ] || [ "$arg" = "-c" ]; then
		csv=1
	fi
	if [ "$arg" = "-T" ]; then
		selftest
		cleanexit
	fi
	if [ "$arg" = "-s" ]; then
		if [ "$1" ]; then
			RHOST="$1"; shift
		else
			echo "$0: -s requires a hostname, to execute this on a remote server" >&2
			cleanexit 2
		fi
	fi
done

if [ "$RHOST" ]; then
			if isup.sh "$RHOST" >/dev/null 2>%1; then
				CMD=$(echo "$0" | sed -e 's_^.*/__')
				if [ "$csv" ]; then
					CMD="$CMD -csv"
				fi
				echo "Running $CMD on $RHOST" >&2
				if bash -c ":|ssh $SSHOPTS $RHOST '$CMD'"; then
					cleanexit 0
				else
					echo "ssh or remote command failed" >&2
					cleanexit 1
				fi
			else
				echo "$RHOST isn't a valid hostname or the system isn't online" >&2
				cleanexit 2
			fi
fi
if [ "$dblist" ]; then
	for i in $dblist; do
		d=$(dbdir $i 2>/dev/null)
		if [ -e "$d" ]; then
			echo $i $d
		fi
	done | sort -k 2 > $TF
else
	if [ -d "/var/log/mysql/last-access" ]; then
		find /var/log/mysql/last-access/ -mtime -7 | cut -d/ -f 6 | sort | while read x; do
		  d=$(dbdir $x 2>/dev/null)
		  if [ -e "$d" ]; then
			  echo $x $d
		  fi
		done | sort -k 2 > $TF
	fi
fi

cat $TF | while read db dir; do
  realdir=$(cd $dir && /bin/pwd)
  if [ -z "$realdir" ]; then
	  echo "$db has missing directory"
	  continue
  fi
  mount=$(stat --printf "%m\n" "$dir")
  dev=$(grep " $mount " /proc/mounts | cut -d' ' -f1)
  map=${dev/\/dev\/mapper\//}
  wwn="_UNK_"
  if [ -e /dev/mapper/$map ]; then
	  dmdev=$(stat --printf "%N\n" $dev | grep -o 'dm-[0-9]*')
	  wwvn=$(cat /sys/block/${dmdev}/dm/uuid | sed -e  "s/mpath-3624a9370//g")
	  san=$(wwvn2san $wwvn)
  else
	  dmdev='_NA_'
	  wwvn='_NA_'
	  san='_NA_'
  fi
  if [ "$csv" ]; then
	  if [ "$csv" = 1 ]; then
		  echo "mountpoint,mountdev,dmdev,map,san,wwvn,db"
		  csv=2
	  fi
  	echo "$mount,$dev,$dmdev,$map,$san,$wwvn,$db" | sed -e 's/^/"/g' -e 's/$/"/g' -e 's/,/","/g'
  else
  	echo "mountpoint=$mount mountdev=$dev dmdev=$dmdev map=$map san=${san} wwvn=$wwvn db=$db"
  fi
done | less

cleanexit 0

