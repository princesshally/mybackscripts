#!/bin/bash
SRCDIR=$(pwd)
if [ "$1" = "-t" ]; then
  TESTONLY=1
  shift
fi
if [ "$#" != 2 ]; then
  echo "Usage: $0 srcdir dstdir"
  exit
fi
if cd "$1"; then
  SRCDIR="$1"
else
  echo "SRCDIR $1 does not exist"
  exit 1
fi

if cd "$2"; then
  DSTDIR="$2"
else
  echo "DSTDIR $2 does not exist"
  exit 1
fi

cleanupexit() {
  PID=$$
  echo "Caught signal.  Exiting."
  rmdir $(cat /tmp/sync-pending-${PID})
  rm -f ${DSTDIR}/.copy.*.${PID}
  exit
}

cscompare() {
  if [ ! -f "$1" ]; then
    echo "cscompare: $1 is not a regular file" >&2
    return 2
  fi
  if [ ! -f "$2" ]; then
    echo "cscompare: $2 is not a regular file" >&2
    return 2
  fi

  export F1="$1"
  export F2="$2"
  S1=$(stat --printf '%Y-%s' "$F1" 2>/dev/null)
  S2=$(stat --printf '%Y-%s' "$F2" 2>/dev/null)
  if [ "$S1" != "$S2" ]; then
    return 1
  fi
  FSZ=$(stat --printf '%s' "$F1" 2>/dev/null)
  if [ "$FSZ" -le 1048576 ]; then
#    echo "cscompare: small" >&2
    C1=$(dd if=$F1 bs=1048576 2>/dev/null | md5sum | cut -c1-32)
    C2=$(dd if=$F2 bs=1048576 2>/dev/null | md5sum | cut -c1-32)
    if [ "$C1" = "$C2" ]; then
      return 0
    fi
    return 1
  fi
  SKIP=$(echo "($FSZ/524288)-1" | bc)
  SKIPB=$(echo "$FSZ-($SKIP*524288)" | bc)
#  echo "cscompare: large, SKIP=$SKIP, b2sz=$SKIPB" >&2
  C1=$(dd if=$F1 bs=512k count=1 2>/dev/null | md5sum | cut -c1-32)$(dd if=$F1 bs=512k skip=$SKIP 2>/dev/null | md5sum | cut -c1-32)
  C2=$(dd if=$F2 bs=512k count=1 2>/dev/null | md5sum | cut -c1-32)$(dd if=$F2 bs=512k skip=$SKIP 2>/dev/null | md5sum | cut -c1-32)
  if [ "$C1" = "$C2" ]; then
    return 0
  fi
  return 1
}

find $SRCDIR -type f -printf '%f\n' | egrep -vi '\.(TMI|TMD)' | sort -R > /tmp/sync-list-$$
trap cleanupexit 1 2 3 11 15 14 13 17

while read SRCFILE; do
#  echo -n "$SRCFILE ... " >&2
  if [ -e "${SRCDIR}/${SRCFILE}" ]; then
    if cscompare "${SRCDIR}/${SRCFILE}" "${DSTDIR}/${SRCFILE}"; then
#      echo "SAME" >&2
      continue
    fi
    if mkdir "${DSTDIR}/.lock.${SRCFILE}" 2>/dev/null; then
      echo "${DSTDIR}/.lock.${SRCFILE}" > /tmp/sync-pending-$$
      if [ "$TESTONLY" ]; then
        echo "TESTONLY COPY ${SRCDIR}/${SRCFILE} ${DSTDIR}/.copy.${SRCFILE}.$$" >&2
      else
        /bin/cp -av "${SRCDIR}/${SRCFILE}" "${DSTDIR}/.copy.${SRCFILE}.$$" && mv "${DSTDIR}/.copy.${SRCFILE}.$$" "${DSTDIR}/${SRCFILE}"
      fi
      rmdir "${DSTDIR}/.lock.${SRCFILE}" 2>/dev/null
      [ "$TESTONLY" ] || rm /tmp/sync-pending-$$
    else
      echo "${DSTDIR}/${SRCFILE} locked.  Skipping."
    fi
  fi
#  echo ""
done < /tmp/sync-list-$$

rm /tmp/sync-list-$$
