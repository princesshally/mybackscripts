#!/bin/bash
# PFLOCAL
# PFDISTRIB mysql

cd /db/mysql/data || exit 3
c=0
while read x; do
	y=${x/.frm/}
	z=${y/\//.}
	q=$(strings $x | grep -i '^query=' | head -1 | cut -d= -f2-)
	if [ "$q" ]; then
		echo "${z}=${q}"
		c=$((c+1))
	fi
done <<< $(find . -type f -name '*.frm' -printf '%P\n' | sort)
echo "count=$c"
exit 0

