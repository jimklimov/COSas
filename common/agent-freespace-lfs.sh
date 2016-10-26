#!/bin/bash

# agent-freespace-lfs.sh
# (C) Nov 2005-Dec 2008 by Jim Klimov, COS&HT
# (C) 2005-2010 by Jim Klimov, COS&HT revisited for portability (v1.5+)
# (C) 2013 by Jim Klimov, COS&HT revisited for timeout flags (v1.7+)
# $Id: agent-freespace-lfs.sh,v 1.10 2014/12/08 16:29:19 jim Exp $

# This agent checks local mounted FSes for default limits
# May be later adapted to check specific FSes and their
# specific limits, check the CASE structure

AGENTNAME="`basename "$0"`"
AGENTDESC="Check availability and accessibility of mountpoints"

PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH
export PATH

BUGMAIL="root"

case "`uname -s`" in
    SunOS)
	LOCALFS=`( df -k /tmp; df -k -F ufs; df -k -F vxfs; df -k -F zfs ) 2>/dev/null | grep % | sed 's/^.* \(\/.*\)$/\1/' | sort | uniq`
	;;
    Linux)
	LOCALFS=`( df -k /tmp; df -k -F ext2; df -k -F ext3; df -k -F ext4; df -k -F xfs; df -k -F reiserfs; df -k -F vfat; df -k -F msdos ) 2>/dev/null | grep / | sed 's/^.* \(\/.*\)$/\1/' | sort | uniq`
	;;
esac

### Maybe append to this list manually, line by line:
# MANUALFS="/u01
#/u02
#/u03"

MANUALFS=""
TIMEOUT=""
FREEKB=""
FREEPCT=""
VERBOSE=""
### Regexp of filesystems to ignore, such as backups
#[ x"$EXCLUDEFS_RE" = x ] && EXCLUDEFS_RE="(DUMP|backup|var/cores)"
#EXCLUDEFS_RE=""

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
        COSAS_BINDIR=`pwd`
fi

# Source optional config files
[ x"$COSAS_CFGDIR" = x ] && COSAS_CFGDIR="$COSAS_BINDIR/../etc"
if [ -d "$COSAS_CFGDIR" ]; then
    [  -f "$COSAS_CFGDIR/COSas.conf" ] && \
	. "$COSAS_CFGDIR/COSas.conf"
    [  -f "$COSAS_CFGDIR/`basename "$0"`.conf" ] && \
	. "$COSAS_CFGDIR/`basename "$0"`.conf"
fi

while [ $# -gt 0 ]; do
case "$1" in
	-h)	echo "Checks local FSes free space"; exit 0;;
	-v)	VERBOSE=-v;;
	-t)	TIMEOUT="$2"; shift ;;
	-k)	FREEKB="$2"; shift ;;
	-p)	FREEPCT="$2"; shift ;;
	-x)	EXCLUDEFS_RE="$2"; shift ;;
	"")	;;
	*)	echo "Unknown param"; exit 1;;
esac
shift
done

AGENT_FREESPACE="$COSAS_BINDIR/agent-freespace.sh"

if [ ! -x "$AGENT_FREESPACE" ]; then
	echo "Requires: agent-freespace '$AGENT_FREESPACE'" >&2
	exit 1
fi

CHECKFS=`( echo "$LOCALFS"; echo "$MANUALFS" ) | egrep -v '$^' | sort | uniq`
[ x"$EXCLUDEFS_RE" != x ] &&
	CHECKFS="`echo "$CHECKFS" | egrep -v "$EXCLUDEFS_RE"`"
if [ x"$CHECKFS" = x ]; then
	echo "No FSes to check!" >&2
	exit 1
fi

PARAMS="-v"
[ x"$TIMEOUT" != x ] && if [ "$TIMEOUT" -gt 0 ]; then PARAMS="$PARAMS -t $TIMEOUT"; else echo "=== Invalid timeout: '$TIMEOUT'"; fi
[ x"$FREEKB" != x ] && if [ "$FREEKB" -gt 0 ]; then PARAMS="$PARAMS -k $FREEKB"; else echo "=== Invalid freekb: '$FREEKB'"; fi
[ x"$FREEPCT" != x ] && if [ "$FREEPCT" -gt 0 ]; then PARAMS="$PARAMS -p $FREEPCT"; else echo "=== Invalid freepct: '$FREEPCT'"; fi

check_fs () {
	MPT="$1"
	RESULT=1
	case "$FS" in
		# Can add specific check params here for wanted FSes
#example#	/)	OUTPUT=`"$AGENT_FREESPACE" -v "$MPT" -k 10000000 2>&1`; RESULT=$?;;
		/*)
			OUTPUT=`"$AGENT_FREESPACE" $PARAMS "$MPT" 2>&1`
			RESULT=$?
			;;
		*)
			OUTPUT="no such mountpoint: $MPT"
			;;
	esac

	if [ "$RESULT" != 0 ]; then
		# Output streamed to common error, below
		echo "
=== $FS:
$OUTPUT"
		df -k "$FS"
		df -o i "$FS" 2>/dev/null
		echo "$FS	FAILED" >&2
	else
		echo "$FS	OK" >&2
	fi
	return $RESULT
}

if [ x"$DEBUG" != x ]; then
	echo "Passing check_fs parameters to agent-freespace.sh: $PARAMS"
fi

# Make all checks in parallel; common failure caught below
OUTPUT_ALL=`
( for FS in $CHECKFS; do
	check_fs "$FS" &
done 2>&1 >&3 | sort >&2 ) 3>&1`

if [ $? != 0 -o x"$OUTPUT_ALL" != x ]; then
	if [ x"$VERBOSE" != x ]; then
		echo "$OUTPUT_ALL" >&2
	fi
	echo "Status:	FAILED"

	if [ x"$BUGMAIL" != x ]; then
		HOSTNAME=`hostname`
		TITLE="Check free space FAILED on $HOSTNAME at `date`"
		( echo "$TITLE"; echo "$OUTPUT_ALL" ) | mailx -s "$TITLE" "$BUGMAIL"
	fi
	exit 2
else
	echo "Status:	OK"
fi
