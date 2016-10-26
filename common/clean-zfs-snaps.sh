#!/bin/bash

# $Id: clean-zfs-snaps.sh,v 1.9 2015/05/15 08:09:02 jim Exp $
# (C) 2013-2015 by Jim Klimov
# This script should find and clean up same-named snapshots conforming to
# a pattern specified by the user, starting from the oldest (by "creation"
# attribute), until some specified amount of free space is made on the pool.
# Requires a GNU gegrep and a SUN awk; so the PATH is preset accordingly.
# Crontab incantation:
#   50 23 * * * [ -x /opt/COSas/bin/clean-zfs-snaps.sh ] && { PRESERVE_OLDEST=0; PRESERVE_NEWEST=5 ; DEBUG=0; export PRESERVE_OLDEST PRESERVE_NEWEST DEBUG; BASEDS=rpool NEEDED_FREE_SPACE=1g /opt/COSas/bin/clean-zfs-snaps.sh; BASEDS=pool NEEDED_FREE_SPACE=7g /opt/COSas/bin/clean-zfs-snaps.sh; } 2>&1 | egrep -v '^$|No .* snaps found|Nothing to do | after chomping away '

# TODO:
# * Command-line parameters for the variables involved
# * Let call certain routines via command-line (but group them by default)
# * See now if parsing the timestamps (or sizes) is at all needed?
#   Or make up some usecase for that?

# RegExp that matches a string for timestamps, usable by sed/egrep/(awk?)
TSRE='([0-9]{8}(T|t|Z|z|:|-)*[0-9]{6}(Z|z)?|([0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{8})(Z|z|-)[0-9]{2}(:|h|-)*[0-9]{2})'

# RegExp that matches ZFS auto-snapshot tags from several versions of the
# time-slider and equivalents (no leading "@" although it is assumed to
# be directly leading the matching regexp)
TEMPLATE_RE_ZAS='zfs-auto-snap[\:_-](frequent|hourly|daily|weekly|monthly|yearly|event)-@TSRE@'
TEMPLATE_RE_VBOX='vboxsvc-auto-snap:.*:@TSRE@'
TEMPLATE_RE_RSYNC='rsync-beforeBackup-@TSRE@|rsync-afterBackup-@TSRE@-(completed|failed-[0-9]*)'

# How many (>=0) oldest and newest snapshots should be retained after autoclean
[ -z "$PRESERVE_OLDEST" ] && \
    PRESERVE_OLDEST=1
[ -z "$PRESERVE_NEWEST" ] && \
    PRESERVE_NEWEST=3
[ "$PRESERVE_OLDEST" -ge 0 ] 2>/dev/null || PRESERVE_OLDEST=1
[ "$PRESERVE_NEWEST" -ge 0 ] 2>/dev/null || PRESERVE_NEWEST=3

KILLFIRST_RE_RSYNC='rsync-afterBackup-@TSRE@-failed-[0-9]*'

[ -z "$TEMPLATE_RE_INTERESTING" ] && \
    TEMPLATE_RE_INTERESTING="($TEMPLATE_RE_ZAS|$TEMPLATE_RE_VBOX|$TEMPLATE_RE_RSYNC)"
[ -z "$RE_INTERESTING" ] && \
    RE_INTERESTING="`printf '%s\n' "$TEMPLATE_RE_INTERESTING" | sed 's,@TSRE@,'"${TSRE}",g | tr -d '\n'`"

[ -z "$KILLFIRST_RE_COMBINED" ] && \
    KILLFIRST_RE_COMBINED="$KILLFIRST_RE_RSYNC"
[ -z "$RE_KILLFIRST" ] && \
    RE_KILLFIRST="`printf '%s\n' "$KILLFIRST_RE_COMBINED" | sed 's,@TSRE@,'"${TSRE}",g | tr -d '\n'`"

# Default dataset
[ -z "$BASEDS" ] && BASEDS='temp'

# Default verbosity level
[ -z "$DEBUG" ] && DEBUG=1
# Detail programs being executed if the DEBUG level is at least this:
DEBUG_LEVEL_TRACE=3

##########################################################################
# General constraints
PATH="/sbin:/usr/sbin:/bin:/usr/bin:/usr/sfw/bin:/opt/sfw/bin:/usr/gnu/bin:/opt/local/bin:$PATH"
LANG=C
LC_ALL=C
TZ=UTC
export LANG LC_ALL PATH TZ

# If the shell is bash or compatible, handle failures inside pipes better
set -o pipefail 2>/dev/null || true

AGENTNAME="`basename "$0"`"
AGENTDESC="Clean up automatically made snapshots"

TIMEOUT=15

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
	COSAS_BINDIR=`pwd`
fi
TIMERUN="$COSAS_BINDIR/timerun.sh"

# Params for lockfile
BUGMAIL="postmaster"
HOSTNAME=`hostname`

LOCK_BASE="/tmp/$AGENTNAME.lock"
# Set WAIT_C=0 to skip waits
WAIT_C=5
WAIT_S=15

CHECKONLY=0
[ x"$READONLY" = xyes ] && CHECKONLY=1

# Don't let maintenance script break server's real works
[ x"$RENICE" = x ] && RENICE=17
[ x"$RENICE" = x- ] && RENICE=""

### Include this after config files, in case of RUNLEVEL_NOKICK mask override
RUN_CHECKLEVEL=""
[ -s "$COSAS_BINDIR/runlevel_check.include" ] && \
    . "$COSAS_BINDIR/runlevel_check.include" && \
    block_runlevel

# Source optional config files
[ x"$COSAS_CFGDIR" = x ] && COSAS_CFGDIR="$COSAS_BINDIR/../etc"
if [ -d "$COSAS_CFGDIR" ]; then
    [  -f "$COSAS_CFGDIR/COSas.conf" ] && \
        . "$COSAS_CFGDIR/COSas.conf"
    [  -f "$COSAS_CFGDIR/`basename "$0"`.conf" ] && \
        . "$COSAS_CFGDIR/`basename "$0"`.conf"
fi

# Aim for this amount of jobs, wait for launched ones to complete before
# continuing the loop, so as not to strain the system too much
[ -z "$MAX_PARALLEL_JOBS" ] && MAX_PARALLEL_JOBS=100
[ "$MAX_PARALLEL_JOBS" -ge 1 ] 2>/dev/null || MAX_PARALLEL_JOBS=100

[ x"$RENICE" = x- ] && RENICE=""
LOCK="$LOCK_BASE.`echo "$BASEDS" | sed 's,/,_,g'`"

# Check LOCKfile
if [ -f "$LOCK" ]; then
        OLDPID=`head -n 1 "$LOCK"`
        TRYOLDPID=$(ps -ef | grep `basename $0` | grep -v grep | awk '{ print $2 }' | grep "$OLDPID")
        if [ x"$TRYOLDPID" != x ]; then
                LF=`cat "$LOCK"`
                if [ $CHECKONLY = 0 ]; then
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
                        [ ! -s "$LOCK" -a ! -d "/proc/$TRYOLDPID" ] && break
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
        else
                ### CHECKONLY != 0
                echo "NOTE: Active lockfile of disruptive-mode instance of this script was found:
$LF"
                for PID in $LF; do
                        ps -ef | grep -v grep | grep -w "$PID"
                done
                fi
        fi
fi

[ $CHECKONLY = 0 ] && echo "$$" > "$LOCK"

if [ x"$RENICE" != x ]; then
    [ "$VERBOSE" = -v ] && \
        echo "INFO: Setting process priority for work: '$RENICE'"
    renice "$RENICE" $$
fi

# List of SMF services stoppped before work (recover this upon exit)
SVCS_STOPPED=""


#####################################################################
Qk="1024"
Qm="`expr 1024 '*' 1024`" || Qm=1048576
Qg="`expr 1024 '*' 1024 '*' 1024`" || Qg=1073741824
Qt="`expr 1024 '*' 1024 '*' 1024 '*' 1024`" || Qt=1099511627776
Qp="`expr 1024 '*' 1024 '*' 1024 '*' 1024 '*' 1024`" || Qp=1125899906842624

convertnum() {
    [ "$1" -ge 0 -o "$1" -le 0 ] 2>/dev/null && { echo "$1"; return 1; }

    NUM="${1%[BbKkMmGgTtPp]}"
    NUMW="${NUM%.[0123456789]*}"
    case "$NUM" in
	*.*)	NUMR="${NUM#[-0123456789]*\.}" ;;
	*)	NUMR="" ;;
    esac

    RES=0
    case "$1" in
	*[0123456789Bb])
		echo "$NUMW"
		return 0 ;;
	*[Kk])	Q="$Qk" ;;
	*[Mm])	Q="$Qm" ;;
	*[Gg])	Q="$Qg" ;;
	*[Tt])	Q="$Qt" ;;
	*[Pp])	Q="$Qp" ;;
	*)	echo "$1"
		return 2 ;;
    esac

    B="$(($NUMW*$Q))" || RES=$?
    if [ -n "$NUMR" ]; then
	NUMR="${NUMR:0:1}" || NUMR=0
	B="$(($B+$NUMR*$Q/10))"
    fi

    echo "$B"
    return $RES
}

convertts() {
    [ "$@" -ge 0 -o "$@" -le 0 ] 2>/dev/null && \
	echo "$*" && return
    $GDATE -d "$* UTC" '+%s'
}

##########################################################################

die() {
    [ -z "$CODE" ] && CODE=1
    echo "FATAL($CODE): `date`: $0:" "$@" >&2
    exit $CODE
}

log_message() {
    DEBUG_TAG="$1"
    DEBUG_LEVEL="$2"
    shift 2

    if [ "$DEBUG" -ge "$DEBUG_LEVEL" ]; then
	echo "$DEBUG_TAG: $@"
	return 0
    fi
    return 1
}

log_debug() {
    log_message "DEBUG" "$@" >&2
}

log_info() {
    log_message "INFO" "$@"
}

log_warn() {
    log_message "WARN" "$@" >&2
}

exec_debug() (
    PROCNUM="`ls -la /proc/self | awk '{print $NF}'`" || PROCNUM="$$"
    log_message "TRACE[$PROCNUM]-BEGIN" "$DEBUG_LEVEL_TRACE" "`date`:" "$@" >&2
    if [ "$DEBUG_LEVEL_TRACE" -le "$DEBUG" ]; then
	time "$@"
	RES=$?
    else
	"$@"
	RES=$?
    fi
    if [ $RES = 0 ]; then
	log_message "TRACE[$PROCNUM]-ENDED" "$DEBUG_LEVEL_TRACE" \
	    "`date`:" "completed ($RES)" >&2
    else
	log_message "TRACE[$PROCNUM]-ENDED" "$DEBUG_LEVEL_TRACE" \
	    "`date`:" "failed ($RES)" >&2
    fi
    exit $RES
)

zfs_free_baseds() {
    [ -n "${ZFS_LIST_CMD}" ] && \
	convertnum `${ZFS_LIST_CMD} -o avail "$BASEDS"`
}

#####################################################################
### We can stop some services so as to not interfere with their normal work

svcs_list_active_zfsautosnap() {
    ### Returns to STDOUT the list of zfs-auto-snap services stopped
    ### Newer svcs has better CLI handling, but I'd rather have this
    ### backwards compatible to older OS versions
    (which svcs >/dev/null 2>&1) || return 0
    svcs -a | grep svc:/system/filesystem/zfs/auto-snapshot | \
    egrep '^(offline\*|online)' | awk '{print $3}'
}

svcs_stop_zfsautosnap() {
    ### TODO: Grab info if the service was temp-enabled or full-enabled?
    for S in `svcs_list_active_zfsautosnap` ; do
	log_info 1 "Temp-disabling SMF service: $S"
	svcadm disable -t "$S" && SVCS_STOPPED="$SVCS_STOPPED $S"
    done
    unset S
}

svcs_restart_stopped() {
    ### TODO: Grab info if the service was temp-enabled or full-enabled?
    [ -z "$SVCS_STOPPED" ] && return 0
    _SVCS_STILL_STOPPED=""
    for S in $SVCS_STOPPED ; do
	log_info 1 "Re-enabling SMF service: $S"
	svcadm enable "$S" || _SVCS_STILL_STOPPED="$_SVCS_STILL_STOPPED $S"
    done
    SVCS_STOPPED="$_SVCS_STILL_STOPPED"
    [ -z "$SVCS_STOPPED" ] ### Not empty == problem
}


###########################################################################
###              Some more data-processing for snapshot lists
###########################################################################

convertSnapData_s() {
    ### Parse the tab-separated input that needs complete parsing from strings
    _CRTN_PREV=""
    _CRTN_PREV_TS=""
    while IFS="	" read _CRTN _USED _REFER _NAME ; do
	if [ "$_CRTN_PREV" != "$_CRTN" ]; then
	    _CRTN_TS="`convertts "$_CRTN" 2>/dev/null`"
	    [ $? != 0 ] && _CRTN_TS="$_CRTN"
	fi

	_USEDB="`convertnum "$_USED"`"
	_REFERB="`convertnum "$_REFER"`"

	_DS="${_NAME/@*}"
	case "$_NAME" in
	    *@*)	_SN="${_NAME/*@}" ;;
	    *)		_SN="";;
	esac
	echo "$_CRTN_TS	$_USEDB	$_REFERB	$_DS	$_SN"

	_CRTN_PREV_TS="$_CRTN_TS"
	_CRTN_PREV="$_CRTN"
    done | ggrep -E -v '^[	 ]*$'
    # | sort -t '	' -k 1,5
}

convertSnapData_sq() {
    ### Parse the tab-separated input that needs QUICK parsing from strings
    while IFS="	" read _CRTN _USED _REFER _NAME ; do
	_USEDB="`convertnum "$_USED"`"
	_DS="${_NAME/@*}"
	case "$_NAME" in
	    *@*)	_SN="${_NAME/*@}" ;;
	    *)		_SN="";;
	esac
	echo "$_CRTN	$_USEDB	$_REFER	$_DS	$_SN"
    done | ggrep -E -v '^[	 ]*$'
    # | sort -t '	' -k 1,5
}

convertSnapData_n() {
    ### Ultimate quick parsing (i.e. to pick out only zero-sized snapshots)
    ### which only splits the dataset/snapshot name into two columns
    ### Parse the tab-separated input with already numeric data
    while IFS="	" read _CRTN _USED _REFER _NAME ; do
	_DS="${_NAME/@*}"
	case "$_NAME" in
	    *@*)	_SN="${_NAME/*@}" ;;
	    *)		_SN="";;
	esac
	echo "$_CRTN	$_USED	$_REFER	$_DS	$_SN"
    done | ggrep -E -v '^[	 ]*$'
    # | sort -t '	' -k 1,5
}

convertSnapData_z() {
    ### Similar to convertSnapData_n(), this quickly picks out such snapshot
    ### groups where ALL snapshots with the same timestamp and snapname have
    ### zero size altogether
    _CRTN_PREV=""
    _SNAP_PREV=""
    _SKIP_GROUP=no
    BLOCK=""

    ### Complete the quick preprocessing and proceed to specific logic
    ### Group the outputs by timestamp (in string case, this may be not
    ### date-ordered) then by snapshot name
    convertSnapData_n | sort -t '	' -k 1,5 | { \
    while IFS="	" read _CRTN _USED _REFER _DS _SN ; do
	if [ "$_CRTN_PREV" != "$_CRTN" -o "$_SN" != "$_SNAP_PREV" ]; then
	    # Got new timestamp and/or snapname incoming; gotta print something
	    [ "$_SKIP_GROUP" = no -a -n "$BLOCK" ] && echo "$BLOCK"
	    _SKIP_GROUP=no
	    BLOCK=""
	fi

	[ "$_USED" = 0 ] || _SKIP_GROUP=yes

	if [ "$_SKIP_GROUP" = no ]; then
	    LINE="$_CRTN	$_USED	$_REFER	$_DS	$_SN"
	    [ -z "$BLOCK" ] && BLOCK="$LINE" || \
		BLOCK="$BLOCK
$LINE"
	else BLOCK=""; fi

	_CRTN_PREV="$_CRTN"
	_SNAP_PREV="$_SN"
    done
    [ "$_SKIP_GROUP" = yes -o -z "$BLOCK" ] || echo "$BLOCK"; }
}

convertSnapData() {
    if [ "$ZFS_P_SUPPORT" = 0 ]; then
	exec_debug convertSnapData_n
    else
	exec_debug convertSnapData_sq
    fi
}

fetchTSlist() {
    # This provides a list of timestamps in original order for ALLSNAPS_TSLIST
    awk -F'	' '{print $1}' | uniq
}

normalizeSnaps() {
    [ -n "$ALLSNAPS" ] && \
	{ log_debug 2 "normalizeSnaps() called more than once, skipped";
	return 0; }

    log_info 1 "Normalizing snapshot sizes and timestamps into numbers," \
	"this can take long (got $NUM_SNAPS snapshots)..."
    ALLSNAPS="`echo "$ALLSNAPS_RAW" | convertSnapData`"
    ALLSNAPS_TSLIST="`echo "$ALLSNAPS" | fetchTSlist`"

    log_debug 4 "Found these snapshots (processed numbers):
$ALLSNAPS"

    SUM_USED_SNAPS="`echo "$ALLSNAPS" | awk -F'	' '{ print $2 }' | { S=0; while read N; do S=$(($S+$N)); done; echo "$S"; }`"
    log_info 1 "Total space used by selected $NUM_SNAPS snapshots is" \
	"$SUM_USED_SNAPS bytes" >&2
    [ -n "$ALLSNAPS" -a -n "$ALLSNAPS_TSLIST" ]	### Logical result of routine
}

excludeSnapTS() {
    # Pick ALLSNAPS except those matching $1 as the timestamp
    echo "$ALLSNAPS" | ggrep -E -v "^$1	"
}

selectSnapTS() {
    # Pick ALLSNAPS except those matching $1 as the timestamp
    echo "$ALLSNAPS" | ggrep -E "^$1	"
}

chompSnapsTS() {
    # Retain in our list all snapshots whose timestamp columns do NOT match
    # the chosen oldest or newest snapshots which we desire to retain
    log_debug 2 "Starting chompSnapsTS()..."

    normalizeSnaps || return
    [ -z "$ALLSNAPS_TSLIST" -o -z "$ALLSNAPS" ] && {
	log_warn 1 "ALLSNAPS_TSLIST or ALLSNAPS variable are empty"
	return 0; }

    [ "$PRESERVE_OLDEST" -gt 0 -a "$PRESERVE_NEWEST" -gt 0 ] && \
	return 0

    TS_SNAPPAT=""
    OIFS="$IFS"
    IFS='
'
    export IFS
    for S in \
	`[ "$PRESERVE_OLDEST" -gt 0 ] && { echo "$ALLSNAPS_TSLIST" | head -"$PRESERVE_OLDEST"; }` \
	`[ "$PRESERVE_NEWEST" -gt 0 ] && { echo "$ALLSNAPS_TSLIST" | tail -"$PRESERVE_NEWEST"; }` \
    ; do
	[ -z "$TS_SNAPPAT" ] && TS_SNAPPAT='(' || TS_SNAPPAT="$TS_SNAPPAT|"
	TS_SNAPPAT="$TS_SNAPPAT$S"
    done
    IFS="$OIFS"
    export IFS
    unset OIFS

    [ -z "$TS_SNAPPAT" ] && \
	{ log_warn 2 "chompSnapsTS(): Got no pattern to chomp away timestamps";
	return 0; }

    TS_SNAPPAT="$TS_SNAPPAT)"

    log_info 2 "Now chomping away" \
	"$PRESERVE_OLDEST oldest and/or $PRESERVE_NEWEST newest timestamps" \
	"with regex '$TS_SNAPPAT' ..."

    if [ "$DEBUG" -ge 10 ]; then
	log_debug 10 "chompSnapsTS(): ALLSNAPS_TSLIST will lose these lines:" && \
	    { echo "$ALLSNAPS_TSLIST" | ggrep -E '^'"$TS_SNAPPAT"'$'; }
	log_debug 10 "chompSnapsTS(): ALLSNAPS will lose these lines:" && \
	    { echo "$ALLSNAPS" | ggrep -E '^'"$TS_SNAPPAT"'	'; }
    fi

    ALLSNAPS_TSLIST="`echo "$ALLSNAPS_TSLIST" | ggrep -E -v '^'"$TS_SNAPPAT"'$'`" || \
	{ log_warn 2 "chompSnapsTS(): ALLSNAPS_TSLIST selection returned empty"; return 1; }
    ALLSNAPS="`echo "$ALLSNAPS" | ggrep -E -v '^'"$TS_SNAPPAT"'	'`" || \
	{ log_warn 2 "chompSnapsTS(): ALLSNAPS selection returned empty"; return 1; }

    log_info 1 "Chomp was successful; now" \
	"`echo "$ALLSNAPS_TSLIST" | egrep -v '^$' | wc -l | sed 's, ,,g'` timestamps" \
	"(`echo "$ALLSNAPS" | egrep -v '^$' | wc -l | sed 's, ,,g'` snapshots)" \
	"remain in the list to consider"
    return 0
}

reduceRAW() {
    # Prints those snapshots of the ALLSNAPS_RAW list which do NOT match input
    log_info 2 "reduceRAW(): `date`: Reducing original snapshot list to" \
	"remove just-killed ones" >&2

    while IFS='	' read X_CRTN X_U X_R X_DS X_SN; do
	log_debug 3 "=== $X_DS@$X_SN" >&2
	[ -n "$X_DS" -a -n "$X_SN" ] && echo "	$X_DS@$X_SN\$" || \
	    log_debug 3 "===== $X_DS@$X_SN: ignored" >&2
    done > /tmp/.snapraw.$$.tmp
    RES=$?

    log_info 2 "reduceRAW(): `date`: Prepared" \
	"`wc -l /tmp/.snapraw.$$.tmp | awk '{print $1}'`" \
	"patterns for exclusion; RES=$RES" >&2

    if [ $RES = 0 ]; then
	echo "$ALLSNAPS_RAW" | ggrep -E -v -f /tmp/.snapraw.$$.tmp
	RES=$?
	if [ $RES != 0 ]; then
	    N1="`echo "$ALLSNAPS_RAW" | egrep -v '^$' | wc -l | sed 's, ,,g'`"
	    N2="`cat /tmp/.snapraw.$$.tmp | wc -l | sed 's, ,,g'`"
	    [ "$N1" = "$N2" ] && RES=0	# Assume a clean cut-off
	fi
	log_info 2 "reduceRAW(): finished removals; RES=$RES" >&2
    fi

    if [ $RES != 0 ]; then
	log_warn 0 "reduceRAW(): something failed; RES=$RES" >&2
    fi

#    echo "$ALLSNAPS_RAW" > /tmp/.snapraw.$$.raw
    rm -f /tmp/.snapraw.$$.tmp

    return $RES
}

zclean_do() {
    # Actual wiping of the input list of snapshots, grouped by snapname.
    # Prints the list of actual dataset metadata requested for destruction
    # so this can be fed into reduceRAW() later on.
    # May abort early if reaches the requested free space threshold.
    NUM_MAX=$MAX_PARALLEL_JOBS
    NUM_CUR=0
    NUM_TOTAL=0
    SNAP_TOTAL=0
    RES=0
    [ x"$READONLY" = xyes ] && ZECHO="/bin/echo :;" || ZECHO=""
    _SN_PREV=""
    PIDLIST=""

    ESTIMATED_FREE="`zfs_free_baseds`"

    log_debug 2 "Starting zclean_do() ; ZECHO='$ZECHO'..."
    log_info 1 "Desired available space in '$BASEDS' : $NEEDED_FREE_SPACE bytes"

    trap "echo 'Got an exit signal...' >&2 ; svcs_restart_stopped; exit" EXIT SIGHUP SIGINT SIGQUIT SIGTERM
    svcs_stop_zfsautosnap

    while IFS='	' read _CRTN _USED _REFER _DS _SN; do
	if [ -n "$_DS" -a -n "$_SN" ]; then
	    $ZECHO zfs destroy "$_DS@$_SN" >&2 &
	    PIDLIST="$PIDLIST $!"
	    [ -z "$ZECHO" ] && log_debug 5 \
		"  :; zfs destroy '$_DS@$_SN' &" >&2
	    NUM_CUR=$(($NUM_CUR+1))
	    NUM_TOTAL=$(($NUM_TOTAL+1))
	    # Even a zero-sized snapshot occupies some space in pool metadata
	    # But note this assumes success of the destroy, hence it may err
	    ESTIMATED_FREE=$(($ESTIMATED_FREE+$_USED+16384))
	    [ x"$_SN" != x"$_SN_PREV" ] && \
		SNAP_TOTAL=$(($SNAP_TOTAL+1))
	
	    # This is THE stdout result of the function
	    echo "$_CRTN	$_USED	$_REFER	$_DS	$_SN"
	fi

	if [ x"$_SN" != x"$_SN_PREV" ]; then
	    log_info 2 "Estimat available space in '$BASEDS' : $ESTIMATED_FREE bytes"

	    if [ "$NUM_CUR" -ge "$NUM_MAX" ]; then
		log_info 1 "`date`:" \
		    "Launched $NUM_CUR subprocesses;" \
		    "waiting for them to complete..."
		[ -n "$ZECHO" ] && \
		    $ZECHO "sync; wait; wait" || \
		    log_debug 5 "  :; sync; wait; wait"
		sync
		RESX=0
		wait $PIDLIST >/dev/null 2>&1 || RESX=$?
		wait >/dev/null 2>&1 || RESX=$?
		[ $RESX != 127 -a $RES = 0 ] && RES=$RESX
		NUM_CUR=0
		PIDLIST=""
	    fi

	    if [ "$ESTIMATED_FREE" -ge "$NEEDED_FREE_SPACE" ]; then
		log_info 1 \
		    "Estimated free space $ESTIMATED_FREE in $BASEDS" \
		    "exceeds desired requirements $NEEDED_FREE_SPACE;" \
		    "sleeping a bit for the pool metadata to catch up..."
		sleep 15
	    fi

	    # Note this can come with a several-second lag
	    CURRENT_FREE="`zfs_free_baseds`"
	    log_info 1 "Current available space in '$BASEDS' : $CURRENT_FREE bytes"

	    if [ "$NEEDED_FREE_SPACE" -le "$CURRENT_FREE" ]; then
	        log_info 0 "Current available space in '$BASEDS'" \
	    	    "$CURRENT_FREE bytes is greater than desired" \
	    	    "$NEEDED_FREE_SPACE bytes (NEEDED_FREE_SPACE):" \
		    "Nothing more to do!"
	        break
	    fi

	    if [ "$ESTIMATED_FREE" -ge "$NEEDED_FREE_SPACE" -o \
		 "$ESTIMATED_FREE" -lt "$CURRENT_FREE" ]; then
		log_debug 2 \
		    "Bumping the possibly obsolete estimation of free space"
		ESTIMATED_FREE="`zfs_free_baseds`"
	    fi
	fi >&2

	[ -n "$_DS" -a -n "$_SN" ] && \
	    _SN_PREV="$_SN"
    done

    [ "$NUM_CUR" -gt 0 ] && \
	log_info 1 "`date`: loop is over;" \
	    "waiting for the last $NUM_CUR jobs of ZFS destruction..." >&2
    sync >&2
    RESX=0
    wait $PIDLIST >/dev/null 2>&1 || RESX=$?
    wait >/dev/null 2>&1 || RESX=$?
    [ $RESX != 127 -a $RES = 0 ] && RES=$RESX

    if [ $RES = 0 ]; then
	log_debug 2 "Successfully completed zclean_do()..."
    else
	log_warn 0 "Something failed($RES) during zclean_do()..."
    fi

    log_info 1 "`date`:" \
	"Overall launched $NUM_TOTAL subprocesses to destroy" \
	"snapshots across $SNAP_TOTAL snapnames, worst result=$RES" >&2
    CURRENT_FREE="`zfs_free_baseds`"
    log_info 1 "Desired available space in '$BASEDS' : $NEEDED_FREE_SPACE bytes" >&2
    log_info 1 "Current available space in '$BASEDS' : $CURRENT_FREE bytes" \
	"(however do note that ZFS metadata update that we can perceive may" \
	"lag behind 'the reality' for quite a while and so we could clean up" \
	"too much)" >&2

    svcs_restart_stopped
    trap "" EXIT SIGHUP SIGINT SIGQUIT SIGTERM

    return $RES
}

zclean_oldbig() {
    # This is the longer routine which orders and cleans up the oldest
    # snapshots considering their reported "used" size. So before all
    # those expensive string-number conversions, we cheaply stripped
    # the tagged-as-failed and zero-sized snapshots.
    log_debug 2 "Starting zclean_oldbig()..."

    NUM_SNAPS="`echo "$ALLSNAPS_RAW" | egrep -v '^$' | wc -l | sed 's, ,,g'`"
#    ALLSNAPS=""		### We have remaining ALLSNAPS_RAW to reprocess
#    normalizeSnaps
#    [ $? != 0 ] && { log_warn 0 "No old-big snaps found"; return 1; }

    log_info 1 "Normalizing snapshot list to pick out old-big snapshots," \
	"this can take long (got $NUM_SNAPS snapshots)..."
    ALLSNAPS="`echo "$ALLSNAPS_RAW" | exec_debug convertSnapData_sq`"
    [ $? != 0 -o -z "$ALLSNAPS" ] && \
	{ log_warn 0 "No old-big snaps found"; return 1; }
    ALLSNAPS_TSLIST="`echo "$ALLSNAPS" | fetchTSlist`"
    [ $? != 0 -o -z "$ALLSNAPS_TSLIST" ] && \
	{ log_warn 0 "No old-big snaps found"; return 1; }

    chompSnapsTS
    [ $? != 0 -o -z "$ALLSNAPS" -o -z "$ALLSNAPS_TSLIST" ] && {
	log_warn 0 "No old-big snapshots left to consider after chomping away" \
	    "$PRESERVE_OLDEST oldest and/or $PRESERVE_NEWEST newest timestamps"
	return 1; }

    NUM_SNAPS_O="`echo "$ALLSNAPS" | egrep -v '^$' | wc -l | sed 's, ,,g'`"
    SUM_USED_SNAPS="`echo "$ALLSNAPS" | awk -F'	' '{ print $2 }' | { S=0; while read N; do S=$(($S+$N)); done; echo "$S"; }`"
    log_info 1 "Total space used by selected old-big $NUM_SNAPS_O snapshots" \
	"(out of original $NUM_SNAPS) snapshots" \
	"across `echo "$ALLSNAPS_TSLIST" | egrep -v '^$' | wc -l | sed 's, ,,g'` timestamps" \
	"is $SUM_USED_SNAPS bytes" >&2
    NUM_SNAPS="$NUM_SNAPS_O"

    # Now we have several normalized columns of snapshots...
    # Iterate over the oldest ones with nonzero "used"
    #   (in this case killing all same-named same-timestamp ones)
    # until enough free space is made

    ALLSNAPS_DESTROYED="`echo "$ALLSNAPS" | exec_debug zclean_do`"
    [ $? != 0 ] && { \
	log_warn 0 "ZFS cleanup of old-big snapshots failed?"
	return 1; }

    ALLSNAPS_RAW="`echo "$ALLSNAPS_DESTROYED" | exec_debug reduceRAW`"
    [ $? != 0 -o -z "$ALLSNAPS_RAW" ] && { \
	log_warn 0 "ZFS cleanup of old-big snapshots wiped everything"
	return 1; }

    log_debug 2 "Successfully completed zclean_oldbig()..."
    return 0
}

zclean_zerosize() {
    # Kill all zero-sized snaps (where ALL snaps for a timestamp+name = 0)
    log_debug 2 "Starting zclean_zerosize()..."

    NUM_SNAPS="`echo "$ALLSNAPS_RAW" | egrep -v '^$' | wc -l | sed 's, ,,g'`"
    # This pass quickly normalizes the found data (no string conversion)
    log_info 1 "Normalizing snapshot list to pick out zero-sized groups," \
	"this can take long (got $NUM_SNAPS snapshots)..."
    ALLSNAPS_Z="`echo "$ALLSNAPS_RAW" | exec_debug convertSnapData_z`"
    [ $? != 0 -o -z "$ALLSNAPS_Z" ] && \
	{ log_warn 0 "No zero-sized snaps found"; return 1; }
    ALLSNAPS_TSLIST="`echo "$ALLSNAPS_Z" | fetchTSlist`"
    [ $? != 0 -o -z "$ALLSNAPS_TSLIST" ] && \
	{ log_warn 0 "No zero-sized snaps found"; return 1; }

    # Technically, errors due to NaN are possible if non-zeros sneak in
    SUM_USED_SNAPS_Z="`echo "$ALLSNAPS_Z" | awk -F'	' '{ print $2 }' | { S=0; while read N; do S=$(($S+$N)); done; echo "$S"; }`"
    NUM_SNAPS_Z="`echo "$ALLSNAPS_Z" | egrep -v '^$' | wc -l | sed 's, ,,g'`"
    log_info 1 "Total space used by selected zero-sized $NUM_SNAPS_Z" \
	"(out of original $NUM_SNAPS) snapshots" \
	"across `echo "$ALLSNAPS_TSLIST" | egrep -v '^$' | wc -l | sed 's, ,,g'` timestamps" \
	"is $SUM_USED_SNAPS_Z bytes" >&2
    [ -n "$ALLSNAPS_Z" -a -n "$ALLSNAPS_TSLIST" \
      -a "$SUM_USED_SNAPS_Z" = 0 ] || return

    ALLSNAPS="$ALLSNAPS_Z"
    NUM_SNAPS="$NUM_SNAPS_Z"
    SUM_USED_SNAPS="$SUM_USED_SNAPS_Z"
    chompSnapsTS
    [ $? != 0 -o -z "$ALLSNAPS" -o -z "$ALLSNAPS_TSLIST" ] && {
	log_warn 0 "No zero-sized snapshots left to consider after chomping away" \
	    "$PRESERVE_OLDEST oldest and/or $PRESERVE_NEWEST newest timestamps"
	return 1; }
    ALLSNAPS_Z="$ALLSNAPS"

    ALLSNAPS_DESTROYED="`echo "$ALLSNAPS_Z" | exec_debug zclean_do`"
    [ $? != 0 ] && { \
	log_warn 0 "ZFS cleanup of zero-sized snapshots failed?"
	return 1; }

    ALLSNAPS_RAW="`echo "$ALLSNAPS_DESTROYED" | exec_debug reduceRAW`"
    [ $? != 0 -o -z "$ALLSNAPS_RAW" ] && { \
	log_warn 0 "ZFS cleanup of zero-sized snapshots wiped everything"
	return 1; }

    log_debug 2 "Successfully completed zclean_zerosize()..."
    return 0
}

zclean_badsnaps() {
    # According to a defined pattern of primary snapshots to kill, wipe them
    log_debug 2 "Starting zclean_badsnaps()..."

    [ -z "$RE_KILLFIRST" ] && { \
	log_warn 0 "zclean_badsnaps(): RE_KILLFIRST is empty"
	return 1; }

    NUM_SNAPS="`echo "$ALLSNAPS_RAW" | egrep -v '^$' | wc -l | sed 's, ,,g'`"
    # This pass quickly normalizes the found data (no string conversion)
    log_info 1 "Normalizing snapshot list to pick after-failure snapshots" \
	"by regex '@$RE_KILLFIRST';" \
	"this can take long (got $NUM_SNAPS snapshots)..."
    ALLSNAPS_B="`echo "$ALLSNAPS_RAW" | ggrep -E "@$RE_KILLFIRST" | convertSnapData`"
    [ $? != 0 -o -z "$ALLSNAPS_B" ] && \
	{ log_warn 0 "No after-failure snaps found"; return 1; }
    ALLSNAPS_TSLIST="`echo "$ALLSNAPS_B" | fetchTSlist`"
    [ $? != 0 -o -z "$ALLSNAPS_TSLIST" ] && \
	{ log_warn 0 "No after-failure snaps found"; return 1; }

    SUM_USED_SNAPS_B="`echo "$ALLSNAPS_B" | awk -F'	' '{ print $2 }' | { S=0; while read N; do S=$(($S+$N)); done; echo "$S"; }`"
    NUM_SNAPS_B="`echo "$ALLSNAPS_B" | egrep -v '^$' | wc -l | sed 's, ,,g'`"
    log_info 1 "Total space used by selected after-failure $NUM_SNAPS_B" \
	"(out of original $NUM_SNAPS) snapshots" \
	"across `echo "$ALLSNAPS_TSLIST" | egrep -v '^$' | wc -l | sed 's, ,,g'` timestamps" \
	"is $SUM_USED_SNAPS_B bytes" >&2
    [ -n "$ALLSNAPS_B" -a -n "$ALLSNAPS_TSLIST" ] || return

    ALLSNAPS="$ALLSNAPS_B"
    NUM_SNAPS="$NUM_SNAPS_B"
    SUM_USED_SNAPS="$SUM_USED_SNAPS_B"
    chompSnapsTS
    [ $? != 0 -o -z "$ALLSNAPS" -o -z "$ALLSNAPS_TSLIST" ] && {
	log_warn 0 "No after-failure snapshots left to consider after chomping away" \
	    "$PRESERVE_OLDEST oldest and/or $PRESERVE_NEWEST newest timestamps"
	return 1; }
    ALLSNAPS_B="$ALLSNAPS"

    ALLSNAPS_DESTROYED="`echo "$ALLSNAPS_B" | exec_debug zclean_do`"
    [ $? != 0 ] && { \
	log_warn 0 "ZFS cleanup of after-failure snapshots failed?"
	return 1; }

    ALLSNAPS_RAW="`echo "$ALLSNAPS_DESTROYED" | exec_debug reduceRAW`"
    [ $? != 0 -o -z "$ALLSNAPS_RAW" ] && { \
	log_warn 0 "ZFS cleanup of after-failure snapshots wiped everything"
	return 1; }

    log_debug 2 "Successfully completed zclean_badsnaps()..."
    return 0
}


#####################################################################


case "$DEBUG" in
    [Yy]|[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee])
    	DEBUG=1	;;
    [Nn]|[Nn][Oo]|[Ff][Aa][Ll][Ss][Ee])
	DEBUG=0 ;;
    [0-9]*)	;;
    *)	# What was that?
	BAD_DEBUG="$DEBUG"
    	DEBUG=0
	log_warn 0 "Unknown DEBUG='$BAD_DEBUG' value requested;" \
	    "disabling optional verbosity (effectively setting DEBUG='$DEBUG')"
    ;;
esac

for F in \
    /{usr,opt}/{local,sfw,gnu,omni,COSac}/bin/{g,}date \
    /usr/bin/{g,}date \
; do
    [ -z "$GDATE" -o ! -x "$GDATE" ] && [ -n "$F" -a -x "$F" ] && \
        [ $("$F" '+%s' -d 'Mon Dec  8 9:47 2014 UTC') = 1418032020 ] \
            && GDATE="$F" && break
done 2>/dev/null
[ -z "$GDATE" -o ! -x "$GDATE" ] && \
    { log_warn 0 "GNU date or equivalent not found!"; GDATE=false; }
log_info 2 "Using '$GDATE' as GNU date or equivalent"

[ "$NEEDED_FREE_SPACE" != "" ] && \
    NEEDED_FREE_SPACE="`convertnum "$NEEDED_FREE_SPACE"`" || \
    NEEDED_FREE_SPACE="`convertnum 1g`"
[ "$NEEDED_FREE_SPACE" -gt 131072 ] 2>/dev/null || \
    NEEDED_FREE_SPACE="`expr 1024 '*' 1024 '*' 1024`"

ZFS_LIST_CMD="zfs list"

log_info 1 "Checking BASEDS validity and basic ZFS functionality..."
OUT="`${ZFS_LIST_CMD} "$BASEDS"`" || die "Bad BASEDS='$BASEDS'"
log_info 2 "Got BASEDS details:" "\n" "$OUT"

ZFS_CREATION_SAMPLE="`${ZFS_LIST_CMD} -H -o creation "$BASEDS"`" || \
	die "Can't get 'creation' attribute"
ZFS_LIST_CMD="${ZFS_LIST_CMD} -H"

OUT="`${ZFS_LIST_CMD} -o creation -p "$BASEDS" 2>/dev/null`"
ZFS_P_SUPPORT=$?
[ x"$DEBUG_TEST__NO__ZFS_P_SUPPORT" = xyes ] && ZFS_P_SUPPORT=1
[ "$ZFS_P_SUPPORT" = 0 ] && \
	ZFS_LIST_CMD="${ZFS_LIST_CMD} -p" && \
	ZFS_CREATION_SAMPLE="$OUT"
log_debug 3 "ZFS_P_SUPPORT='$ZFS_P_SUPPORT'"

ZFS_CREATION_FORMAT="unknown"
case "$ZFS_CREATION_SAMPLE" in
    [0-9]*)	# Unix epoch seconds like '1418200686'
	log_info 2 "Creation timestamp reported as a number of seconds" \
	    "since the Unix epoch: '$ZFS_CREATION_SAMPLE'"
	ZFS_CREATION_FORMAT="epoch"
	;;
    *[0-9]:[0-9]*\ [0-9]*)
	# Timestamp string like 'Fri May  3  3:59 2013'
	log_info 2 "Creation timestamp reported as a date string:" \
	    "'$ZFS_CREATION_SAMPLE' (conversion: " \
	    "'`convertts "$ZFS_CREATION_SAMPLE"`')"
	ZFS_CREATION_FORMAT="date"
	;;
    *)
	log_warn 1 "Creation timestamp reported in unknown format:" \
	    "'$ZFS_CREATION_SAMPLE'"
	;;
esac

log_info 2 "PID-of-script=$$"

INITIAL_FREE="`zfs_free_baseds`"
log_info 1 "Initial available space in '$BASEDS' : $INITIAL_FREE bytes"
log_info 1 "Desired available space in '$BASEDS' : $NEEDED_FREE_SPACE bytes"

if [ "$NEEDED_FREE_SPACE" -le "$INITIAL_FREE" ]; then
    log_info 0 "Initial available space in '$BASEDS' $INITIAL_FREE bytes" \
	"is greater than desired $NEEDED_FREE_SPACE bytes" \
	"(NEEDED_FREE_SPACE): Nothing to do!"
    exit 0
fi

log_info 1 "Picking out snapshots, this can take long..."
log_info 3 "Picking out snapshot names by regexp" \
    "RE_INTERESTING='${RE_INTERESTING}'"

### Simplify debugging to just one dataset:
[ x"$DEBUG_TEST__NO__ZFS_DEPTH" = xyes ] && \
    ZFS_LIST_CMD="${ZFS_LIST_CMD} -d1"

ALLSNAPS_RAW=$(${ZFS_LIST_CMD} -s creation -S used \
	-o creation,used,refer,name \
	-t snapshot -r "$BASEDS" | \
exec_debug ggrep -E "@$RE_INTERESTING"
)
ALLSNAPS=""
ALLSNAPS_TSLIST=""
SUM_USED_SNAPS=""

NUM_SNAPS="`echo "$ALLSNAPS_RAW" | egrep -v '^$' | wc -l | sed 's, ,,g'`"

log_debug 5 "Found $NUM_SNAPS snapshots (raw numbers):
$ALLSNAPS_RAW"


log_info 1 "Starting the cleanup with" \
    "`echo "$ALLSNAPS_RAW" | sed 's,^.*@,,' | uniq | egrep -v '^$' | wc -l | sed 's, ,,g'` timestamps" \
    "(`echo "$ALLSNAPS_RAW" | egrep -v '^$' | wc -l | sed 's, ,,g'` snapshots)" \
    "in the list to consider"


echo "" && zclean_badsnaps
echo "" && zclean_zerosize
echo "" && zclean_oldbig

RESULT=$?

log_info 1 "Finished the cleanup with" \
    "`echo "$ALLSNAPS_RAW" | sed 's,^.*@,,' | uniq | egrep -v '^$' | wc -l | sed 's, ,,g'` timestamps" \
    "(`echo "$ALLSNAPS_RAW" | egrep -v '^$' | wc -l | sed 's, ,,g'` snapshots)" \
    "remaining in the list"

# Be nice, clean up
[ $CHECKONLY = 0 ] && rm -f "$LOCK"

exit $RESULT
