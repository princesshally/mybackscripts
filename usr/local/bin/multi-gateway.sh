#!/bin/bash
# PFLOCAL
# PFDISTRIB net admin

# multi-gateway.sh by Erik Schorr <erik@peoplefinders.com>
# v 20191007 - added config path var $CONF
# v 20250406 - added better option handling and debug code

# Format of /etc/multi-gateway.conf
#<ifname> <def_gateway_ip>
#bond0.1 192.168.16.1
#bond0.4 10.10.4.1

###########################################
DEBUG=''
TESTONLY=''
IFUP=''

while [ "$1" ]; do
  arg="$1"
  shift
  if [ "${arg:0:1}" = "-" ]; then
    if echo -- "$arg" | grep -q '[vD]'; then DEBUG=1; fi
    if echo -- "$arg" | grep -q 'n'; then TESTONLY=1; fi
    if echo -- "$arg" | grep -q 'i'; then IFUP=1; fi
  fi
done
  
CONF=/etc/multi-gateway.conf
ME=$(basename "$0" .sh)
TS=$(date +%Y%m%d-%H%M%S)
[ "$DEBUG" ] && echo "${ME} starting at ${TS}"

if [ ! -s "$CONF" ]; then
  echo "${ME}: Exiting because $CONF is missing or empty"
  exit 0
fi

PATH=/sbin:/usr/sbin:/bin:/usr/bin
# Get list of interfaces from $CONF
interfaces=$(grep -io '^[a-z][a-z0-9.]*' <"$CONF" | sort |uniq | tr '\n' ' ')

if which ipcalc >/dev/null; then
  echo "ipcalc ok" >/dev/null
else
  echo "$0: ipcalc isn't installed.  Please install it to use this script"
  echo "RH/CentOS: yum install ipcalc"
  echo "Deb/Ub: apt-get install ipcalc"
  exit 1
fi

echo "Configuring multiple-gateway policies for interfaces found in $CONF: $interfaces"

policyidx=100
for iface in $interfaces; do
  ruleidx="${policyidx}1"

  # Get primary IP addr of interface
  ipaddr=$(ip -o addr list dev $iface | grep 'inet ' | head -1 | grep -o '[0-9][0-9]*\.[0-9]*\.[0-9]*\.[0-9][0-9]*' | head -1 )

  # Get netmask/CIDRLEN of primary IP addr
  cidrlen=$(ip -o addr list dev $iface | grep 'inet ' | head -1 | grep -o '/[0-9][0-9]*' | cut -d/ -f2)

  # Find desired gateway for traffic leaving interface
  gateway=$(grep "^\b${iface}\b" <"$CONF" | tr -s ' ' '\t' | cut -f2)

  # Complain if anythingis missing
  if [ -z "$cidrlen" ] || [ -z "$ipaddr" ] || [ -z "$gateway" ]; then
    echo "NOTICE: $iface not configured or malformed/missing line in $CONF"
    continue
  fi

  # Find network address for interface
  netaddr=$(ipcalc -nb ${ipaddr}/${cidrlen} | grep -i 'network[=:]' | grep -o '[0-9][0-9.]*\.[0-9.]*[0-9]' )
  # Generate IP_IP_IP_IP_CIDR style identifier
  cidrid=$(echo ${netaddr}_${cidrlen} | tr . _)

  [ $DEBUG ] && echo "IF:$iface IP:$ipaddr NET:$netaddr LEN:$cidrlen CIDRID:$cidrid GW:$gateway"
  if grep -q "\b${cidrid}_gw_policy\b" /etc/iproute2/rt_tables; then
    echo "table name ${cidrid}_gw_policy already found in rt_tables - removing"
    sed -e "/\b{cidrid}_gw_policy\b/d" -i /etc/iproute2/rt_tables
  fi
  if grep -q "^${policyidx}" /etc/iproute2/rt_tables; then
    echo "table idx ${policyidx} already found in rt_tables - removing"
    sed -e "/${policyidx}\b/d" -i /etc/iproute2/rt_tables
  fi

  [ $DEBUG ] && echo "Adding ${policyidx} ${cidrid}_gw_policy to rt_tables"
  echo "${policyidx} ${cidrid}_gw_policy" >> /etc/iproute2/rt_tables

  # Clear rule list first
  ip rule list | grep "from ${netaddr}/${cidrlen}" | while read x; do
    p=$(echo "$x" | cut  -d: -f1)
    [ $DEBUG ] && echo "Removing old rule $x"
    ip rule del priority $p
  done

  # Install "connected-network" rule to bypass gateway for traffic to hosts on local network
  ip rule add priority $ruleidx from ${netaddr}/${cidrlen} to ${netaddr}/${cidrlen} lookup main
  ruleidx=$((ruleidx+1))

  # Install "remote-network" rule to use new policy for traffic to remote networks
  ip rule add priority $ruleidx from ${netaddr}/${cidrlen} lookup ${cidrid}_gw_policy
  ruleidx=$((ruleidx+1))

  # Remove old route tables
  ip route show table ${policyidx} | grep -q '[0-9]' && ip route del default table ${policyidx}

  # Add new ones for new per-interface policies
  ip route add default via ${gateway} table ${cidrid}_gw_policy
  
  policyidx=$((policyidx+1))
done
