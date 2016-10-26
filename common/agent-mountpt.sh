#!/bin/bash

# agent-mountpt.sh
# (C) Nov 2005-Dec 2008 by Jim Klimov, COS&HT
# (C) 2005-2010 by Jim Klimov, COS&HT revisited for portability (v1.4+)
# $Id: agent-mountpt.sh,v 1.7 2010/11/15 14:32:09 jim Exp $

# Usage: agent-mountpt mountpoint [-t timeout]
# This script probes the specified mountpoint presumably
# imported from NFS server, but not necessarily. If the 
# mountpoint is actually unavailable (probe times out),
# report so by returning -1 (255). If it doesn't seem to be 
# mounted (according to mount command) return 2. Syntax
# errors in params return 1.

AGENTNAME="`basename "$0"`"
AGENTDESC="Try to access and probe a mountpoint"

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
	COSAS_BINDIR=`pwd`
fi
TIMERUN="$COSAS_BINDIR/timerun.sh"

# Defaults
TIMEOUT=5

do_help() {
	echo "Agent:	$AGENTNAME"
	echo "	$AGENTDESC"

	echo "Usage: $0 [-v] mountpoint [-t timeout]"
	echo "	-v		enable more verbose reports from this and sub agents"
	echo "	mountpoint	should go from root node /"
	echo "	timeout		default $TIMEOUT sec"
}

VERBOSE=""

PATH="/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/sbin:/usr/local/bin:$PATH"
export PATH

# Source optional config files
[ x"$COSAS_CFGDIR" = x ] && COSAS_CFGDIR="$COSAS_BINDIR/../etc"
if [ -d "$COSAS_CFGDIR" ]; then
    [  -f "$COSAS_CFGDIR/COSas.conf" ] && \
        . "$COSAS_CFGDIR/COSas.conf"
    [  -f "$COSAS_CFGDIR/`basename "$0"`.conf" ] && \
        . "$COSAS_CFGDIR/`basename "$0"`.conf"
fi
        
GOTWORK=no
while [ $# -gt 0 ]; do
	case "$1" in
		-h)
			do_help
			exit 0
			;;
		-v)	VERBOSE=-v;;
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
	echo "Current params incomplete: -t '$TIMEOUT' '$MOUNTPT'" >&2
	exit 1
fi

if [ "$VERBOSE" = "-v" ]; then
	echo "Current params: -t '$TIMEOUT' '$MOUNTPT'"
fi

# Check binaries
if [ ! -x "$TIMERUN" ]; then
	echo "Requires: timerun '$TIMERUN'" >&2
	exit 1
fi

# Checkers
check_mount() {
	### Check that it's mounted at the moment
	MPT="$1"

	case "`uname -s`" in
	    SunOS)
		MOUNTLIST=`mount | egrep '^'"$MPT"' '`
		;;
	    Linux)
		MOUNTLIST=`mount | egrep '^.* on '"$MPT"' '`
		;;
	esac
	if [ x"$MOUNTLIST" = x ]; then
		return 2
	fi
	return 0
}

check_df() {
	### Access fs's free space info
	MPT="$1"
	"$TIMERUN" "$TIMEOUT" df -k "$MPT" >/dev/null
}

check_ls() {
	### List fs objects under mountpoint
	MPT="$1"
	"$TIMERUN" "$TIMEOUT" ls -la "$MPT/" >/dev/null
}

# Do work
RESULT=0

### To be sure we also check at the end that mountpoint
### is still available,- useful for i.e. aircopy
### Start with "check_ls" for automounter to fire if applicable
### Thus "check_mount" may fail once before the "check_ls"
echo "Checking '$MOUNTPT' with max timeout '$TIMEOUT':"
TESTNUM=0
for CHECK in check_mount check_ls check_mount check_df check_mount; do
	TESTNUM=$(($TESTNUM+1))
	OUTPUT=`$CHECK $MOUNTPT 2>&1`
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
		if [ x"$CHECK" != xcheck_mount -o "$TESTNUM" -gt 2 ]; then
		    break
		fi
	fi
done

if [ $RESULT != 0 ]; then
	echo "Status:	FAILED" >&2
else
	echo "Status:	OK" >&2
fi

exit "$RESULT"
