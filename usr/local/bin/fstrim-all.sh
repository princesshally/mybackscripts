#!/bin/bash
if echo "$@" | grep -q -e '-b'; then
  echo "Running detached fstrim job in the background." >&2
  (nohup $0 </dev/null >/dev/null 2>/dev/null & )
  exit 0
fi
BLACKLISTFILE=/etc/fstrim_blacklist.conf
which fstrim || exit 1
[ -f "$BLACKLISTFILE" ] || touch "$BLACKLISTFILE"
MOUNTS=$(cat /proc/mounts | egrep -i 'ext4|btrfs|xfs|reiser' | awk '{print $2}')
for M in $MOUNTS; do
  if grep -q "^${M}$" "$BLACKLISTFILE"; then
    echo "Ignoring blacklisted mount $M" >&2
    continue
  fi
  if fstrim -v "$M"; then
    echo "fstrim $M succeeded" >&2
  else
    echo "fstrim $M failed.  Adding to $BLACKLISTFILE" >&2
    echo "$M" >> "$BLACKLISTFILE"
  fi
done
