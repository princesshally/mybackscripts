#!/bin/bash
hosts="devmysql01 devmysql03 galmysql:01-10 prodmysql:02-06 qa-mysql01 qa-galmysql01 devgalmysql01 sandmysql01"
scriptfile=""

usage() {
  echo "$0 usage:"
  echo "$0 -h                    - show this helpful message"
  echo "$0 -s scriptname.sh      - upload this script to each host and run it there in a safe temp directory"
  echo "$0 -c command            - execute command on each host"
  echo "$0 -c \"command pipeline\" - execute command pipeline on each host"
  exit 0
}

while [ "$1" ]; do
  arg="$1"
  #echo "arg: $1"
  shift
  if [ "$arg" = "-h" ]; then
    usage
    exit
  fi
  if [ "$arg" = "-s" ] && [ -f "$1" ]; then
    scriptfile="$1"
    #echo "Set scriptfile to $scriptfile" >&2
    shift
    continue
  fi
  if [ "$arg" = "-c" ] && [ "$1" ]; then
    cmd="$*"
    break
  fi
done

if [ "$cmd" ] && [ "$scriptfile" ]; then
  echo "$0: command and scriptfile cannot be specified together."
  exit 1
fi

if echo "$scriptfile" | grep -q /; then
  echo "$0: scriptfile must exist in current directory and not contain directory elements"
  exit 1
fi

hostlist=""
for h1 in $hosts; do
#  echo "== $h1 =="
  prefix=$(echo "$h1" | cut -d: -f1)
  range=$(echo "$h1" |cut -s -d: -f2)
  if [ "$range" ]; then
    r1=$(echo "$range" | cut -d- -f1)
    r2=$(echo "$range" | cut -d- -f2)
    for suffix in $(seq -w $r1 $r2); do
      hostlist="$hostlist ${prefix}${suffix}"
    done
  else
    hostlist="$hostlist ${prefix}"
  fi
done

hostlist="$(echo $hostlist | sed -e 's/^ *//g' -e 's/ *$//')"
for host in $hostlist; do
#for host in galmysql01; do
  echo "${host}:"
  if [ "$cmd" ]; then
    echo "$cmd" | openssl base64 | ssh -q $host "openssl base64 -d | bash"
  fi
  if [ "$scriptfile" ]; then
    cat $scriptfile | gzip -1c | openssl base64 | ssh -q $host "(TD=\$(mktemp -d); if cd \$TD; then cat | openssl base64 -d | gzip -cd > $scriptfile && chmod a+rx $scriptfile && ./$scriptfile && echo __OK__ >&2 || echo __ERR:\${?}__ >&2; cd /tmp; rm -rf \$TD; fi)"
  fi
  echo ""
done
exit
