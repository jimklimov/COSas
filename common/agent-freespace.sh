#!/bin/bash

# agent-freespace.sh
# (C) Nov 2005-Dec 2008 by Jim Klimov, COS&HT
# (C) 2005-2010 by Jim Klimov, COS&HT revisited for portability (v1.5+)
# $Id: agent-freespace.sh,v 1.8 2014/12/09 13:28:38 jim Exp $

# Usage: agent-freespace [-v] [-t timeout] [-p freepct] [-k freekb] [-if freeinodes] [-ip freeinodespct] mountpoint"
# Checks free space and availability of given mountpoint.
# Output relies on "df -k" so there may be some root-reserved
# space above what is reported for users (5% by default)

AGENTNAME="`basename "$0"`"
AGENTDESC="Try to access and probe a mountpoint, then check how mouch free space there is"

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
	COSAS_BINDIR=`pwd`
fi
AGENT_MOUNTPT="$COSAS_BINDIR/agent-mountpt.sh"
TIMERUN="$COSAS_BINDIR/timerun.sh"

# Defaults
# Local fs may have little timeouts
# Trigger an error if under 5% or 10Mb are available to users
TIMEOUT=2
FREEPCT="5"
FREEKB="10000"
FREEINODES="1000"
FREEINODESPCT="5"

VERBOSE=""
QUICK=""

# Source optional config files
[ x"$COSAS_CFGDIR" = x ] && COSAS_CFGDIR="$COSAS_BINDIR/../etc"
if [ -d "$COSAS_CFGDIR" ]; then
    [  -f "$COSAS_CFGDIR/COSas.conf" ] && \
        . "$COSAS_CFGDIR/COSas.conf"
    [  -f "$COSAS_CFGDIR/`basename "$0"`.conf" ] && \
        . "$COSAS_CFGDIR/`basename "$0"`.conf"
fi             

do_help() {
	echo "Agent:	$AGENTNAME"
	echo "	$AGENTDESC"

	echo "Usage: $0 [-q] [-v] [-t timeout] [-p freepct] [-k freekb] [-if freeinodes] [-ip freeinodespct] mountpoint"
	echo "	-q		quick mode - skip accessibility checks and timeouts"
	echo "			ONLY checks free space/inodes via df. For use in loops"
	echo "	-v		enable more verbose reports from this and sub agents"
	echo "	mountpoint	should go from root node /"
	echo "	timeout		default 5 sec"
	echo "	freepct 	check fails if less than this %free is reported"
	echo "	freekb		check fails if less than this kb free is reported"
	echo "	freeinodes	check fails if less than this inodes free is reported"
	echo "	freeinodespct	check fails if less than this inodes % free is reported"
	echo "			! inodes are checked if applicable to this FStype"
}

GOTWORK=no
while [ $# -gt 0 ]; do
	case "$1" in
		-h)
			do_help
			exit 0
			;;
		-v)	VERBOSE=-v;;
		-q)	QUICK=-q;;
		-t)
			shift 1
			OK=no
			if [ x"$1" != x ]; then
				if [ "$1" -gt 0 ]; then
					TIMEOUT="$1"
					OK=yes
				fi
			fi
			if [ $OK = no ]; then
				echo "Wrong timeout, using default" >&2
			fi
			;;
		-p)
			shift 1
			OK=no
			if [ x"$1" != x ]; then
				if [ "$1" -ge 0 -a "$1" -le 100 ]; then
					FREEPCT="$1"
					OK=yes
				fi
			fi
			if [ $OK = no ]; then
				echo "Wrong freepct, using default" >&2
			fi
			;;
		-k)
			shift 1
			OK=no
			if [ x"$1" != x ]; then
				if [ "$1" -ge 0 ]; then
					FREEKB="$1"
					OK=yes
				fi
			fi
			if [ $OK = no ]; then
				echo "Wrong freekb, using default" >&2
			fi
			;;
		-if)
			shift 1
			OK=no
			if [ x"$1" != x ]; then
				if [ "$1" -gt 0 ]; then
					FREEINODES="$1"
					OK=yes
				fi
			fi
			if [ $OK = no ]; then
				echo "Wrong freeinodes, using default" >&2
			fi
			;;
		-ip)
			shift 1
			OK=no
			if [ x"$1" != x ]; then
				if [ "$1" -gt 0 -a "$1" -le 100 ]; then
					FREEINODESPCT="$1"
					OK=yes
				fi
			fi
			if [ $OK = no ]; then
				echo "Wrong freeinodespct, using default" >&2
			fi
			;;
		/*)	MOUNTPT="$1"
			GOTWORK=yes
			;;
		*)	echo "Unknown parameter: '$1'... a mountpoint should go from root /" >&2
			;;
	esac
	shift 1
done

if [ x"$GOTWORK" = xno ]; then
	do_help >&2
	echo "Current params incomplete: -t '$TIMEOUT' -p '$FREEPCT' -k '$FREEKB' -if '$FREEINODES' -ip '$FREEINODESPCT' '$MOUNTPT'" >&2
	exit 1
fi

if [ "$VERBOSE" = "-v" ]; then
	echo "Current params: -t '$TIMEOUT' -p '$FREEPCT' -k '$FREEKB' -if '$FREEINODES' -ip '$FREEINODESPCT' '$MOUNTPT'"
fi

if [ "$QUICK" = "-q" ]; then
	echo "WARNING: running in quick mode (skips check_access and timeouts)"
fi

# Check binaries
if [ ! -x "$TIMERUN" ]; then
	echo "Requires: timerun '$TIMERUN'" >&2
	exit 1
fi

if [ ! -x "$AGENT_MOUNTPT" ]; then
	echo "Requires: agent-mountpt '$AGENT_MOUNTPT'" >&2
	exit 1
fi

# Checkers
check_access() {
	if [ x"$QUICK" = x-q ]; then
		return 0
	else
		"$AGENT_MOUNTPT" $VERBOSE "$MOUNTPT" -t "$TIMEOUT"
		return $?
	fi
}

check_dfree_space() {
	if [ x"$QUICK" = x-q ]; then
		OUT=`df -k "$MOUNTPT"`
		RES=$?
	else
		OUT=`"$TIMERUN" "$TIMEOUT" df -k "$MOUNTPT"`
		RES=$?
	fi

	case "$RES" in
	0)
		if ! echo "$OUT" | tail -1 | egrep "[	 ]$MOUNTPT"'$' >/dev/null; then
			# Last line should have the mountpoint stats
			echo "Unexpected output from df: no mountpoint" >&2
			return 2
		fi
		NUMLINES=`echo "$OUT" | wc -l | awk '{print $1}'`
		case $NUMLINES in
			# We have a header line and 1 or 2 lines for FS info, depends on length of device name
			2) 
				USEDPCT=`echo "$OUT" | tail -1 | awk '{print $5}' | sed 's/\%//'`
				AVAILKB=`echo "$OUT" | tail -1 | awk '{print $4}'`
				;;
			3)
				USEDPCT=`echo "$OUT" | tail -1 | awk '{print $4}' | sed 's/\%//'`
				AVAILKB=`echo "$OUT" | tail -1 | awk '{print $3}'`
				;;
			*) echo "Unexpected output from df: $NUMLINES lines returned" >&2
				return 2
				;;
		esac
		AVAILPCT=$((100-$USEDPCT))
		if [ "$AVAILPCT" -lt "0" -o "$AVAILPCT" -gt 100 ]; then
			echo "Unexpected output from df: seems $AVAILPCT% free space is avail" >&2
			return 2
		fi

		if [ "$AVAILKB" -lt "0" ]; then
			echo "Unexpected output from df: seems $AVAILKB kb free space is avail" >&2
			return 2
		fi

		if [ "$AVAILPCT" -lt "$FREEPCT" ]; then
			echo "check_dfree_availpct:	FAILED	($AVAILPCT < $FREEPCT)" >&2
			return 3
		else
			echo "check_dfree_availpct:	0"
		fi

		if [ "$AVAILKB" -lt "$FREEKB" ]; then
			echo "check_dfree_availkb:	FAILED	($AVAILKB < $FREEKB)" >&2
			return 4
		else
			echo "check_dfree_availkb:	0"
		fi
		;;
	65535|255)
		echo "df timed out" >&2
		return "$RES"
		;;
	*)	echo "df error '$RES'" >&2
		return "$RES"
	esac
}

check_dfree_inodes() {
	RES=0
	if [ x"$QUICK" = x-q ]; then
		case "`uname -s`" in
		    SunOS)
			OUT="`df -o i "$MOUNTPT" 2>&1`"
			RES=$?
			;;
		    Linux)
			OUT="`df -i "$MOUNTPT" 2>&1`"
			RES=$?
			;;
		esac
	else
		case "`uname -s`" in
		    SunOS)
			OUT="`"$TIMERUN" "$TIMEOUT" df -o i "$MOUNTPT" 2>&1`"
			RES=$?
			;;
		    Linux)
			OUT="`"$TIMERUN" "$TIMEOUT" df -i "$MOUNTPT" 2>&1`"
			RES=$?
			;;
		esac
	fi

	case $RES in
	1)
		if echo "$OUT" | fgrep "df: operation not applicable for FSType " > /dev/null; then
			echo "check_dfree_inodes:	NA ($OUT)" >&2
			return 0
		fi
		if echo "$OUT" | fgrep "df: invalid option " > /dev/null; then
			echo "check_dfree_inodes:	NA ($OUT)" >&2
			return 0
		fi
		echo "df error $RES, output: $OUT" >&2
		return 1
		;;
	0)
		if ! echo "$OUT" | tail -1 | egrep "[	 ]$MOUNTPT"'$' >/dev/null; then
			# Last line should have the mountpoint stats
			echo "Unexpected output from df: no mountpoint" >&2
			return 2
		fi
		NUMLINES=`echo "$OUT" | wc -l | awk '{print $1}'`
		case $NUMLINES in
			# We have a header line and 1 or 2 lines for FS info, depends on length of device name
			2) case "`uname -s`" in
			    SunOS)
				USEDIPCT=`echo "$OUT" | tail -1 | awk '{print $4}' | sed 's/\%//'`
				AVAILI=`echo "$OUT" | tail -1 | awk '{print $3}'`
				;;
			    Linux)
			    	USEDIPCT=`echo "$OUT" | tail -1 | awk '{print $5}' | sed 's/\%//'`
				AVAILI=`echo "$OUT" | tail -1 | awk '{print $4}'`
				;;
			   esac ;;
			3) case "`uname -s`" in
			    SunOS)
				USEDIPCT=`echo "$OUT" | tail -1 | awk '{print $3}' | sed 's/\%//'`
				AVAILI=`echo "$OUT" | tail -1 | awk '{print $2}'`
				;;
			    Linux)
				USEDIPCT=`echo "$OUT" | tail -1 | awk '{print $4}' | sed 's/\%//'`
				AVAILI=`echo "$OUT" | tail -1 | awk '{print $3}'`
				;;
			   esac ;;
			*) echo "Unexpected output from df: $NUMLINES lines returned" >&2
				return 2
				;;
		esac
		AVAILIPCT=$((100-$USEDIPCT))
		if [ "$AVAILIPCT" -lt "0" -o "$AVAILIPCT" -gt 100 ]; then
			echo "Unexpected output from df: seems $AVAILIPCT% free inodes is avail" >&2
			return 2
		fi

		if [ "$AVAILI" -lt "0" ]; then
			echo "Unexpected output from df: seems $AVAILI free inodes are avail" >&2
			return 2
		fi

		if [ "$AVAILIPCT" -lt "$FREEINODESPCT" ]; then
			echo "check_dfree_availinodespct:	FAILED	($AVAILIPCT < $FREEINODESPCT)" >&2
			return 5
		else
			echo "check_dfree_availinodespct:	0"
		fi

		if [ "$AVAILI" -lt "$FREEINODES" ]; then
			echo "check_dfree_availinodes:	FAILED	($AVAILI < $FREEINODES)" >&2
			return 6
		else
			echo "check_dfree_availinodes:	0"
		fi
		;;
	65535|255)
		echo "df timed out" >&2
		return "$RES"
		;;
	*)	echo "df error '$RES', output: $OUT" >&2
		return "$RES"
	esac
}

# Start work
RESULT=0

for CHECK in check_access check_dfree_space check_dfree_inodes; do
	OUTPUT=`$CHECK 2>&1`
	RESULT=$?
	if [ "$VERBOSE" = "-v" -a x"$OUTPUT" != x ]; then
		echo "$CHECK:	$RESULT"
		echo "	Details:" >&2
		echo "$OUTPUT" | while IFS= read LINE; do
			echo "	$LINE" >&2
		done
	else
		echo "$CHECK:	$RESULT"
	fi
	if [ $RESULT != 0 ]; then
		break
	fi
done

# Report
if [ $RESULT != 0 ]; then
	echo "Status:	FAILED" >&2
else
	echo "Status:	OK" >&2
fi

exit "$RESULT"
