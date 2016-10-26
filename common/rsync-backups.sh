#!/bin/bash

### (C) 2013-2015 by Jim Klimov, COS&HT
### Copies only newest backup files (new since last sync) to remote storage
###   export SYNC_ALL=y		to replicate all suitable files and
###				initialize the timestamp
### Currently rsync over NFS
### $Id: rsync-backups.sh,v 1.7 2015/07/07 15:02:12 jim Exp $

[ x"$TGTHOST" = x ] && TGTHOST="ucs-oracle-gz-vm"
[ x"$SRCDIR" = x ] && SRCDIR="/export/DUMP/regular"
[ x"$TGTDIR" = x ] && TGTDIR="/net/$TGTHOST/$SRCDIR"
[ x"$RSYNC_OPTS" = x ] && RSYNC_OPTS="-RDaP"

[ x"$DEBUG" = xY ] && QUIET="" || QUIET="-q"

[ x"$DUMPDIR_CHECK_TIMEOUT" = x ] && DUMPDIR_CHECK_TIMEOUT=15

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
        COSAS_BINDIR=`pwd`
fi
TIMERUN="$COSAS_BINDIR/timerun.sh"

# Source optional config files
[ x"$COSAS_CFGDIR" = x ] && COSAS_CFGDIR="$COSAS_BINDIR/../etc"
if [ -d "$COSAS_CFGDIR" ]; then
    [  -f "$COSAS_CFGDIR/COSas.conf" ] && \
        . "$COSAS_CFGDIR/COSas.conf"
    [  -f "$COSAS_CFGDIR/`basename "$0"`.conf" ] && \
        . "$COSAS_CFGDIR/`basename "$0"`.conf"
fi

LOCK="/tmp/`basename $0`__`echo "$SRCDIR" | sed 's,/,_,g'`__${TGTHOST}__`echo "$TGTDIR" | sed 's,/,_,g'`".lock
if [ -f "$LOCK" ] ; then
	echo "ERROR: LOCK file exists '$LOCK'" >&2
	exit 1
fi
trap "rm -f $LOCK" 0 1 2 3 15
echo $$ > "$LOCK"

checkdir() {
	DUMPDIR="$1"
	RES=0

	if [ -x "$TIMERUN" ]; then
	    "$TIMERUN" "$DUMPDIR_CHECK_TIMEOUT" ls -la "$DUMPDIR/" >/dev/null
	    if [ $? != 0 ]; then
	        echo "WARN: (archival) DUMPDIR='$DUMPDIR' is unreachable" >&2
		RES=1
	    fi
	else
	    if [ ! -d "$DUMPDIR" ]; then
	        echo "WARN: (archival) DUMPDIR='$DUMPDIR' is not a directory" >&2
		RES=1
	    fi
	fi
	return $RES
}

checkdir "$SRCDIR" || exit 1
checkdir "$TGTDIR" || exit 1

if ! cd "$SRCDIR" ; then
	echo "ERROR: Can't cd into '$SRCDIR'"
	exit 1
fi
if [ ! -d ".lastsync" ]; then
	mkdir ".lastsync" || exit 1
fi
touch ".lastsync/start-$TGTHOST" || exit 1
[ -f ".lastsync/lastsuccess-$TGTHOST" ] && \
	LS="-newer .lastsync/lastsuccess-$TGTHOST" || \
	LS="-mtime -7"

[ x"$SYNC_ALL" != x ] && LS=""

### For timestamp promotion we are interested in non-empty sync's
NUMF="`find . -type f $LS | egrep -v '\.__WRITING__$|^\./\.lastsync' | wc -l`" || NUMF=-1

rsync $RSYNC_OPTS $QUIET --exclude=.lastsync --exclude=.lastsync/* \
	--files-from=<( find . -type f $LS | egrep -v '\.__WRITING__$' ) \
	"$SRCDIR/" "$TGTDIR/" 
RESR=$?
[ "$NUMF" -gt 0 -a $RESR = 0 ] && \
    mv -f "$SRCDIR/.lastsync/start-$TGTHOST" \
	"$SRCDIR/.lastsync/lastsuccess-$TGTHOST"

exit $RESR
