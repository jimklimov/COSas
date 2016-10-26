#!/bin/sh

# dumper-sunics5-hotbackup.sh
# (C) Nov 2007-Dec 2008 by Jim Klimov, COS&HT
# $Id: dumper-sunics5-hotbackup.sh,v 1.23 2012/05/06 15:56:20 jim Exp $
# Creates an archive from a dump of Sun Calendar Server (ICS5 from JCS5) data
# Default Sun ICS dump method is to copy several database files;
# this script creates a single archive and can copy it to (remote) DUMPDIR
# Calendar does its daily(!) archiving itself; we only make a single-file copy 

# For use from cron
# 45 3 * * * [ -x /opt/COSas/bin/dumper-sunics5-hotbackup.sh ] && /opt/COSas/bin/dumper-sunics5-hotbackup.sh

[ x"$LOCK" = x ] && LOCK="/tmp/`basename "$0"`.`dirname "$0" | sed 's/\//_/g'`.lock"
# TS format dictated by Sun Commsuite's backup dir names
# as YYYYMMDD (see TSDIR below) in local time-date
TS=`/bin/date '+%Y%m%dT%H%M%S'` || TS='last'   ### NON-UTC!
[ x"$extTS" != x ] && TS="$extTS"
[ x"$REMOVEORIG" = x ] && REMOVEORIG=Y
[ x"$REMOVELOCAL" = x ] && REMOVELOCAL=N
TSDIR=`echo "$TS" | /bin/cut -c 1-8`
BASEDIR=/var/opt/SUNWics5/csdb/hotbackup
ARCHFILE="$BASEDIR"/`hostname`.`domainname`_csdb-hotbackup-"$TS".tar
DUMPDIR="/DUMP/SUNWics5/csdb/hotbackup"

# Don't let maintenance script break server's real works
[ x"$COMPRESS_NICE" = x ] && COMPRESS_NICE=17

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

### Some sanity checks
if [ ! -d "$BASEDIR" ]; then
    echo "FATAL ERROR: (working) BASEDIR='$BASEDIR' is not a directory" >&2
    exit 1
fi

cd "$BASEDIR" || exit 1

# Check LOCKfile
if [ -f "$LOCK" ]; then
    OLDPID=`head -n 1 "$LOCK"`
    BN="`basename $0`"
    TRYOLDPID=`ps -ef | grep "$BN" | grep -v grep | awk '{ print $2 }' | grep "$OLDPID"`
    if [ x"$TRYOLDPID" != x ]; then

        LF=`cat "$LOCK"`

        echo "= SUNWics hotbackup dump aborted because another copy is running - lockfile found:
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

if [ -d "$TSDIR" ]; then
# Prepare the archive file
    if touch "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__; then
        chmod "$CHMOD_RIGHTS" "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__
	chown "$CHMOD_OWNER" "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__

        echo "=== Archive file stub prepared: $ARCHFILE$COMPRESSOR_SUFFIX.__WRITING__"

        $TIME tar cf - "$TSDIR" | \
            $COMPRESSOR_BINARY $COMPRESSOR_OPTIONS > "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__
        ARCHOK=$?

        if [ $ARCHOK = 0 ]; then
            mv -f "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__ "$ARCHFILE$COMPRESSOR_SUFFIX"
            RESULT=$?
	    if [ x"$REMOVEORIG" = xY \
    	        -a x"$TSDIR" != x/ -a x"$TSDIR" != x. \
    	        ]; then
        	    rm -rf "$TSDIR"
    	    fi
        else
            echo "`date`: $0: Can't complete dump file "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__" >&2
	    rm -f "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__
            RESULT=1
        fi

    else
	echo "`date`: $0: Can't create dump file "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__" >&2
	rm -f "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__
	RESULT=2
    fi
else
    echo "`date`: $0: No timestamped dir to dump: $TSDIR" >&2
    RESULT=3
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
