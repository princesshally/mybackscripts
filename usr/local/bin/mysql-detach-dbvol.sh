#!/bin/bash
# PFLOCAL
# PFDISTRIB mysql
# mysql-detach-dbvol.sh
# Version 0.9 (first usable release) 20200529 Erik Schorr

# This version is not considered "stable".  Please do not modify anything in
# this script without discussing it with the author, Erik Schorr
# <erik@peoplefinders.com>

###################################
# No user-servicable parts inside #
###################################

usage() {
	echo "Usage:"
	echo "$0 [-h] : show this help"
	echo "$0 [-t] : test only, don't actually do anything"
	echo "$0 [-D] <databasename> : [optionally drop and] flush DB, unmount volume, detach associated SAN devices"
	echo ""
	echo "Use the -D option with caution.  It drops the database and trims the volume, leaving it unrecoverable."
	echo ""
	exit 0
}
while [ "$1" ]; do
	arg="$1"; shift
	if [ "$arg" = "-h" ]; then
		usage
		exit 0
	fi
	if [ "$arg" = "-D" ]; then
		DROP=1
		continue
	fi
	if [ "$arg" = "-F" ]; then
		FSTRIM=1
		continue
	fi
	if [ "$arg" = "-t" ]; then
		TESTONLY=1
		continue
	fi
	arg2=$(echo "$arg" | tr - _)
	if [ -e "/db/mysql/data/$arg2" ]; then
		if [ "$DB" ]; then
			echo "Only one database can be specified"
			exit 2
		else
			DB="$arg2"
		fi
		continue
	fi
	echo "Unknown DB or option: $arg"
done

if [ "$DB" ]; then
	if [ "$DB" = "mysql" ] || [ "$DB" = "performance_schema" ] || [ "$DB" = "information_schema" ]; then
		echo "Skipping request to detach/purge a system database ($DB)" >&2
		continue
	fi
	MOUNT=$(df "/db/mysql/data/$DB/" | grep -io "/db/[a-z0-9_-]*$" )
	MPMAP=$(df "/db/mysql/data/$DB/" | grep -io "/dev/mapper/[a-z0-9_-]*" | cut -d/ -f 4 )
	if [ "$MOUNT" = "/db/mysql" ] || [ "$MOUNT" = "/" ] || [ "$MOUNT" = "/var" ]; then
		echo "Skipping request to detach/purge a database on system volume ($DB on $MOUNT)" >&2
		continue
	fi
	FS_MULT_PIDS=$(fuser -m $MOUNT 2>/dev/null | grep -o '[0-9]\{1,\} [0-9].*')
	if [ "$FS_MULT_PIDS" ]; then
		echo "Database mountpoint $MOUNT has multiple processes accessing it.  We cannot proceed until nothing else is touching the filesystem (PIDS: $FS_MULT_PIDS)."
		exit 1
	fi
	echo "Disabling request queuing on map $MPMAP"
	# this will expose path errors to the application, so that mysqld can properly close FDs on blocked maps
	multipathd -k"disablequeueing map $MPMAP"
	echo ""
	if [ "$DROP" ]; then
		if [ "$TESTONLY" ]; then
			echo "[TESTONLY] DROP DATABASE IF EXISTS $DB"
		else
			echo "*** Drop database $DB, unmount $MOUNT, detach device map $MPMAP ***"
			read -p "Hit <enter> or wait 5 seconds to continue, or <ctrl-C> to cancel. " -t 5 x
			echo "Proceeding with: DROP DATABASE IF EXISTS $DB"
			sleep 1
			if mysql -e "DROP DATABASE IF EXISTS $DB"; then
				echo "DROP DATABASE IF EXISTS $DB - success"
				if [ "$FSTRIM" ]; then
					echo "Running fstrim $MOUNT to free up space on SAN"
					sync
					fstrim -v "$MOUNT"
				fi
			else
				echo "DROP DATABASE IF EXISTS $DB returned error, but trying to proceed anyway"
			fi
			sleep 1
	fi
	else
		if [ "$TESTONLY" ]; then
			echo "[TESTONLY] FLUSH DATABASE $DB"
		else
			if mysql-flush-db.sh $DB && mysql-flush-db.sh $DB; then
				echo "mysql-flush-db.sh $DB - success"
			else
				echo "mysql-flush-db.sh $DB returned error, but trying to proceed anyway"
			fi
		fi
	fi
	if [ "$TESTONLY" ]; then
		echo "[TESTONLY] would unmount $MOUNT"
	else
		umount -f "$MOUNT"
		umount -f "/dev/mapper/$MPMAP"
		if cat /proc/mounts |grep -q "^${MPMAP} "; then
			echo "Could not unmount /dev/mapper/$MPMAP but trying to proceed anyway"
		else
			echo "Unmounted /dev/mapper/$MPMAP"
		fi
	fi
	if [ "$TESTONLY" ]; then
		echo "[TESTONLY] would detach map $MPMAP"
	else
		detach-multipath.sh $MPMAP >/dev/null
		if [ -e "/dev/mapper/$MPMAP" ]; then
			echo "Could not detach map $MPMAP"
			exit 2
		else
			echo "detached multipath map $MPMAP"
		fi
	fi
	echo "Complete!"
else
	echo "No database specified." >&2
	exit 1
fi
