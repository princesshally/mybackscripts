#!/bin/bash
# PFLOCAL
# PFDISTRIB mysql

usage() {
	echo "This script finds files in mysql data directories that aren't recognized as MySQL-related files, and optionally deletes them."
	echo ""
	echo "Usage:"
	echo "  With no args -- list foreign files in mysql data dirs, but don't do anything"
	echo "  $0 -l        -- List foreign files in mysql data dirs (simple)"
	echo "  $0 -L        -- List foreign files in mysql data dirs with details (ls -l)"
	echo "  $0 -D        -- Delete foreign files in mysql data dirs"
	echo "  $0 -h        -- show this helpful info"
	echo ""
}
if [ "$#" = 0 ]; then
	usage
	exit 0
fi
if [ "$LS_OPTS" ]; then
	LS_OPTS="-AldGhd"
else
	LS_OPTS="$LS_OPTS -lhd"
fi
opts=""
while [ "$1" ]; do
	arg="$1"; shift
	if [ "${arg:0:1}" = "-" ]; then
		opts="$opts${arg:1}"
	fi
done

if [[ "$opts" =~ h ]]; then
	usage
	exit 0
fi
if [[ "$opts" =~ D ]]; then
	DELETE=1
fi
if [[ "$opts" =~ l ]]; then
	LIST=1
fi
if [[ "$opts" =~ L ]]; then
	LIST=1
	DETAIL=1
fi

find /data/mysql/data/*/ /db/mysql/data/*/ -mindepth 1 -type f 2>/dev/null | egrep -av 'mysql/data/mysql' | egrep -av '\.(MYI|MYD|frm|par|MAI|MAD|opt|ibd)$' | sort | while read x; do
	if [ "$LIST" ]; then
		[ "$DETAIL" ] && ls $LS_OPTS "$x" || echo "$x"
	fi
	if fuser -v "$x" >&2; then
		echo "WARNING: $x is in use! (this file will not be deleted)" >&2
	else
		if [ "$DELETE" ]; then
			rm -f "$x"
		fi
	fi
done
exit 0
