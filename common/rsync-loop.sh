#!/bin/bash

# $Id: rsync-loop.sh,v 1.17 2014/01/25 11:57:17 jim Exp $
# (C) Jim Klimov, 2005-2014
# CURRENT: Loop to initiate rsync from local to remote, sleep.

# TODO: Detect changed local files and initiate sync to remote storage
# (ideas partially based on cpaw-nfs.sh and clean-dump.sh (C) Jim Klimov).

### Admin should setup passwordless ssh-key auth from local host to remote.
### Typical sync from localhost author to remote public:
###   rsync -rtlHKv --partial --partial-dir=.partial /mnt/mediacontent/ otherserver:/mnt/mediacontent/; echo $?

### Directories in local/remote server filesystems
### HINT: end paths with a slash to avoid surprises
SRCPATH=/mnt/mediacontent/
DSTPATH=/mnt/mediacontent/
### An empty host is assumed to be localhost (no host: string prepended to path)
SRCHOST=""
DSTHOST=otherserver

SLEEP=10
### Even if no changes were detected, force a sync every FORCESYNC loops
FORCESYNC=60
### Force a sync with checksum comparison every FORCESYNC loops
FORCEBIGSYNC=600

### If source files were deleted, should we delete remote copies?
PROMOTE_DELETION=yes

### Basic RSync options used in each case (more options may be added
### for certain parts of the loop). The "partial" options below are
### an optimization for atomic appearance of copied files in the target
### location; it is assumed that they appear and are later unchanged on
### the origin (otherwise this may be an expensive way to copy updates)
RSYNC_OPTIONS_COMMON="-rtLHK --partial --partial-dir=.partial"
### Do a full verbose sync, checking checksums of existing files
RSYNC_OPTIONS_INITIAL="-vcz"
### Do a verbose sync during usual runs (files changed or patience timeout)
RSYNC_OPTIONS_USUAL="-v"

### Use this option to treat local symlinks to dirs like directories with files
#FIND_FOLLOW="-follow"
FIND_FOLLOW=""

### Don't let maintenance script break server's real works
[ x"$RENICE" = x ] && RENICE=17

### If LOGFILE is set, pass stdout and stderr into it
### May be inherited from environment, i.e. initscript
#LOGFILE=""

### General envvars
LANG=C
LC_ALL=C
PATH=/usr/local/bin:/opt/sfw/bin:/usr/sfw/bin:$PATH
LD_LIBRARY_PATH=/usr/local/lib:/opt/sfw/lib:/usr/sfw/lib:$LD_LIBRARY_PATH
export LANG LC_ALL PATH LD_LIBRARY_PATH
### rsync binary is now assumed to be in PATH

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
        COSAS_BINDIR=`pwd`
fi

AGENTNAME="`basename "$0"`"
AGENTDESC="rsync loop of changed files from local host to remote host"

# Source optional config files
[ x"$COSAS_CFGDIR" = x ] && COSAS_CFGDIR="$COSAS_BINDIR/../etc"
if [ -d "$COSAS_CFGDIR" ]; then
    [  -f "$COSAS_CFGDIR/COSas.conf" ] && \
        . "$COSAS_CFGDIR/COSas.conf"
    [  -f "$COSAS_CFGDIR/`basename "$0"`.conf" ] && \
        . "$COSAS_CFGDIR/`basename "$0"`.conf"
fi

### Include this after config files, in case of RUNLEVEL_NOKICK mask override
RUN_CHECKLEVEL=""
[ -s "$COSAS_BINDIR/runlevel_check.include" ] &&
    . "$COSAS_BINDIR/runlevel_check.include" &&
        block_runlevel

LOCK_BASE="/tmp/$AGENTNAME.lock"
WAIT_C=0
WAIT_S=15
LOCK="$LOCK_BASE.`echo "$SRCHOST%$SRCPATH===$DSTHOST%$DSTPATH" | sed 's/\//_/g'`"

RSYNC_DELETE=""
[ x"$PROMOTE_DELETION" = xyes ] && RSYNC_DELETE=" --delete-after"

[ x"$FIND_FOLLOW" != x"-follow" ] && FIND_FOLLOW=""

check_lock() {
# Check LOCKfile
if [ -f "$LOCK" ]; then
    OLDPID=`head -n 1 "$LOCK"`
    TRYOLDPID=$(ps -ef | grep `basename $0` | grep -v grep | awk '{ print $2 }' | grep "$OLDPID")
    if [ x"$TRYOLDPID" != x ]; then

        LF=`cat "$LOCK"`

        echo "Older lockfile found:
$LF"
            if [ ! "$WAIT_C" -gt 0 ]; then
                ### Catch <=0 as well as errors
                exit 2
            fi
            echo "Sleeping $WAIT_C times of $WAIT_S seconds to give it a fix..."
        W=0
            while [ "$W" -lt "$WAIT_C" ]; do
            sleep $WAIT_S
            [ ! -s "$LOCK" ] && break
                W="$(($W+1))"
            echo -n "."
        done
            if [ "$W" = "$WAIT_C" -a "$WAIT_C" != 0 ]; then
            echo "Older lockfile found:
$LF
Sleeps timed out ($WAIT_C*$WAIT_S sec) - $0 on $HOSTNAME froze!?

`date`
`$COSAS_BINDIR/proctree.sh -P $LF`
" | mailx -s "$0 on $HOSTNAME locked"  "$BUGMAIL"
            exit 1
        fi
    fi
fi
}

################################################################################

do_rsync() {
	rsync $RSYNC_OPTIONS_COMMON $@ \
		${SRCHOST:+"$SRCHOST:"}${SRCPATH} \
		${DSTHOST:+"$DSTHOST:"}${DSTPATH}
}

longsleep() {
	### Easily breakable sleep
	COUNT=0
	MAX="$1"
	[ x"$MAX" = x ] && MAX="$SLEEP"
	[ "$MAX" -gt 0 ] || MAX="$SLEEP"
	[ "$MAX" -gt 0 ] || MAX=10

	while [ "$COUNT" -le "$MAX" ]; do
	    COUNT=$(($COUNT+1))
	    sleep 1
	done
}

GDIFF=""
for G in /bin/diff /bin/gdiff /usr/bin/gdiff /usr/local/bin/gdiff /opt/sfw/bin/gdiff /usr/sfw/bin/gdiff; do
    [ x"$GDIFF" = x -a -x "$G" ] && "$G" -bu "$0" "$0" >/dev/null 2>&1 && GDIFF="$G"
done

main_loop() {
### This script publishes files received from editors and saved by magnolia
### into a local directory SRCPATH and transfers them to remote DSTPATH.
### Subdirectory hierarchy is maintained, access rights are not cared about.

check_lock

### Discover current PID of a possibly forked bash subprocess - myself...
MYPID=$$
case "$1" in
    FG) MYPID=$$ ;;
    BG) sleep 20 2>/dev/null &
	MYPID="$(ps -ef | awk '( $2 == '$!' ) { print $3 };')"
	[ $? != 0 -o x"$MYPID" = x ] && MYPID=$$
	#kill -1 $! 2>/dev/null
	;;
esac
echo "$MYPID" > "$LOCK"
rm -f "$LOCK.find0" "$LOCK.find1" "$LOCK.find2"

echo "`date`: Started, PID=$MYPID. Doing initial sync after startup..."
RES=127

if [ x"$RENICE" != x ]; then
        echo "INFO: Setting process priority for work: '$RENICE'"
        renice "$RENICE" $MYPID
fi

BREAK=0
trap 'echo ""; echo "`date`: $0: PID=$MYPID: BREAK detected, finishing script..."; BREAK=1; exit 0; ' 1 2 3 15
trap 'echo ""; echo "`date`: $0: PID=$MYPID: Removing lock-file $LOCK and exiting ($RES)"; rm -f "$LOCK" "$LOCK.find0" "$LOCK.find1" "$LOCK.find2"; exit "$RES"; ' 0

while [ "$RES" != 0 -a "$BREAK" = 0 ]; do
	do_rsync $RSYNC_OPTIONS_INITIAL $RSYNC_DELETE
	RES=$?
	if [ "$RES" != 0 -a "$BREAK" = 0 ]; then
		echo "`date`: rsync error ($RES), retrying after $SLEEP sec..."
		longsleep $SLEEP
	fi
done
[ "$BREAK" != 0 ] && exit $RES
[ x"$SRCHOST" = x -o x"$SRCHOST" = xlocalhost ] && find "$SRCPATH" -ls $FIND_FOLLOW > "$LOCK.find0"

echo ""
echo "`date`: Initial sync after startup completed. Current file-list:"
do_rsync --list-only
RES=$?
[ "$BREAK" != 0 ] && exit $RES

echo ""
echo "`date`: Now looping infinitely to rsync any updates (every $SLEEP seconds)..."
RES=0

FORCESYNC_COUNT=0
FORCEBIGSYNC_COUNT=0
while [ "$BREAK" = 0 ]; do
	DO_SYNC=no
	FORCESYNC_COUNT=$(($FORCESYNC_COUNT+1))
	FORCEBIGSYNC_COUNT=$(($FORCEBIGSYNC_COUNT+1))

	### If localhost is the pushing source:
	if [ x"$SRCHOST" = x -o x"$SRCHOST" = xlocalhost ]; then
	    mv -f "$LOCK.find1" "$LOCK.find2" 2>/dev/null
	    mv -f "$LOCK.find0" "$LOCK.find1"
	    find "$SRCPATH" -ls $FIND_FOLLOW > "$LOCK.find0"

	    ### TODO: Add detection of changed files here as to not use rsync
	    ### when there's nothing to update or while changes are underway.
	    ### One start would be to find a file which is different in all
	    ### 3 stages of history...

	    DIFFRES=0
	    if [ x"$GDIFF" != x ]; then
		OUT="`"$GDIFF" -bu "$LOCK.find1" "$LOCK.find0"`"
		DIFFRES=$?
		OUT="`echo "$OUT" | egrep '^[+-]' | egrep -v '^(\-\-\-|\+\+\+)'`"
	    else
		### At least some diff should exist!?
		OUT="`diff "$LOCK.find1" "$LOCK.find0"`"
		DIFFRES=$?
		OUT="`echo "$OUT" | egrep '^[><]'`"
	    fi
		### TODO?: maybe revert to CATing files to string vars
		### and comparing them? ;)

	    if [ $DIFFRES != 0 ]; then
		echo "`date`: Causing an rsync because files have changed:"
		echo "$OUT"
		DO_SYNC=yes
	    fi
	fi

	### Rarely do a checksum matching sync as well; may follow a changed-file sync (on next cycle)
	if [ x"$DO_SYNC" = xno -a "$FORCEBIGSYNC_COUNT" -ge "$FORCEBIGSYNC" ]; then
	    echo "`date`: Causing a rsync-with-checksums just-in-case after $FORCEBIGSYNC_COUNT empty $SLEEP-second cycles elapsed..."
	    DO_SYNC=big
	fi

	### Run rsync anyway every once in a while just in case, if no syncs were done recently
	if [ x"$DO_SYNC" = xno -a "$FORCESYNC_COUNT" -ge "$FORCESYNC" ]; then
	    echo "`date`: Causing an rsync-just-in-case after $FORCESYNC_COUNT empty $SLEEP-second cycles elapsed..."
	    DO_SYNC=yes
	fi

	RES=0
	case x"$DO_SYNC" in
	    xbig)
	        do_rsync $RSYNC_OPTIONS_INITIAL $RSYNC_DELETE
		RES=$?
	        FORCESYNC_COUNT=0
		FORCEBIGSYNC_COUNT=0

		[ "$RES" = 0 ] || echo "`date`: RSYNC returned with an error ($RES)"
		;;
	    xyes)
	        do_rsync $RSYNC_OPTIONS_USUAL $RSYNC_DELETE
		RES=$?
	        FORCESYNC_COUNT=0

		[ "$RES" = 0 ] || echo "`date`: RSYNC returned with an error ($RES)"
		;;
	    xno|*) ;;
	esac

	### Should an RSYNC error/abortion break the loop?
	#[ "$RES" != 0 ] && BREAK=2

	[ "$BREAK" = 0 ] && longsleep $SLEEP
done

echo ""
echo "`date`: Infinite loop complete, exiting..."
exit $RES
### Exit processed by trap(0)
}

stop_loop() {
	if [ -f "$LOCK" ]; then
	    OLDPID=`head -n 1 "$LOCK"`
	    TRYOLDPID=$(ps -ef | grep `basename $0` | grep -v grep | awk '{ print $2 }' | grep "$OLDPID")
	    if [ x"$TRYOLDPID" != x ]; then
		echo "`date`: Stopping PID(s) $TRYOLDPID"
		if [ -x /opt/COSas/bin/proctree.sh ]; then
		    /opt/COSas/bin/proctree.sh -s 15 $TRYOLDPID
		else
		    kill -15 $TRYOLDPID
		fi
		sleep 5
	    fi
	fi
}

MYPID=$$
trap 'if [ x"$LOGFILE" != x ]; then exec >>"$LOGFILE" 2>&1; echo "`date`: $0 $@: PID=$MYPID, begin writing logs to file"; fi' USR1
kill -USR1 $$

case "$1" in
    stop)
	stop_loop
	;;
    start)
	main_loop BG &
	;;
    restart)
	stop_loop
	main_loop BG &
	;;
    *)
	main_loop FG
	;;
esac
