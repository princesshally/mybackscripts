# library of common routines for pvc db deployment scripts
# PFLOCAL

# auto-set debuglevel based on program args
_pl_args="$@"
if [[ "${_pl_args}" =~ -DD*[0-9] ]]; then
	_pl_d0=$(echo "${_pl_args}" | grep -oe "-DD*[0-9][0-9]*" | grep -o "[0-9][0-9]*")
	if [ "${_pl_d0}" ]; then
		DEBUG=${_pl_d0}
		echo "set DEBUG to $DEBUG"
	fi
fi

# common variables
_0=$(echo "$0" | sed -e 's/^.*\///g')
PROGNAME=${_0}

# debug print
# example: dprint 5 "this is a debug message"
# Writes entries to DEBUGLOG if variable set (debug log file), regardless of debuglevel setting
# prepends contents of DPREFIX if non-empty to each log line
# arg 1: minimum debug level (DEBUG var) to print at.  If 0, always print.  If 1, print only if DEBUG set to 1 or higher.  If 2, print only if DEBUG set to 2 or higher
dprint() {
	_d=0
	if [[ "$1" =~ ^[0-9][0-9]*$ ]]; then
#		echo ":1: $1 ($@)"
		_d=$1
		shift
#		echo ":2: $1 ($@)"
		_msg=$@
	else
		_msg=$@
	fi
	_dp2=""
	if [ "$DPREFIX" ]; then
		_dp2="$DPREFIX "
		_dp3="$DPREFIX[$$]"
	fi
	if [ "$DEBUGLOG" ]; then
		_TS=$(TZ=UTC LANG=C date +%Y%m%d-%H%M%S);
		if [ "$_dp3" ]; then
			_LOGPREFIX="$_TS $_dp3 "
		else
			_LOGPREFIX="$_TS $0[$$] "
		fi
		echo "${_LOGPREFIX}$_msg" >> $DEBUGLOG
	fi
	if [ "$_d" = 0 ]; then
#		echo "${_dp2}$_msg" >&2
		echo $@
	else
		if [ $DEBUG ]; then
			if [ "$DEBUG" -ge "$_d" ]; then
				echo "${_dp2}[D$_d] $_msg" >&2
			fi
		fi
	fi
}

if [[ "$*" =~ -DD ]]; then
	DPREFIX="[pvc-lib]"
	dprint "D=$DEBUG,d=blank always print"
	dprint 0 "D=$DEBUG,d=0 always print"
	dprint 1 "D=$DEBUG,d=1"
	dprint 2 "D=$DEBUG,d=2"
	dprint 9 "D=$DEBUG,d=9"
fi

