#!/usr/bin/bash

### post-xfer ZFS snapshot of rsync'ed module directory
### presumes that executing uid has required rights (is root or delegated)
### RSYNC_ variables are set by the calling RSyncD in daemon mode
### $Id: $
### (C) Jan 2009 by Jim Klimov, COS&HT


PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:$PATH
export PATH

VERBOSE=0
DOSNAPSHOT=0
DOSNAPSHOT_ONLYOK=0
WRITELOG=0
SETDEBUG=0

while [ $# -gt 0 ]; do
    case "$1" in
	-v)	VERBOSE=$(($VERBOSE+1)) ;;
	-l)	WRITELOG=1 ;;
	-x)	SETDEBUG=1; WRITELOG=1 ;;
	-w)	DOSNAPSHOT=1 ;;
	-ok)	DOSNAPSHOT_ONLYOK=1;;
	-h)	echo "$0 help:"'
    This script takes an automatic ZFS snapshot of the Module Path upon 
    completion of an incoming RSyncD transmission. The RSyncD provides 
    required variables; you can set debugging verbosity and enable actual
    snapshots:
    -v [-v ...]	Raise verbosity level
    -l		Redirect output to private logfile (/tmp/rsync-zfshot.log*)
    -x		Enable debugging output (set -x > logfile)
    -w		Enable writing (call to zfs snapshot)
    -ok		Only do the snapshot if RSYNC_EXIT_STATUS==0 (and -w is set)
'; exit 0 ;;
    esac
    shift
done

LOGFILE=/tmp/rsync-zfshot.log.$$
if [ "$WRITELOG" = 1 ]; then
    touch "$LOGFILE" && chmod 600 "$LOGFILE"
    exec > "$LOGFILE" 2>&1
fi

if [ "$SETDEBUG" = 1 ]; then
    set -x
fi

if [ "$VERBOSE" -ge 1 ]; then
    echo "$0[$$]: `date`: VERBOSITY level is $VERBOSE" >&2
    set >> "$LOGFILE"
fi

if [ -z "$RSYNC_MODULE_PATH" -o -z "$RSYNC_EXIT_STATUS" ]; then
    ### Directory or status not defined - boogie calls
    [ "$VERBOSE" -ge 1 ] && echo "$0[$$]: `date`: RSYNC_ directory or status not defined" >&2
    exit 1
fi

ZFSBIN="`which zfs`"
if [ $? != 0 -o ! -x "$ZFSBIN" ]; then
    ### ZFS binary not found; is this Solaris (Linux FUSE, MacOS, FreeBSD?)
    [ "$VERBOSE" -ge 1 ] && echo "$0[$$]: `date`: ZFS binary not found" >&2
    exit 1
fi

### TODO: Unroll directory-symlinks as in Tomcat scripts

if [ -d "$RSYNC_MODULE_PATH" ]; then
    if zfs list "$RSYNC_MODULE_PATH" >/dev/null 2>&1; then
	### This path is a zfs filesystem
	ZFSPATH=$(zfs list -H "$RSYNC_MODULE_PATH" | awk -F"`echo -e "\t"`" '{ print $1 }')
	TS="`TZ=UTC date "+%Y%m%dUTC%H%M%S"`__rsync"

	[ -n "$RSYNC_HOST_ADDR" ] && TS="${TS}__${RSYNC_HOST_ADDR}"

	if [ "$RSYNC_EXIT_STATUS" != "0" ]; then
	    RSYNC_EXIT_STATUS=${RSYNC_EXIT_STATUS:--1}

	    if [ "$VERBOSE" -ge 2 ]; then
	        echo "$0[$$]: `date`: TS=$TS; RSYNC_MODULE_PATH=$RSYNC_MODULE_PATH; RSYNC_EXIT_STATUS=${RSYNC_EXIT_STATUS}" | wall
		### Abort on this?
	    fi
	fi
	[ "$VERBOSE" -ge 1 ] && echo "$0[$$]: `date`: TS=$TS; RSYNC_MODULE_PATH=$RSYNC_MODULE_PATH; RSYNC_EXIT_STATUS=${RSYNC_EXIT_STATUS}" >&2

	TS="${TS}__res${RSYNC_EXIT_STATUS}"

	[ "$VERBOSE" -ge 1 ] && echo "$0[$$]: `date`: zfs snapshot '$ZFSPATH'@'$TS'"

	if [ "$DOSNAPSHOT" = "1" ]; then
	    if [ "$DOSNAPSHOT_ONLYOK" = 1 -a "$RSYNC_EXIT_STATUS" != "0" ]; then
		[ "$VERBOSE" -ge 1 ] && echo "$0[$$]: `date`: RSYNC_EXIT_STATUS != 0 and ONLYOK is set; aborting" >&2
		exit $RSYNC_EXIT_STATUS
	    fi

	    zfs snapshot "$ZFSPATH@$TS"
	fi
    else
	### Not a ZFS filesystem
	exit 2
    fi
else
    ### Not a directory
    exit 1
fi

exit $RSYNC_EXIT_STATUS
