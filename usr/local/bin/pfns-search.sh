#!/bin/bash
# PFLOCAL
# PFDISTRIB all
# PFREQUIRES isup.sh
# pfns-search.sh by Erik Schorr <erik@peoplefinders.com>
# This searches all listed nameservers for a given hostname or pattern within listed domains
# version 0.1 initial release 2022-12-16

NAMESERVERS="10.10.1.12 10.10.1.13 10.10.5.10 172.16.0.4 172.16.0.5 10.33.72.4 10.33.72.5 10.33.72.11 10.33.72.12 4.2.2.1 8.8.8.8"
DOMAINS="pfnetwork.net cco gateway.cco network.cco hadoop.cco hadoop.pfnetwork.net peoplefinders.com k8s.pfnetwork.net"

expat=""
pattern=""
type=a
#DEBUG=1

while [ "$1" ]; do 
  arg="$1"; shift
  if [ "${arg:0:1}" = "-" ]; then
    if [ "$arg" = "-D" ]; then
      DEBUG=1
      continue
    fi
    if [ "$arg" = "-t" ]; then
      type=$1
      shift
      continue
    fi
    if [ "$arg" = "-x" ]; then
      expat=$1
      shift
      continue
    fi
    if [ "$arg" = "-l" ]; then
      list=1
      continue
    fi
    if [ "$arg" = "-r" ]; then
      req="$1"
      shift
      continue
    fi
    echo "unknown option $arg"
    exit
  fi
  if [ -z "$pattern" ]; then 
    pattern="$arg"
    [ "$DEBUG" ] && echo "Set pattern to $pattern"
  fi
done

if [ -z "${list}${pattern}${req}" ]; then
  echo "Usage: $0 [-l pattern] | [-r name]"
  exit 0
fi

if [ -z "$pattern" ]; then pattern=.; fi
if [ -z "$expat" ]; then expat="999impossible999"; fi

# admin.pfpro04.pfnetwork.net is an alias for pfpro04.pfnetwork.net.
#  pfpro04.pfnetwork.net has address 10.33.17.14

for ns in $NAMESERVERS; do
  if isup.sh $ns >/dev/null 2>/dev/null; then
    if [ "$req" ]; then
      host -W 1 -t "$type" "${req}" "$ns" 2>/dev/null | egrep "is an alias|has address" | sed -e "s/^/$ns responds: /g"
    fi
    for d in $DOMAINS; do
      [ "$DEBUG" ] && echo "ns:$ns d:$d pattern:$pattern type:$type" >&2
      if [ "$req" ]; then
        host -W 1 -t "$type" "${req}.${d}" "$ns" 2>/dev/null | egrep "is an alias|has address" | sed -e "s/^/$ns responds: /g"
      else
        host -W 2 -l $d $ns 2>/dev/null | egrep "is an alias|has address" | sed -e "s/^/$ns responds: /g"
      fi
    done
  fi
done | grep -aiv "$expat" | egrep -ai "$pattern" | sort |uniq

