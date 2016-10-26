#!/bin/bash

### logkeep-portal.sh
### A log rotater for Sun JES portal. 
### (C) Dec 2005-Jan 2014 by Jim Klimov, COS&HT
### $Id: logkeep-portal.sh,v 1.27 2014/01/25 11:57:17 jim Exp $

### Marks the files with rotation date and restarts the portal during rotation.
### WARNING: if webalizer is used to track monthly stats, don't rotate ACCESS
### logs at intermediate days, or configure/run webalizer to process additional
### (rotated) access log files. See also logkeep-weblb.sh for access log maint.
### Crontab for monthly rotations and daily if any logfile exceeds 100M:
### 10 0 * * * [ -x /opt/COSas/bin/logkeep-portal.sh ] && /opt/COSas/bin/logkeep-portal.sh -sz 102400
### 0 0 1 * * [ -x /opt/COSas/bin/logkeep-portal.sh ] && /opt/COSas/bin/logkeep-portal.sh -sz 0

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
AGENTDESC="Try to rotate data from portal web server"

### If defined, this directory will hold compressed files
### Otherwise files remain in their log dir
# DUMPDIR="/DUMP"

### Access rights for newly created empty logfiles.
### TODO: chmod and chown like old version
CHMOD_RIGHTS=644

### Successful rotation ends in compressing log files
### Don't let it break server's real works
COMPRESS_NICE=17

### Host of portal on this machine (to check state)
LOCALHOST=127.0.0.1
LOCALPORT=80

### Timeout for dump dir accessibility checks
FS_TIMEOUT=5

### space consumed on FS according to 'du -ks'
MAXSIZE=0

do_help() {
	echo "Utility:	$AGENTNAME"
	echo "	$AGENTDESC"

	echo "Usage: $0 [-d dumpdir] [-l localhostname] [-p localport] [-N nice] [-r rights] [-t fstimeout] [-sz maxsize]"
	echo "	dumpdir		place resulting files to dumpdir, otherwise to dir of log"
	echo "	localhostname	IP or name of portal ($LOCALHOST)"
	echo "	localport	portal's port number ($LOCALPORT)"
	echo "	nice		renice to priority nice before compression ($COMPRESS_NICE)"
	echo "	rights		set these rights to new empty logfiles ($CHMOD_RIGHTS)"
	echo "	fstimeout	timeout for dump dir accessibility checks ($FS_TIMEOUT)"
	echo "	maxsize		files larger than this (by 'du -ks') will be rotated ($MAXSIZE)"
}

### We check if it's running and should be restarted
COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
	COSAS_BINDIR=`pwd`
fi
AGENT_PORTAL="$COSAS_BINDIR/agent-web-portal.sh"
TIMERUN="$COSAS_BINDIR/timerun.sh"

### Sun ONE log files that tend to grow fast
### Comment away (via config file) access log files if you use webalizer.
### Use logrotate-weblb.sh to monthly rotate access logs instead.
LOGFILE_LIST_ACCESS="\
/opt/SUNWwbsvr*/https-*/logs/*/access \
/opt/SUNWwbsvr*/https-*/logs/access \
/var/opt/SUNWwbsvr*/https-*/logs/access \
/var/opt/SUNWwbsvr*/https-*/logs/*/access \
/var/opt/SUNWappserver*/domains/domain*/server*/logs/access \
"
LOGFILE_LIST_COMMON="\
/var/opt/SUNWam/debug/desktop.debug \
`find /var/opt/SUNWam/debug -name 'am*' -type f | grep -v '\.till'` \
/var/opt/SUNWam/debug/CCPPClientDetector \
/var/opt/SUNWam/debug/LDAPConnectionPool \
/var/opt/SUNWam/debug/MAPClientDetector \
/var/opt/SUNWam/stats/amMasterSessionTableStats \
/var/opt/SUNWam/stats/amSDKStats \
/var/opt/SUNWam/stats/amPolicyStats \
/var/opt/SUNWappserver*/domains/domain*/server*/logs/server.log \
/opt/SUNWwbsvr*/https-*/logs/errors \
/opt/SUNWwbsvr*/https-*/logs/*/errors \
/var/opt/SUNWwbsvr*/https-*/logs/errors \
/var/opt/SUNWwbsvr*/https-*/logs/*/errors \
"

### Redefine this in config file to rotate only common log files
LOGFILE_LIST="\
$LOGFILE_LIST_COMMON \
$LOGFILE_LIST_ACCESS \
"

### /var/opt/SUNWps/https-*/portal/logs/searchengine.log \

### Portal bundle controller script                                               
PORTAL_SCRIPT_LIST="/etc/init.d/portal /etc/init.d/portal7 /etc/init.d/portal71"
PORTAL_SCRIPT="/etc/init.d/portal"
for SP in $PORTAL_SCRIPT_LIST; do
    [ -s "$SP" -a -x "$SP" ] && PORTAL_SCRIPT="$SP"
done
### restart param may be restartVRTS for Veritas setup of portal(6) script
PORTAL_SCRIPT_RESTART="restart"
# PORTAL_SCRIPT_RESTART="restarthard"
# PORTAL_SCRIPT_RESTART="restartVRTS"

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
		-d) DUMPDIR="$2"; shift;;
		-l) LOCALHOST="$2"; shift;;
		-p) LOCALPORT="$2"; shift;;
                -N) COMPRESS_NICE="$2"; shift;;
                -n) echo "INFO: '-n' is deprecated for setting a NICE level, change calls to '-N' please" >&2
                    COMPRESS_NICE="$2"; shift;;
		-r) CHMOD_RIGHTS="$2"; shift;;
		-t) FS_TIMEOUT="$2"; shift;;
		-sz) MAXSIZE="$2"; shift;;
		*) echo "Unknown param:	$1" >&2;;
	esac
	shift
done

### Check binaries
if [ ! -x "$AGENT_PORTAL" ]; then
	echo "Requires: agent-web-portal '$AGENT_PORTAL'" >&2
	exit 1
fi

if [ ! -x "$TIMERUN" ]; then
	echo "Requires: timerun '$TIMERUN'" >&2
	exit 1
fi

if [ ! -x "$PORTAL_SCRIPT" ]; then
	echo "Requires: PORTAL_SCRIPT '$PORTAL_SCRIPT'" >&2
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

RESULT=0

"$AGENT_PORTAL" "$LOCALHOST" "$LOCALPORT"
RESULT_PORTAL=$?

### Work only if portal server is up. If it died, we don't want to change system too much.
if [ $RESULT_PORTAL = 0 ]; then
	ROTATED=""
	for F in $LOGFILE_LIST; do
		if [ -s "$F" ]; then
			### By -s we also ensure that file is not empty
			TIMESTAMP="`TZ=UTC /bin/date +%Y%m%dT%H%M%SZ`"

			# This is a more true size than ls's column 5
			# in case of sparse or compressed files and FSes
                        SZ=`du -ks "$F" | awk '{ print $1 }'`

			if [ "$MAXSIZE" -lt "$SZ" ]; then
			    R="$F.till_$TIMESTAMP"
			    EXOWNER=`ls -la "$F" | awk '{ print $3":"$4 }'`

			    if mv -f "$F" "$R"; then
				echo "Rotated $F to $R"
				ROTATED="$ROTATED $R"
				touch "$F"
				### TODO: chmod and chown new file like old one
				chmod "$CHMOD_RIGHTS" "$F"
				chown "$EXOWNER" "$F"
			    else
				echo "Failed to move $F to $R" >&2
				RESULT=2
			    fi
			else
			    echo "Did not rotate $F - too small ($SZ < $MAXSIZE)" >&2
			fi
		fi
	done

	if [ x"$ROTATED" = x ]; then
	    echo "No files rotated, no restart needed" >&2
	    exit 0
	fi

	### Ensure that portal now writes its logs to different files
	"$PORTAL_SCRIPT" $PORTAL_SCRIPT_RESTART

	if [ x"$COMPRESS_NICE" != x ]; then
		echo "Setting process priority for compressing: '$COMPRESS_NICE'"
		renice "$COMPRESS_NICE" $$
	fi

	for R in $ROTATED; do
		RZ="$R$COMPRESSOR_SUFFIX"
		if [ x"$DUMPDIR" != x ]; then
			### Check accessibility
			### If inaccessible, compress logs where they are
			"$TIMERUN" "$FS_TIMEOUT" ls -la "$DUMPDIR" >/dev/null
			if [ $? = 0 ]; then
				if [ -d "$DUMPDIR" -a -w "$DUMPDIR" ]; then
					RZ="$DUMPDIR/`basename "$R"`$COMPRESSOR_SUFFIX"
				else
					echo "Storage dir '$DUMPDIR' inaccessible, compressing log where it was!" >&2
				fi
			else
				echo "Storage dir '$DUMPDIR' inaccessible, compressing log where it was!" >&2
			fi
		fi

		RZW="$RZ.__WRITING__"
		echo -n "Compressing $R to $RZW... "

		### Redirection allows to avoid problems with files over 2gb
		$COMPRESSOR_BINARY $COMPRESSOR_OPTIONS < "$R" > "$RZW"

		if [ $? = 0 ]; then
			echo -n "moving $RZW to $RZ... "
			mv -f "$RZW" "$RZ"
			if [ $? = 0 ]; then
				echo -n "removing $R... "
				rm "$R" || RESULT=5
			else
				echo "Failed to move $RZW to $RZ" >&2
				RESULT=4
			fi
		else
			echo "Problem compressing $R to $RZW! Removing unfinished work..." >&2
			rm -f "$RZW"
			RESULT=3
		fi
		echo "complete."
	done
else
	echo "Portal on $LOCALHOST not up, not rotating logs" >&2
	RESULT=$RESULT_PORTAL
fi

### Be nice, clean up
rm -f "$LOCK"

exit $RESULT

