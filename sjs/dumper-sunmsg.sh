#!/bin/sh

# dumper-sunmsg.sh
# (C) Nov 2007-Dec 2008 by Jim Klimov, COS&HT
# $Id: dumper-sunmsg.sh,v 1.23 2011/09/13 21:26:08 jim Exp $
# Creates a dump of Sun Messaging Server (mail from JCS5) data
# Default Sun ICS dump method is to create an ".arch" file, maybe big (>2G)
# this script compresses the archive and can copy it to (remote) DUMPDIR

# For use from cron
# 10 * * * * [ -x /opt/COSas/bin/dumper-sunmsg.sh ] && /opt/COSas/bin/dumper-sunmsg.sh

# Restore (maybe several archives over each other) with commands like:
#   bzcat /DUMP/backups/msgstore/msgstore-backup-20071205T001002.arch.bz2 | /opt/SUNWmsgsr/sbin/imsrestore -f -
# Use last archive-file(s) before the crash(es)
# Check atabase validity with:
#   /opt/SUNWmsgsr/sbin/reconstruct -m
# See: "Sun Java System Messaging Server Administration Guide, Backing Up and Restoring the Message Store"
# i.e. for Msg Srv 6.3: http://docs.sun.com/app/docs/doc/819-4428/bgayq?a=view

TS=`TZ=UTC /bin/date '+%Y%m%dT%H%M%SZ'` || TS='last'
[ x"$extTS" != x ] && TS="$extTS"
[ x"$REMOVELOCAL" = x ] && REMOVELOCAL=N

BASEDIR="/var/opt/backups/msgstore"
# This filename pattern is also used in compression below
ARCHFILE="$BASEDIR"/`hostname`.`domainname`_msgstore-backup-"$TS".arch
DUMPDIR="/DUMP/backups/msgstore"

# Don't let maintenance script break server's real works
[ x"$COMPRESS_NICE" = x ] && COMPRESS_NICE=17

[ x"$LOCK" = x ] && LOCK="/tmp/`basename "$0"`.`dirname "$0" | sed 's/\//_/g'`.lock"

# Path to Sun Messaging Server backup utility
IMSBACKUP=/opt/SUNWmsgsr/sbin/imsbackup
# List of IMS message-store partitions. Just one by default:
STOREPARTITIONS="/primary"

# Archive file rights and owner, try to set...
# chowner may fail so we try him after rights
[ x"$CHMOD_OWNER" = x ] && CHMOD_OWNER=0:0
[ x"$CHMOD_RIGHTS" = x ] && CHMOD_RIGHTS=600

### Program to measure time consumed by operation. Okay to be absent.
TIME=
[ -x /bin/time ] && TIME=/bin/time

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
        COSAS_BINDIR=`pwd`
fi
TIMERUN="$COSAS_BINDIR/timerun.sh"
DUMPDIR_CHECK_TIMEOUT=15

# Set a default compressor (bzip2 from PATH)
# and try to source the extended list of compressors
COMPRESSOR_BINARY="bzip2"
COMPRESSOR_SUFFIX=".bz2"
COMPRESSOR_OPTIONS="-c"
[ x"$COMPRESSOR_PREFERENCE" = x ] && \
    COMPRESSOR_PREFERENCE="pbzip2 bzip2 pigz gzip cat"
[ -s "$COSAS_BINDIR/compressor_list.include" -a \
  -s "$COSAS_BINDIR/compressor_choice.include" ] && \
    . "$COSAS_BINDIR/compressor_list.include"

# Source optional config files
[ x"$COSAS_CFGDIR" = x ] && COSAS_CFGDIR="$COSAS_BINDIR/../etc"
if [ -d "$COSAS_CFGDIR" ]; then
    [  -f "$COSAS_CFGDIR/COSas.conf" ] && \
        . "$COSAS_CFGDIR/COSas.conf"
    [  -f "$COSAS_CFGDIR/`basename "$0"`.conf" ] && \
        . "$COSAS_CFGDIR/`basename "$0"`.conf"
fi

# Try to source and select the actual compressor and its options
[ -s "$COSAS_BINDIR/compressor_list.include" -a \
  -s "$COSAS_BINDIR/compressor_choice.include" ] && \
    . "$COSAS_BINDIR/compressor_choice.include"

### Include this after config files, in case of RUNLEVEL_NOKICK mask override
RUN_CHECKLEVEL=""
[ -s "$COSAS_BINDIR/runlevel_check.include" ] &&
    . "$COSAS_BINDIR/runlevel_check.include" &&
    block_runlevel

cd "$BASEDIR" || exit 1
[ -x "$IMSBACKUP" ] || exit 1

# Check LOCKfile
if [ -f "$LOCK" ]; then
    OLDPID=`head -n 1 "$LOCK"`
    BN="`basename $0`"
    TRYOLDPID=`ps -ef | grep "$BN" | grep -v grep | awk '{ print $2 }' | grep "$OLDPID"`
    if [ x"$TRYOLDPID" != x ]; then

        LF=`cat "$LOCK"`

        echo "= SUNWmsg dump aborted because another copy is running - lockfile found:
$LF
Aborting..." | wall
        exit 1
    fi
fi
echo "$$" > "$LOCK"

if [ -x "$TIMERUN" ]; then
    "$TIMERUN" "$DUMPDIR_CHECK_TIMEOUT" ls -la "$DUMPDIR/" >/dev/null
    if [ $? != 0 ]; then
        echo "WARN: (archival) DUMPDIR='$DUMPDIR' is unreachable" >&2
    fi
else
    if [ ! -d "$DUMPDIR" ]; then
        echo "WARN: (archival) DUMPDIR='$DUMPDIR' is not a directory" >&2
    fi
fi

if [ x"$COMPRESS_NICE" != x ]; then
        echo "Setting process priority for dumping and compressing: '$COMPRESS_NICE'"
        renice "$COMPRESS_NICE" $$
fi

# Prepare the archive file
if touch "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__; then
    chmod "$CHMOD_RIGHTS" "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__
    chown "$CHMOD_OWNER" "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__

    echo "=== Archive file stub prepared: $ARCHFILE$COMPRESSOR_SUFFIX.__WRITING__"

    ARCHOK=-1
    $TIME "$IMSBACKUP" -f - $STOREPARTITIONS | \
        $COMPRESSOR_BINARY $COMPRESSOR_OPTIONS > "$ARCHFILE$COMPRESSOR_SUFFIX.__WRITING__"
    ARCHOK=$?

    if [ $ARCHOK = 0 ]; then
        mv -f "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__ "$ARCHFILE$COMPRESSOR_SUFFIX"
        RESULT=$?

        if [ x"$REMOVEORIG" = xY \
            -a x"$TS" != x/ -a x"$TS" != x. \
            ]; then
            rm -rf "$TS"
        fi
    else
        echo "`date`: $0: Can't complete dump file "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__" >&2
        rm -f "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__
        RESULT=1
    fi
else
    echo "`date`: $0: Can't create dump file "$ARCHFILE".__WRITING__" >&2
    rm -f "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__
    RESULT=2
fi

if [ -d "$DUMPDIR" -a -w "$DUMPDIR" -a -f "$ARCHFILE$COMPRESSOR_SUFFIX" -a "$RESULT" = 0 ]; then
    if [ x"$REMOVELOCAL" = xY ]; then
        mv -f "$ARCHFILE$COMPRESSOR_SUFFIX" "$DUMPDIR" 
        RESULT=$? 
    else
        cp -p "$ARCHFILE$COMPRESSOR_SUFFIX" "$DUMPDIR"
        RESULT=$?
    fi
fi

# Be nice, clean up
rm -f "$LOCK"

exit $RESULT
