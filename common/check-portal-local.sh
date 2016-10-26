#!/bin/bash

# check-portal-local.sh
# (C) Nov 2005-May 2015 by Jim Klimov, COS&HT
# $Id: check-portal-local.sh,v 1.30 2015/05/15 08:09:57 jim Exp $

# check-portal-local.sh [-n] [-V] [-t timeout] [-u URL] [-P POSTDATA] [host [port]]
# Checks that portal (default localhost:80) is up and responds with anything
# Otherwise (re-)starts it
# Logs restarts to LOGFILE=/var/log/check-portal.log if the file exists and is writable

AGENTNAME="`basename "$0"`"
AGENTDESC="Check and kick portal on local machine"

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
	COSAS_BINDIR=`pwd`
fi
AGENT_PORTAL="$COSAS_BINDIR/agent-web-portalOra.sh"

# Portal bundle controller script
SCRIPT_PORTAL_LIST="/etc/init.d/portal /etc/init.d/portal7 /etc/init.d/portal71"
SCRIPT_PORTAL_RESTART="restart"
#SCRIPT_PORTAL_RESTART="restarthard"
SCRIPT_PORTAL="/etc/init.d/portal"
for SP in $SCRIPT_PORTAL_LIST; do
    [ -s "$SP" -a -x "$SP" ] && SCRIPT_PORTAL="$SP"
done

### Note: for SMF services this could be like:
#SCRIPT_PORTAL="/usr/sbin/svcadm"
#SCRIPT_PORTAL_RESTART="restart glassfish"

TCPTIMEOUT=35

[ x"$CONNHOST" = x ] && CONNHOST=127.0.0.1
[ x"$CONNPORT" = x ] && CONNPORT=80
[ x"$HTTP_METHOD" = x ] && HTTP_METHOD=GET
[ x"$VERBOSE_OUT" = x ] && VERBOSE_OUT=0

### Empty PSDESKTOP(URL) causes usage of URL defined for the agent
### 2 varnames due to historical backward compatibility, merged below.
### Primary name:  TESTURL
### Some URLs to request include:
# TESTURL="/portal/dt"
# TESTURL="/amserver/isAlive.jsp"
[ x"$TESTURL" = x ] && TESTURL=""
[ x"$PSDESKTOP" = x ] && PSDESKTOP=""
[ x"$PSDESKTOPURL" = x ] && PSDESKTOPURL=""

FREESPACE_PARAMS=""

LOGFILE=/var/log/check-portal.log

# Params for lockfile
BUGMAIL="postmaster"
HOSTNAME=`hostname`

# TODO Lockfile name should depend on params (dir)
LOCK_BASE="/tmp/$AGENTNAME.lock"
# Set WAIT_C=0 to skip waits
WAIT_C=5
WAIT_S=15

# Source optional config files
[ x"$COSAS_CFGDIR" = x ] && COSAS_CFGDIR="$COSAS_BINDIR/../etc"
if [ -d "$COSAS_CFGDIR" ]; then
    [  -f "$COSAS_CFGDIR/COSas.conf" ] && \
        . "$COSAS_CFGDIR/COSas.conf"
    [  -f "$COSAS_CFGDIR/`basename "$0"`.conf" ] && \
        . "$COSAS_CFGDIR/`basename "$0"`.conf"
fi

# Historical backward compatibility - used if old vars are defined but TESTURL is not
[ x"$PSDESKTOP" != x -a x"$TESTURL" = x ] && TESTURL="$PSDESKTOP"
[ x"$PSDESKTOPURL" != x -a x"$TESTURL" = x ] && TESTURL="$PSDESKTOPURL"

# If == 1, don't restart, but check no locking either
CHECKONLY=0

do_help() {
	echo "Utility:	$AGENTNAME"
	echo "	$AGENTDESC"

	echo "Usage: $0 [-n] [-V] [-t timeout] [-u URL] [-P POSTDATA] [host [port]]"
	echo "Defaults: timeout=$TCPTIMEOUT, host=$CONNHOST, port=$CONNPORT, agent-default URL"
	echo "Use -n to only check the status, but not restart; skip lock checks"
}


# Parse params
# We always have a default host/port/timeout
GOTWORK=1

while [ $# -gt 0 ]; do
	case "$1" in
		-h) do_help; exit 0;;
		-V) VERBOSE_OUT=1 ;;
		-t) 
			# One more shift, two words
                        shift 1
                        OK=no
                        if [ x"$1" != x ]; then
                                if [ "$1" -gt 0 ]; then
                                        TCPTIMEOUT="$1"
                                        OK=yes
                                fi
                        fi
                        if [ $OK = no ]; then
                                echo "Wrong timeout, using default" >&2
                        fi
                        ;;
		-u)
			shift
			TESTURL="$1"
			;;
		-P) HTTP_METHOD=POST; HTTP_POSTDATA="$2"; shift 1;;
		-n) CHECKONLY=1 ;;
		*) case $# in
			1)
				if [ x"$CONNHOST" = x ]; then
					CONNHOST="$1"
				else
					CONNPORT="$1"
				fi
				;;
			2) CONNHOST="$1";;
			*) do_help >&2; exit 1;;
		esac ;;
	esac
	shift
done

[ x"$CONNHOST" = x ] && CONNHOST=127.0.0.1
[ x"$CONNPORT" = x ] && CONNPORT=80

### Include this after config files, in case of RUNLEVEL_NOKICK mask override
RUN_CHECKLEVEL=""
[ -s "$COSAS_BINDIR/runlevel_check.include" ] &&
        . "$COSAS_BINDIR/runlevel_check.include" &&
	block_runlevel

# Checkers
if [ ! -x "$AGENT_PORTAL" ]; then
	echo "Requires: agent-portal '$AGENT_PORTAL'" >&2
	exit 1
fi

if [ "$GOTWORK" = 0 ]; then
	echo "Wrong number of required params received. Aborting!"
	exit 1
fi

LOCK="$LOCK_BASE.$CONNHOST-$CONNPORT"

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

### Do some work now...
do_check() {
  VERB=""
  if [ x"$VERBOSE_OUT" = x1 ]; then VERB="-V"; fi
  if [ x"$TESTURL" = x ]; then
    time "$AGENT_PORTAL" -t "$TCPTIMEOUT" $VERB \
	${HTTP_POSTDATA:+-P "$HTTP_POSTDATA"} "$CONNHOST" "$CONNPORT" 2>&1
  else
    time "$AGENT_PORTAL" -t "$TCPTIMEOUT" $VERB -u "$TESTURL" \
	${HTTP_POSTDATA:+-P "$HTTP_POSTDATA"} "$CONNHOST" "$CONNPORT" 2>&1
  fi
}

#OUTPUT=`do_check 2>&1`
OUTPUT=`do_check`
RESULT=$?

case $RESULT in
	1) # param error
		if [ x"$VERBOSE_OUT" = x1 ]; then echo "$OUTPUT"; fi
		RESULT=1 ;;
	0) # ok
		if [ x"$VERBOSE_OUT" = x1 ]; then echo "$OUTPUT"; fi
		RESULT=0 ;;
	34) # Host unknown
		if [ x"$VERBOSE_OUT" = x1 ]; then echo "$OUTPUT"; fi
		RESULT=1 ;;
	32|33|255|65535) #conn refused, time out
		echo "$OUTPUT" >&2
		if [ -w "$LOGFILE" ]; then
		    [ $CHECKONLY = 0 ] && echo "`date`: portal froze ( $RESULT ), restarting" >> "$LOGFILE"
		    [ $CHECKONLY = 1 ] && echo "`date`: portal froze ( $RESULT ), restart skipped (check only)" >> "$LOGFILE"
		fi
		[ $CHECKONLY = 0 -a -x "$SCRIPT_PORTAL" ] && $RUN_CHECKLEVEL "$SCRIPT_PORTAL" $SCRIPT_PORTAL_RESTART
		RESULT=$?
		;;
	*) # other errors, may choose to ignore...
		echo "$OUTPUT" >&2
		if [ -w "$LOGFILE" ]; then
		    [ $CHECKONLY = 0 ] && echo "`date`: portal error ( $RESULT ), restarting" >> "$LOGFILE"
		    [ $CHECKONLY = 1 ] && echo "`date`: portal error ( $RESULT ), restart skipped (check only)" >> "$LOGFILE"
		fi
		[ $CHECKONLY = 0 -a -x "$SCRIPT_PORTAL" ] && $RUN_CHECKLEVEL "$SCRIPT_PORTAL" $SCRIPT_PORTAL_RESTART
		RESULT=$?
		;;
esac

# Be nice, clean up
[ $CHECKONLY = 0 ] && rm -f "$LOCK"

exit $RESULT
