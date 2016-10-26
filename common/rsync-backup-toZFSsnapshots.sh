#!/bin/bash

# Copy backup of the system to "backup" machine with ZFS snapshots.
# SSH keys for remote login are preset (run ssh-keygen as root,
# and add the contents of source:/root/.ssh/id_rsa.pub
# to backup:/root/.ssh/authorized_keys)
# $Id: rsync-backup-toZFSsnapshots.sh,v 1.10 2015/04/02 17:57:57 jim Exp $
# (C) 2014 by Jim Klimov
# Crontab usage examples:
### Quick rsync of Jenkins dirs for example:
# 30 * * * * [ -x /opt/COSas/bin/rsync-backup-toZFSsnapshots.sh ] && SRCDIRS="/{usr,var}/lib/jenkins* /etc" /opt/COSas/bin/rsync-backup-toZFSsnapshots.sh >/dev/null
### Occasional full rsync of the VM:
# 45 0 * * * [ -x /opt/COSas/bin/rsync-backup-toZFSsnapshots.sh ] && /opt/COSas/bin/rsync-backup-toZFSsnapshots.sh >/dev/null

[ -z "$DESTSRV" ] && DESTSRV="backup"
[ -z "$DESTDIR" ] && DESTDIR="/export/DUMP/manual/`hostname`/fullroot"
[ -z "$DESTUSER" ] && DESTUSER="root"
[ -z "$RSYNC_OPTS" ] && RSYNC_OPTS="-avPHK --delete-after"

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

### Absolute directories, mapped 1:1 to target storage relative to $DESTDIR
if [ -z "$SRCDIRS" ] ; then
    case "`uname -s`" in
	Linux)
	    SRCDIRS="`/bin/mount | egrep 'type (ext|xfs|reiser|zfs|ufs)' | awk '{print $3}'`" \
		|| SRCDIRS=""
	    ;;
	SunOS|*illumos*)
	    SRCDIRS="`( /bin/df -kFzfs; /bin/df -kFufs; /bin/df -kFvxfs; ) 2>/dev/null | awk '{print $NF}' | grep / | sort`" \
		|| SRCDIRS=""
	    ;;
    esac
    [ -z "$RSYNC_OPTS_ADD" ] && RSYNC_OPTS_ADD="-x"
fi

### This order of quoting should strip newlines into spaces
[ -n "$SRCDIRS" ] && \
	SRCDIRS="`echo $SRCDIRS`" || \
	SRCDIRS="/"

if [ $# != 0 ]; then
	echo "Replicates files via rsync to remote storage and makes ZFS snapshots there"
	echo "See code for variables used from environment or config files."
	exit 1
fi

LOCK="/tmp/`basename $0`__`echo "$SRCDIRS" | sed 's,[/\{\} \,\?\*],_,g'`__${DESTSRV}__`echo "$DESTDIR" | sed 's,/,_,g'`"
LOCK="`echo $LOCK | cut -b 1-100,190-210,320-340`".lock
if [ -f "$LOCK" ] ; then
	echo "ERROR: LOCK file exists '$LOCK'" >&2
	exit 1
fi
trap "rm -f $LOCK" 0 1 2 3 15
echo $$ > "$LOCK" || echo "ERROR: Could not create LOCK file!" >&2


die() {
	[ -z "$CODE" ] && CODE=1
	echo "FATAL: $@" >&2
	exit $CODE
}

echo "=== `date`: Starting backup session of '$SRCDIRS' from '`hostname`' to '$DESTUSER@$DESTSRV:$DESTDIR'"

# Validate that the remote machine is accessible and set a checkpoint
echo "INFO: Testing accessibility of remote storage '$DESTSRV'..."
DS="`ssh -l "$DESTUSER" "$DESTSRV" "cd '$DESTDIR' && { df -k . | grep / | tail -1 | awk '{print "'$1'"}'; }"`" || DS=""
[ x"$DS" = x ] && \
	CODE=1 die "Can't get device/dataset name on remote storage"

TS="`date -u +%Y%m%dZ%H%M%S`" || \
	CODE=9 die "Can't generate timestamp"
SS="rsync-beforeBackup-$TS"
echo "INFO: Creating snapshot on remote storage '$DESTSRV': '$DS@$SS'..."
ssh -l "$DESTUSER" "$DESTSRV" "zfs snapshot -r '$DS@$SS'" || \
	CODE=2 die "Can't make remote snapshot '$DS@$SS'"

RES_RSYNC=0
for SRCDIR in `eval ls -1d $SRCDIRS` ; do
	echo "INFO: starting backup of '$SRCDIR' from '`hostname`' to '$DESTUSER@$DESTSRV:$DESTDIR/$SRCDIR/' with 'rsync $RSYNC_OPTS $RSYNC_OPTS_ADD'..."
	time rsync $RSYNC_OPTS $RSYNC_OPTS_ADD \
		--exclude=/{sys,system,dev,devices,proc,run,var/run,tmp,net,misc,mnt,media}/ \
		"$SRCDIR/" "$DESTUSER@$DESTSRV:$DESTDIR/$SRCDIR/" || \
	RES_RSYNC=$?
done 2>&1
[ "$RES_RSYNC" != 0 ] && echo "WARNING: rsync phase(s) had failure(s): code $RES_RSYNC was reported" >&2

TS="`date -u +%Y%m%dZ%H%M%S`" || \
	CODE=9 die "Can't generate timestamp"
SS="rsync-afterBackup-$TS"
[ "$RES_RSYNC" = 0 ] && \
	SS="$SS-completed" || \
	SS="$SS-failed-$RES_RSYNC"

echo "INFO: Creating snapshot on remote storage '$DESTSRV': '$DS@$SS'..."
ssh -l "$DESTUSER" "$DESTSRV" "zfs snapshot -r '$DS@$SS'" || \
	CODE=2 die "Can't make remote snapshot '$DS@$SS'"

echo "=== `date`: backup session of '$SRCDIRS' from '`hostname`' to '$DESTUSER@$DESTSRV:$DESTDIR/' completed OK"
exit 0
