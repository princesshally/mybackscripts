#!/bin/bash
# PFLOCAL
# PFDISTRIB all
# block-dev-targetports.sh - shows relationsships between FC host ports, target ports, local devs, and local maps
# Initial release 2022-10-12
# Erik Schorr <erik@enformion.com>

# default output format (FMT=p for parsable, FMT=t for tree)
FMT=t

# No user-serviceable items below

usage() {
	echo "Usage:"
	echo "$0 [-p] [-h]"
	echo "  -p : output machine-parsable output (defaults to tree view)"
	echo "  -t : output machine-parsable output (defaults to tree view)"
	echo "  -h : show this help"
	echo ""
	echo "This script is the work of Erik Schorr <code@arpa.org>"
	echo "Release: 20221012"
	echo "Copyleft / Creative Commons / Include Attribution"
	echo "This script comes with no guarantees or warranties of any kind."
	echo "Enhancements welcome; send ideas/questions to maintainer."
	echo ""
}

while [ "$1" ]; do
	arg="$1"; shift
	if [ "$arg" = "-p" ]; then
		FMT=p
		continue
	fi
	if [ "$arg" = "-t" ]; then
		FMT=t
		continue
	fi
	if [ "$arg" = "-h" ]; then
		usage
		exit 0
	fi
	usage
	exit 2
done

if uname | grep -q Linux; then
	if uname -r | grep -q "^[34]\."; then
		echo "Supported OS/Version!" >/dev/null
	else
		echo "This script requires Linux kernel 4.x or later" >&2
		exit 3
	fi
else
	echo "This script requires Linux kernel 4.x or later" >&2
	exit 3
fi

[ "$FMT" = "p" ] && echo "HostNum,HostPortName,HostPortID,TargetPortName,TargetPortID,VolID,MapName,ScsiAddr,DiskDev"
#find /sys/class/fc_host/ -maxdepth 1 -type l | while read fchost; do
while read fchost; do
  if [ -z "$fchost" ]; then
    continue
  fi
  host=$(echo "$fchost" |grep -o "host[0-9][0-9]*")
  if [ -f "${fchost}/port_id" ]; then
	  i_pid=$(cat ${fchost}/port_id | sed -e 's/^0x//')
  fi
  if [ -f "${fchost}/port_name" ]; then
	  i_wwpn=$(cat ${fchost}/port_name | sed -e 's/^0x//')
  fi
  if [ -f "${fchost}/node_name" ]; then
	  i_wwnn=$(cat ${fchost}/node_name | sed -e 's/^0x//')
  fi
  [ "$FMT" = "t" ] && echo "FC initiator h:$host n:$i_wwnn p:$i_wwpn pid:$i_pid"
  [ "$FMT" = "t" ] && [ "$verbose" ] && (cd $fchost && grep . symbolic_name port_state supported_speeds tgtid_bind_type speed port_id node_name port_name dev_loss_tmo | sed -e 's/^/  /g')
  HOSTDIR=$(cd $fchost && /bin/pwd)
  find "$HOSTDIR/device/" -maxdepth 1 -name 'rport-*:*-*' | while read rport; do
    r2=$(echo $rport | grep -o 'device/.*$')
    [ "$FMT" = "t" ] && echo "   -> $host $r2"
    t_nn=$(find "$rport/" -path "*/fc_remote_ports*" -name "node_name" | xargs -r grep -o '0x[a-f0-9]*$' | sed -e 's/^0x//')
    t_pn=$(find "$rport/" -path "*/fc_remote_ports*" -name "port_name" | xargs -r grep -o '0x[a-f0-9]*$' | sed -e 's/^0x//')
    t_id=$(find "$rport/" -path "*/fc_remote_ports*" -name "port_id" | xargs -r grep . | sed -e 's/^0x//')
    [ "$FMT" = "t" ] && echo "     -> target n:$t_nn p:$t_pn pid:$t_id"
    f="" 
    while read dev; do
      if [ -z "$dev" ]; then
	continue
      fi
      f=1	   
      wwvn=$(find /sys/block/${dev}/device/ -name wwid 2>/dev/null | xargs -r cat)
      map=$(find /sys/block/${dev}/holders/dm*/dm/ -name name 2>/dev/null | xargs -r cat)
      spath=$(find /sys/block/${dev}/device/bsg/ -mindepth 1 -maxdepth 1 -name '*:*:*:*' -printf '%f\n')
      if [ "$map" ]; then
        [ "$FMT" = "t" ] && echo "       -> $spath/$dev ($wwvn,$map)"
      else
        [ "$FMT" = "t" ] && echo "       -> $spath/$dev ($wwvn,N/A)"
      fi
      [ "$FMT" = "p" ] && echo "${host},${i_wwpn},${i_pid},${t_pn},${t_id},${wwvn},${map},${spath},${dev}"
    done <<< $(find "$rport/" -name "sd*[a-z]" | grep -o 'target[0-9].*sd[a-z][a-z]*$' | grep -o 'sd[a-z][a-z]*' | sort )
    if [ -z "$f" ]; then
	    [ "$FMT" = "t" ] && echo "       -> (no devs configured/found on target $target)"
    fi

  done
done <<< $(find /sys/class/fc_host/ -maxdepth 1 -type l | sort )
