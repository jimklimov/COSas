#!/bin/bash

### logkeep-weblb.sh
### A log rotater for Sun Web Server as a multi-virthost server (load balancer)
### Runs webalizer if available; thus is very aimed at running once per month.
### and at using Sun Web server with its default log file format.
### Clone this script (not improve) if needed for other servers (Sun AppServer,
### tomcat, apache httpd, etc.)
### (C) May 2009-Jan 2014 by Jim Klimov, COS&HT
### $Id: logkeep-weblb.sh,v 1.11 2014/01/25 11:57:17 jim Exp $

### Marks the files with rotation date and reconfig's SWS during rotation.
### Crontab for monthly rotations:
### 0 0 1 * * [ -x /opt/COSas/bin/logkeep-weblb.sh ] && /opt/COSas/bin/logkeep-weblb.sh -sz 128

### Numerous problems can cause different return codes, some are:
### 0	no error detected
### 1	command-line parsing
### 2	couldn't rotate a logfile
### 3	couldn't compress a logfile to temp file
### 4	couldn't rename a compressed temp file
### 5	couldn't remove an uncompressed log file
### 255	timeouts (portal)
### Seek problem descriptions in stderr as well

AGENTNAME="`basename "$0"`"
AGENTDESC="Monthly rotate log data from Sun Web server (as load balancer or other multivirthost); run webalizer if available"

### If defined, this directory will hold compressed files
### Otherwise files remain in their log dir
# DUMPDIR="/DUMP"

### Access rights for newly created empty logfiles.
### If CHOWN_UGID is defined, use it; otherwise try to set like old file
### TODO: chmod and chown like old version
CHMOD_RIGHTS="644"
#CHOWN_UGID="webservd:webservd"
CHOWN_UGID=""

### Successful rotation ends in compressing log files
### Don't let it break server's real works
COMPRESS_NICE=17

### Timeout for dump dir accessibility checks
FS_TIMEOUT=5

### space consumed on FS according to 'du -ks'
### file size also filtered by 'wc -l' > 10, below (shorter files remain)
MAXSIZE=0

### Typical date in apache-style logs looks like:
###   [24/Apr/2009:02:31:17 +0400]
### We'll grep 'Mon/YEAR:' to catch last lines of the log file which match
### new month. Do nothing similar if it is set to empty (in cfg file).
### Note: mechanism is currently limited to currently starting month,
### see "grep &" below
MONTH_MARK="`LC_ALL=C LC_TIME=C date '+%b/%Y:'`"

### If !=yes, skip running webalizer before rotation, but copy month-start
### lines to new logfile anyway
USE_WEBALIZER=yes

do_help() {
	echo "Utility:	$AGENTNAME"
	echo "	$AGENTDESC"

	echo "Usage: $0 [-d dumpdir] [-l localhostname] [-p localport] [-N nice] [-r rights] [-u user:group] [-t fstimeout] [-m monthmark] [-sz maxsize] [--skip-webalizer]"
	echo "	dumpdir		place resulting files to dumpdir, otherwise rotates"
	echo "			and compresses in-place to dir of log"
	echo "	nice		renice to priority nice before compression ($COMPRESS_NICE)"
	echo "	rights		set these rights to new empty logfiles ($CHMOD_RIGHTS)"
	echo "	user:group	(opt) set these owner credentials to new empty logfiles ($CHOWN_UGID)"
	echo "	fstimeout	timeout for dump dir accessibility checks ($FS_TIMEOUT)"
	echo "	monthmark	string to grep for new month in old logs ($MONTH_MARK)"
	echo "	maxsize		files larger than this (by 'du -ks') will be rotated ($MAXSIZE)"
	echo "  --skip-webalizer	if set, don't run webalizer before log rotation"
	echo "			(if valid webalizer path is set, copies month-start anyway)"
}

### We check if it's running and should be restarted
COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
	COSAS_BINDIR=`pwd`
fi
TIMERUN="$COSAS_BINDIR/timerun.sh"

### Sun Web Server log files
LOGFILE_LIST="\
/var/opt/SUNWwbsvr*/https-*/logs/access \
/var/opt/SUNWwbsvr*/https-*/logs/errors \
/var/opt/SUNWwbsvr*/https-*/logs/*/access \
/var/opt/SUNWwbsvr*/https-*/logs/*/errors \
/opt/SUNWwbsvr*/https-*/logs/access \
/opt/SUNWwbsvr*/https-*/logs/errors \
/opt/SUNWwbsvr*/https-*/logs/*/access \
/opt/SUNWwbsvr*/https-*/logs/*/errors \
"
### TEST:
#LOGFILE_LIST=/var/opt/SUNWwbsvr7/https-*/logs/DUMMY*/access

### Sun Web Server script to reinitialize quickly
# TODO: seems that reconfig does not write to new log files.
#       utilize rotate and/or restart (for now)
#SWSRECONFIG_LIST="`ls -1 /var/opt/SUNWwbsvr*/https-*/bin/reconfig`"
SWSRECONFIG_LIST="`ls -1 /var/opt/SUNWwbsvr*/https-*/bin/restart`"

### If available, run webalizer on these logfiles just before rotation
WEBALIZER_RUN='/opt/webalizer/bin/analyze'

### Params for lockfile
BUGMAIL="postmaster"
HOSTNAME=`hostname`

### TODO Lockfile name should depend on params?
LOCK_BASE="/tmp/$AGENTNAME.lock"
# Set WAIT_C=0 to skip waits
WAIT_C=5
WAIT_S=15

VERBOSE=""

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

### Include this after config files, in case of RUNLEVEL_NOKICK mask override
RUN_CHECKLEVEL=""
[ -s "$COSAS_BINDIR/runlevel_check.include" ] &&
    . "$COSAS_BINDIR/runlevel_check.include" &&
    block_runlevel

while [ $# -gt 0 ]; do
	case "$1" in
		-h) do_help; exit 0;;
		-v) VERBOSE=-v;;
		--skip-webalizer) USE_WEBALIZER=no;;
		-d) DUMPDIR="$2"; shift;;
		-N) COMPRESS_NICE="$2"; shift;;
		-n) echo "INFO: '-n' is deprecated for setting a NICE level, change calls to '-N' please" >&2
		    COMPRESS_NICE="$2"; shift;;
		-r) CHMOD_RIGHTS="$2"; shift;;
		-u) CHOWN_UGID="$2"; shift;;
		-t) FS_TIMEOUT="$2"; shift;;
		-m) MONTH_MARK="$2"; shift;;
		-sz) MAXSIZE="$2"; shift;;
		*) echo "Unknown param:	$1" >&2;;
	esac
	shift
done

### Check binaries
if [ ! -x "$TIMERUN" ]; then
	echo "Requires: timerun '$TIMERUN'" >&2
	exit 1
fi

# Try to source and select the actual compressor and its options
[ -s "$COSAS_BINDIR/compressor_list.include" -a \
  -s "$COSAS_BINDIR/compressor_choice.include" ] && \
    . "$COSAS_BINDIR/compressor_choice.include"

LOCK="$LOCK_BASE.`echo "$DUMPDIR" | sed 's/\//_/g'`"

if [ x"$VERBOSE" != "" ]; then
	echo "My params: lock=$LOCK"
fi

### Check LOCKfile
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

if ! [ "$MAXSIZE" -ge 0 ]; then
    echo "Invalid MAXSIZE ($MAXSIZE) fixed to 0"
    MAXSIZE=0
fi

echo "$$" > "$LOCK"

if [ -x "$WEBALIZER_RUN" -a "$USE_WEBALIZER" = yes ]; then
    # TODO: initial idea was to run webalizer in background, so it would lock
    # the log files and prevent them from being erased before it finished
    # processing. However due to DNS lookups and caching, the database file
    # can be locked so only one webalizer can run at a time.
    # So far we'd rather forfeit the first few log entries of the month in
    # the statistics (i.e. at 00:00 webalizer starts, at 00:03 it ends and
    # we actually rotate the logs, losing from future stats these few entries).
    # But we'll try to cheat by grepping these last lines into the new log...

    echo "=== Run webalizer for the last time on these logs..."
    "$WEBALIZER_RUN"
fi

### Result may change on failures. If it remains 0, none happened.
RESULT=0

### List of rotated filenames
ROTATED=""
for F in $LOGFILE_LIST; do
    if [ -s "$F" ] && [ `wc -l "$F" | awk '{ print $1 }'` -gt 10 ]; then
	### By -s we also ensure that file exists and is not empty
	### By 'wc -l' we ensure it's big enough to rotate
	TIMESTAMP=`TZ=UTC date +%Y%m%dT%H%M%SZ`
	R="$F.till_$TIMESTAMP"

        # This is a more true size than ls's column 5
        # in case of sparse or compressed files and FSes
        SZ=`du -ks "$F" | awk '{ print $1 }'`

        if [ "$MAXSIZE" -lt "$SZ" ]; then
          R="$F.till_$TIMESTAMP"
          EXOWNER=`ls -la "$F" | awk '{ print $3":"$4 }'`

	  if mv -f "$F" "$R"; then
	    echo "=== Rotated $F to $R"
	    ROTATED="$ROTATED $R"


	    touch "$F"
	    ### TODO: chmod and chown new file like old one
	    chmod "$CHMOD_RIGHTS" "$F"
	    if [ x"$CHOWN_UGID" = x ]; then
		chown "$EXOWNER" "$F"
	    else
		chown "$CHOWN_UGID" "$F"
	    fi

	    ### If we use webalizer, try to save last few log lines
	    ### of the new month for more complete statistics (gaps
	    ### are still possible)
	    [ -x "$WEBALIZER_RUN" -a x"$MONTH_MARK" != x ] && case "$F" in
		*access*)
		    echo "==== Saving last lines of old log file matching current new month ($MONTH_MARK) into new logfile $F..."
		    head -1 "$R" > "$F"
		    grep "$MONTH_MARK" "$R" >> "$F" &
		    ;;
	    esac
	  else
	    echo "===== ERROR: Failed to move $F to $R" >&2
	    RESULT=2
	  fi
	else
	    echo "===== INFO: Did not rotate $F - too small ($SZ < $MAXSIZE)" >&2
	fi
    fi
done

### Let finish async statistics copiers...
wait

### Ensure that webserver now writes its logs to different files
for F in $SWSRECONFIG_LIST; do
    echo "=== Refreshing webserver: $F ..."
    [ -x "$F" ] && "$F"
done

if [ x"$COMPRESS_NICE" != x ]; then
    echo "=== Setting process priority for compressing: '$COMPRESS_NICE'"
    renice "$COMPRESS_NICE" $$
fi

for R in $ROTATED; do
    echo "=== Begin processing file $R"

    RZ="$R$COMPRESSOR_SUFFIX"
    if [ x"$DUMPDIR" != x ]; then
	### Check accessibility
	### If inaccessible, compress logs where they are

	"$TIMERUN" "$FS_TIMEOUT" ls -la "$DUMPDIR" >/dev/null

	if [ $? = 0 ]; then
	    if [ -d "$DUMPDIR" -a -w "$DUMPDIR" ]; then
	        RZ="$DUMPDIR/`basename "$R"`$COMPRESSOR_SUFFIX"
	    else
	        echo "===== INFO: Storage dir '$DUMPDIR' inaccessible, compressing log where it was!" >&2
	    fi
	else
	    echo "===== INFO: Storage dir '$DUMPDIR' inaccessible, compressing log where it was!" >&2
        fi
    fi

    RZW="$RZ.__WRITING__"
    echo -n "==== Compressing $R to $RZW... "

    ### Redirection allows to avoid problems with files over 2gb
    $COMPRESSOR_BINARY $COMPRESSOR_OPTIONS < "$R" > "$RZW"

    if [ $? = 0 ]; then
        echo -n "==== Moving $RZW to $RZ... "
	mv -f "$RZW" "$RZ"

    	if [ $? = 0 ]; then
	    echo -n "==== Removing $R... "
	    rm "$R" || RESULT=5
	else
	    echo "===== ERROR: Failed to move $RZW to $RZ" >&2
	    RESULT=4
	fi
    else
	echo "===== ERROR: Problem compressing $R to $RZW! Removing unfinished work..." >&2
	rm -f "$RZW"
	RESULT=3
    fi
    echo "=== Processing of $R is complete."
done

echo "= `date`: Finished [$RESULT]"

### Be nice, clean up
rm -f "$LOCK"

exit $RESULT
