#!/bin/bash

# $Id: zpool-scrub.sh,v 1.11 2013/11/13 14:09:42 jim Exp $
# this script will go through all pools and scrub them one at a time
#
# Use like this in crontab:
# 0 22 * * * [ -x /opt/COSas/bin/zpool-scrub.sh ] && /opt/COSas/bin/zpool-scrub.sh
#
# (C) 2007 nickus@aspiringsysadmin.com and commenters
# (C) 2009 Jim Klimov, cosmetic mods and logging; 2010 - locking
# http://aspiringsysadmin.com/blog/2007/06/07/scrub-your-zfs-file-systems-regularly/
#
[ x"$BUGMAIL" = x ] && BUGMAIL=postmaster

[ x"$ZPOOL" = x ] && ZPOOL=/usr/sbin/zpool
[ x"$TMPFILE" = x ] && TMPFILE=/tmp/scrub.sh.$$.$RANDOM
[ x"$LOCK" = x ] && LOCK="/tmp/`basename "$0"`.`dirname "$0" | sed 's/\//_/g'`.lock"

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

[ ! -x "$ZPOOL" ] && exit 1

### Include this after config files, in case of RUNLEVEL_NOKICK mask override
RUN_CHECKLEVEL=""
[ -s "$COSAS_BINDIR/runlevel_check.include" ] &&
    . "$COSAS_BINDIR/runlevel_check.include" &&
    block_runlevel

# Check LOCKfile
if [ -f "$LOCK" ]; then
    OLDPID=`head -n 1 "$LOCK"`
    BN="`basename $0`"
    TRYOLDPID=`ps -ef | grep "$BN" | grep -v grep | awk '{ print $2 }' | grep "$OLDPID"`
    if [ x"$TRYOLDPID" != x ]; then

        LF=`cat "$LOCK"`

        echo "= ZPoolScrub wrapper aborted because another copy is running - lockfile found:
$LF
Aborting..." | wall
        exit 1
    fi
fi
echo "$$" > "$LOCK"

scrub_in_progress() {
        ### Check that we're not yet shutting down
        if [ x"$RUN_CHECKLEVEL" != x ]; then
	    if [ x"`check_runlevel`" != x ]; then
		echo "INFO: System is shutting down. Aborting scrub of pool '$1'!" >&2
		zpool scrub -s "$1"
		return 1
	    fi
	fi

	if $ZPOOL status "$1" | grep "scrub in progress" >/dev/null; then
		return 0
	else
		return 1
	fi
}

#ZPOOL_LIST=""
while [ $# -gt 0 ]; do
case "$1" in
	-h|-help|--help)
		echo "Initiates a scrub of ZFS pool(s) sequentially and waits for it to finish"
		echo "Usage: $0 [-l|-L] [pool] [pool...]"
		echo "	-l|-L	Short or longer listing of pools and states"
		echo "	pool...	Scrub/long-list only named pool(s), by default all imported ones"
		exit 0
		;;
	-l)	echo "Available pools:"; $ZPOOL list; exit ;;
	-L)	echo "Available pools:"; $ZPOOL list
		[ x"$ZPOOL_LIST" = x ] && \
			echo "Available pools statuses:" || \
			echo "Selected pools statuses: $ZPOOL_LIST"
		$ZPOOL status $ZPOOL_LIST | egrep '(scrub|scan|pool|state|errors):|scrub|/s|%'
		exit ;;
	*)	ZPOOL_LIST="$ZPOOL_LIST $1" ;;
esac
shift
done
[ x"$ZPOOL_LIST" = x ] && ZPOOL_LIST="`$ZPOOL list -H -o name`"

trap 'echo "`date`: Received request to abort script $0. Last scrubbed pool ($pool) status:"; $ZPOOL status $pool; exit ' 0 1 2 3 15

RESULT=0
for pool in $ZPOOL_LIST; do
	echo "=== `TZ=UTC date` @ `hostname`: $ZPOOL scrub $pool started..."
	$ZPOOL scrub "$pool"

	while scrub_in_progress "$pool"; do sleep 60; done

	echo "=== `TZ=UTC date` @ `hostname`: $ZPOOL scrub $pool completed"

	if ! $ZPOOL status $pool | grep "with 0 errors" >/dev/null; then
		$ZPOOL status "$pool" | tee -a $TMPFILE
		RESULT=$(($RESULT+1))
	fi
done

trap '' 0 1 2 3 15

if [ -s $TMPFILE ]; then
	cat $TMPFILE | mailx -s "zpool scrub on `hostname` generated errors" "$BUGMAIL"
fi

rm -f $TMPFILE

# Be nice, clean up
rm -f "$LOCK"

exit $RESULT
