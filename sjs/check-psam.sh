#!/bin/bash

### Concept script to check and kick access manager (alive/login) and
### inform messaging server if amserver was restarted (for UWC with AMAgent),
### so they restart in concert (otherwise messaging server's login session
### into the separate Access Manager instance times out upon restart of AM).
### Run via cron in PSAM zone and WEBMAIL zone
###   * * * * * [ -x /opt/COSas/bin/check-psam.sh ] && /opt/COSas/bin/check-psam.sh > /dev/null
### Also run via initscripts to purge the old status files:
###   ln -s /opt/COSas/bin/check-psam.sh /etc/rc3.d/S10check-psam

### NOTE: Requires config file to run!

### TODO: support multi-instance PSAM/OpenSSO with session replication
###   test - maybe UWC restart is only needed if both servers went down
###   and one is okay
### TODO: see if portal support is required - placeholder at the moment
### TODO: some specific logging?
### (C) Jim Klimov, May 2009-Jan 2014
### $Id: check-psam.sh,v 1.16 2014/12/09 13:20:14 jim Exp $

AGENTNAME="`basename "$0"`"
AGENTDESC="Check AMServer status and startup time; use on AMClients to restart them after amserver - if needed"

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
        COSAS_BINDIR=`pwd`
fi

PROCTREE="$COSAS_BINDIR/proctree.sh"

### Script instances in various zones interact via shared dir (lofs, nfs)
### time should be synchronized! (zones on same machine or NTP for different)
SHAREDIR="/export/shared-psam"
TIMEOUT=5
AGENT_FREESPACE="$COSAS_BINDIR/agent-freespace.sh"
### will pass freespace params to agent-freespace.sh
FREESPACE_PARAMS=""

### Config file of COSps71 and certain defaults relevant to us
### This script's own config file, if available, should override.
PS71CONFIG="/etc/default/portal71.conf.local"
PS71ROLE_MSG_UWC_SERVER=no
PS71ROLE_AMSERVER=no
PS71ROLE_PSSERVER=no

### Use these scripts and params to check web services' availability
### Pass params. Actualy do all this if DO_CHECK_* is not 0.
CHECK_AMSERVER_ALIVE="$COSAS_BINDIR/check-portal-local.sh"
CHECK_AMSERVER_ALIVE_PARAMS="-u /amserver/isAlive.jsp localhost 80"
CHECK_AMSERVER_LOGIN="$COSAS_BINDIR/check-amserver-login.sh"
CHECK_AMSERVER_LOGIN_PARAMS="localhost 80"
[ x"$DO_CHECK_AMSERVER" = x ] && DO_CHECK_AMSERVER=0
[ x"$DO_CHECK_AMLOGIN" = x ] &&  DO_CHECK_AMLOGIN=0

CHECK_PORTAL_ALIVE="$COSAS_BINDIR/check-portal-local.sh"
CHECK_PORTAL_ALIVE_PARAMS="-u /portal/dt localhost 80"
[ x"$DO_CHECK_PORTAL" = x ] &&   DO_CHECK_PORTAL=0

CHECK_WEBMAILUWC_ALIVE="$COSAS_BINDIR/check-portal-local.sh"
CHECK_WEBMAILUWC_ALIVE_PARAMS="-u /uwc/auth localhost 80"
[ x"$DO_CHECK_WEBMAILUWC" = x ] && DO_CHECK_WEBMAILUWC=0

### We require a GNU date with +%s param
GDATE_LIST="/opt/COSac/bin/gdate /usr/gnu/bin/gdate /usr/gnu/bin/date /opt/sfw/bin/gdate /usr/local/bin/date /usr/local/bin/gdate /usr/sfw/bin/gdate /usr/sfw/bin/date"
[ x"`uname -s`" = xLinux ] && GDATE_LIST="$GDATE_LIST /bin/date"
GDATE=""

### Portal bundle controller script
PORTAL_SCRIPT_LIST="/etc/init.d/portal /etc/init.d/portal7 /etc/init.d/portal71"
PORTAL_SCRIPT="/etc/init.d/portal"
for SP in $PORTAL_SCRIPT_LIST; do
    [ -s "$SP" -a -x "$SP" ] && PORTAL_SCRIPT="$SP"
done
### restart param may be restartVRTS for Veritas setup of portal(6) script
### for larger messaging deployments (IM as well as web) or appserver, use
### heavier restarts. But they take longer.
PORTAL_SCRIPT_RESTART="restartweb"
# PORTAL_SCRIPT_RESTART="restartas"
# PORTAL_SCRIPT_RESTART="restartmsg-psamdep"
# PORTAL_SCRIPT_RESTART="restart"
# PORTAL_SCRIPT_RESTART="restarthard"
# PORTAL_SCRIPT_RESTART="restartVRTS"

### Params for lockfile
BUGMAIL="postmaster"
HOSTNAME=`hostname`

# TODO Lockfile name should depend on params (dir)
LOCK_BASE="/tmp/$AGENTNAME.lock"
# Set WAIT_C=0 to skip waits
WAIT_C=5
WAIT_S=15

do_help() {
        echo "Utility:  $AGENTNAME"
        echo "  $AGENTDESC"

        echo "Usage: $0 [-n] [-nf] [-nw] [-v]"
        echo "	-n	don't restart webservers; don't modify status file; skip lock"
        echo "	-nw	don't restart webservers"
        echo "	-nf	don't modify status file"
        echo "	-v	verbose progress"
        echo "All params passed in config files for $CHECK_AMSERVER_LOGIN and $CHECK_AMSERVER_ALIVE and this script itself"
        echo "init.d usage to clean up status files: $0 {start|stop}"
}

### if CHECKONLY_WEB != 0, don't restart webservers
### if CHECKONLY_STAT != 0, don't update status file
### if CHECKONLY != 0, don't restart webservers AND don't update status file
###    but ignore script-locking too
CHECKONLY=0
CHECKONLY_WEB=0
CHECKONLY_STAT=0
VERBOSE=no

# Source required config file(s)
INCLUDES=0

[ x"$COSAS_CFGDIR" = x ] && COSAS_CFGDIR="$COSAS_BINDIR/../etc"
if [ -d "$COSAS_CFGDIR" ]; then
    [  -f "$COSAS_CFGDIR/COSas.conf" ] && \
        . "$COSAS_CFGDIR/COSas.conf" && INCLUDES=1
    [  -f "$COSAS_CFGDIR/`basename "$0"`.conf" ] && \
        . "$COSAS_CFGDIR/`basename "$0"`.conf" && INCLUDES="`echo $INCLUDES+2|bc`"
fi

if [ "$INCLUDES" -lt 2 ]; then
    echo "ERROR: this script requires a config file ($COSAS_CFGDIR/`basename "$0"`.conf)." >&2
    echo "    At least 'touch' it if you think defaults are okay" >&2
    exit 1
fi

if [ -f "$PS71CONFIG" ]; then
    ### Path to this COSps71 file could be redefined in configs above.
    ### But their values for this server's roles are of higher priority -
    ### so we re-include this script's config.
    . "$PS71CONFIG"
    [  -f "$COSAS_CFGDIR/`basename "$0"`.conf" ] && \
        . "$COSAS_CFGDIR/`basename "$0"`.conf"
fi

SHAREDFILE_PSAM="$SHAREDIR/psam.status"
SHAREDFILE_PSAM_PORTAL="$SHAREDFILE_PSAM.portal"
SHAREDFILE_PSAM_UWC="$SHAREDFILE_PSAM.webmail-uwc"

### Process command-line params
while [ $# -gt 0 ]; do
	case "$1" in
		start|stop)
		    ### Use from init scripts to clean up work files
		    if [ "$PS71ROLE_AMSERVER" = yes ]; then
		        rm -f "$SHAREDFILE_PSAM"
		    fi
		    if [ "$PS71ROLE_MSG_UWC_SERVER" = yes ]; then
		        rm -f "$SHAREDFILE_PSAM_UWC"
		    fi
		    if [ "$PS71ROLE_PSSERVER" = yes ]; then
		        rm -f "$SHAREDFILE_PSAM_PORTAL"
		    fi
		    exit 0
		    ;;
		    -h) do_help; exit 0;;
		    -n) CHECKONLY=$(($CHECKONLY+1))
		    CHECKONLY_WEB=$(($CHECKONLY_WEB+1))
		    CHECKONLY_STAT=$(($CHECKONLY_STAT+1))
		    ;;
		    -nw) CHECKONLY_WEB=$(($CHECKONLY_WEB+1)) ;;
		    -nf) CHECKONLY_STAT=$(($CHECKONLY_STAT+1)) ;;
		    -v) if [ $VERBOSE = -v ]; then
		        FREESPACE_PARAMS="$FREESPACE_PARAMS $1"
		    fi
		    VERBOSE=-v
		;;
		*) echo "Unknown param: $1" >&2;;
	esac
	shift
done

### Include this after config files, in case of RUNLEVEL_NOKICK mask override
RUN_CHECKLEVEL=""
[ -s "$COSAS_BINDIR/runlevel_check.include" ] &&
    . "$COSAS_BINDIR/runlevel_check.include" &&
    block_runlevel

if [ ! -x "$AGENT_FREESPACE" ]; then
        echo "Requires: agent-freespace '$AGENT_FREESPACE'" >&2
        exit 1
fi

[ x"$GDATE" = x ] && for F in $GDATE_LIST; do
        if [ -x "$F" ]; then
                GDATE="$F"
                break
        fi
done

if [ x"$GDATE" = x ]; then
        echo "Requires: GNU date, not found among '$GDATE_LIST'" >&2
        exit 1
fi

if [ ! -x "$GDATE" ]; then
        echo "Requires: GNU date ('$GDATE' not executable)" >&2
        exit 1
fi

TS_START="`TZ=UTC $GDATE +%s`"
if [ ! "$TS_START" -gt 0 ]; then
        echo "Requires: GNU date with +%s parameter ('$GDATE' not OK)" >&2
        exit 1
fi

[ "$DO_CHECK_AMSERVER" = no ] && DO_CHECK_AMSERVER=0
if [ "$DO_CHECK_AMSERVER" != 0 ]; then
    if [ ! -x "$CHECK_AMSERVER_ALIVE" ]; then
        echo "Requires: CHECK_AMSERVER_ALIVE = '$CHECK_AMSERVER_ALIVE'" >&2
        exit 1
    fi
fi

[ "$DO_CHECK_AMLOGIN" = no ] && DO_CHECK_AMLOGIN=0
if [ "$DO_CHECK_AMLOGIN" != 0 ]; then
    if [ ! -x "$CHECK_AMSERVER_LOGIN" ]; then
        echo "Requires: CHECK_AMSERVER_LOGIN = '$CHECK_AMSERVER_LOGIN'" >&2
        exit 1
    fi
fi

[ "$DO_CHECK_PORTAL" = no ] && DO_CHECK_PORTAL=0
if [ "$DO_CHECK_PORTAL" != 0 ]; then
    if [ ! -x "$CHECK_PORTAL_ALIVE" ]; then
        echo "Requires: CHECK_PORTAL_ALIVE = '$CHECK_PORTAL_ALIVE'" >&2
        exit 1
    fi
fi

[ "$DO_CHECK_WEBMAILUWC" = no ] && DO_CHECK_WEBMAILUWC=0
if [ "$DO_CHECK_WEBMAILUWC" != 0 ]; then
    if [ ! -x "$CHECK_WEBMAILUWC_ALIVE" ]; then
        echo "Requires: CHECK_WEBMAILUWC_ALIVE = '$CHECK_WEBMAILUWC_ALIVE'" >&2
        exit 1
    fi
fi

LOCK="$LOCK_BASE"

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

### Flag variable to check whether 'ls' supports precise timing
if [ x"$LSMODE" = x ]; then
    ls -duE / >/dev/null 2>&1 && LSMODE="ExtDate"
fi

### Define a few routines...

getMtime() {
        # Get modification (~creation) time of file,
        # this leads to its extreme age

        TZ=UTC $GDATE -r "$1" +%s
}

getAtime() {
        # Get access (last read) time of the file, this
        # leads to its usefulness to the admins/users.
        # Source value is updateable by 'touch -a FILE'

        # WARNING: -l gives a very approximate measurement
        # (minutes for a fresh file, days for old one)
        # and may lie about yesteryear files (no year marked
        # in ls output => gdate thinks it's a future date).
        # -E (if available in your ls), gives precise date-times

        if [ x"$LSMODE" = x"ExtDate" ]; then
                TZ=UTC $GDATE -d "$(TZ=UTC ls -duE "$1" | awk '{print $6" "$7" "$8 }' | sed 's/^\(.*\)\..*\( .*\)$/\1\2/' )" +%s
        else
                TZ=UTC $GDATE -d "$(TZ=UTC ls -dul "$1" | awk '{print $6" "$7" "$8 }')" +%s
        fi
}

### Do some work now

USE_SHAREDIR=yes
[ x"$SHAREDIR" = x ] && USE_SHAREDIR=no

if [ "$USE_SHAREDIR" = yes ]; then
    # Running the agent takes some time due to timeouts (min 5 sec of little work)
    # It ensures that working mountpoint is available and whether it needs cleanup
    [ "$VERBOSE" = -v ] && echo "=== Checking shared dir '$SHAREDIR' with agent-freespace"

    OUTPUT=` "$AGENT_FREESPACE" -t "$TIMEOUT" $FREESPACE_PARAMS "$SHAREDIR" 2>&1 `
    RESULT=$?
    [ "$VERBOSE" = -v ] && echo "===== result: $RESULT"

    case "$RESULT" in
        255|65535)
            echo "ERROR: Access to '$SHAREDIR' timed out." >&2
            USE_SHAREDIR=no
            ;;
        1)  echo "ERROR: failed to run agent-freespace (params)." >&2
            USE_SHAREDIR=no
            ;;
        2)  echo "ERROR: failed to run agent-freespace (mountpt). Aborting!" >&2
            USE_SHAREDIR=no
            ;;
    esac

    if [ "$USE_SHAREDIR" = yes -a ! -w "$SHAREDIR" ]; then
        echo "ERROR: write access to '$SHAREDIR' denied!" >&2
        USE_SHAREDIR=no
    fi

    if [ "$USE_SHAREDIR" = yes ]; then
        cd "$SHAREDIR"
        if [ $? != 0 ]; then
            echo "ERROR: Couldn't cd to shared dir '$SHAREDIR'" >&2
            USE_SHAREDIR=no
        fi
    fi
fi

if [ ! "$USE_SHAREDIR" = yes ]; then
    echo "INFO: can't acccess shared dir or it is misconfigured. I'll only try to check webservers then" >&2
fi

CHECKONLY_FLAG=""
[ "$CHECKONLY_WEB" != 0 ] && CHECKONLY_FLAG="-n"

if [ "$PS71ROLE_AMSERVER" = yes ]; then
    [ "$VERBOSE" = -v ] && echo "=== Running routines for AMSERVER"

    ### 1) Check if AMserver responds; restart if needed
    ### 2) Mark AMserver's webserver spawn time into shared file
    ###    (most recent sibling of webservd-wdog)

    if [ "$DO_CHECK_AMSERVER" != 0 ]; then
        [ "$VERBOSE" = -v ] && echo "=== Checking amserver_alive..."
        "$CHECK_AMSERVER_ALIVE" $CHECKONLY_FLAG $CHECK_AMSERVER_ALIVE_PARAMS 2>&1
    fi
    if [ "$DO_CHECK_AMLOGIN" != 0 ]; then
        [ "$VERBOSE" = -v ] && echo "=== Checking amserver_login..."
        "$CHECK_AMSERVER_LOGIN" $CHECKONLY_FLAG $CHECK_AMSERVER_LOGIN_PARAMS 2>&1
    fi

    if [ "$USE_SHAREDIR" = yes ]; then
        ### if we're here, webserver should be running (if we checked for it)
        ### and the shared dir is available
        ### if we potentially restarted the web server, sleep...
        [ $CHECKONLY_WEB = 0 ] && sleep 10

        ### Possibly grep for specific config file here - if several webservers
        ### are running
        PID_WDOG=` ps -ef | grep -w 'webservd-wdog' | egrep -v 'grep|admin-server' | awk '{ print $2 }' `
        PID_WSRV="NA"
        TS_PID="NA"
        TIME_PID="NA"
        TIME_PID_LOC="NA"

        if [ x"$PID_WDOG" = x ]; then
            echo "ERROR: webservd-wdog of amserver not found running!" >&2
            PID_WDOG="NA"
        else
            PID_WSRV=` "$PROCTREE" -P $PID_WDOG | grep 'webservd ' | head -1 | awk '{ print $2 }' `
            if [ $? != 0 -o x"$PID_WSRV" = x ]; then
                echo "ERROR: webservd of amserver not found running!" >&2
                PID_WSRV="NA"
            else
                TS_PID="`getMtime /proc/$PID_WSRV`"
                TIME_PID="`TZ=UTC $GDATE -d "1970-01-01 00:00:00 +0000 + $TS_PID sec"`"
                TIME_PID_LOC="`$GDATE -d "1970-01-01 00:00:00 +0000 + $TS_PID sec"`"
            fi
        fi

        echo "webservd of amserver:
PID_WDOG:	$PID_WDOG
PID_WSRV:	$PID_WSRV
start_TSUTC:	$TS_PID
start_UTC:	$TIME_PID
start_LOC:	$TIME_PID_LOC
" > "$SHAREDFILE_PSAM.tmp"

        if [ "$VERBOSE" = -v ]; then
            echo "===== current status:"
            cat "$SHAREDFILE_PSAM.tmp"
        fi

        if [ $? = 0 ]; then
            if [ -f "$SHAREDFILE_PSAM" ]; then
                diff "$SHAREDFILE_PSAM.tmp" "$SHAREDFILE_PSAM" >/dev/null 2>&1
                case $? in
                    0) # No differences were found
                        [ "$VERBOSE" = -v ] && echo "===== status: unchanged"
                        if [ "$CHECKONLY_STAT" = 0 ]; then
                            ### Stat file's date marks the last check time
                            touch "$SHAREDFILE_PSAM"
			    rm -f "$SHAREDFILE_PSAM.tmp"
			fi
			;;
		    1) # Differences were found
			### TODO: elaborate on rotation here...
		        if [ "$VERBOSE" = -v ]; then
			    echo "===== status: changed"
		    	    echo "===== prev status:"
			    cat "$SHAREDFILE_PSAM"
			fi	
			if [ "$CHECKONLY_STAT" = 0 ]; then
		    	    mv -f "$SHAREDFILE_PSAM" "$SHAREDFILE_PSAM.prev"
			    mv -f "$SHAREDFILE_PSAM.tmp" "$SHAREDFILE_PSAM"
		        fi
			;;
		    *) # An error occurred
			echo "ERROR: diff couldn't compare '$SHAREDFILE_PSAM.tmp' and '$SHAREDFILE_PSAM'" >&2
		        [ $CHECKONLY = 0 ] && rm -f "$LOCK"
			exit 4
		        ;;
	        esac
	    else
		[ "$VERBOSE" = -v ] && echo "===== status: new status file created, no previous data available"
	        if [ "$CHECKONLY_STAT" = 0 ]; then
	    	    mv -f "$SHAREDFILE_PSAM.tmp" "$SHAREDFILE_PSAM"
		fi
	    fi
        else
	    echo "ERROR: Can't write to $SHAREDFILE_PSAM.tmp" >&2
	    [ $CHECKONLY = 0 ] && rm -f "$LOCK"
	    exit 4
        fi
    fi
#// END OF 'PS71ROLE_AMSERVER = yes' logic
fi

if [ "$PS71ROLE_MSG_UWC_SERVER" = yes ]; then
    [ "$VERBOSE" = -v ] && echo "=== Running routines for Msg/UWC webserver"

    if [ "$USE_SHAREDIR" = yes ]; then
	if [ -f "$SHAREDFILE_PSAM" -a -f "$SHAREDFILE_PSAM_UWC" ]; then
	    diff "$SHAREDFILE_PSAM_UWC" "$SHAREDFILE_PSAM" >/dev/null 2>&1
	    case $? in
		0) # No differences were found
		    [ "$VERBOSE" = -v ] && echo "===== status: unchanged"
		    ;;
		1) # Differences were found
		    if [ "$VERBOSE" = -v ]; then
			echo "===== status: changed"
		    	echo "===== current status:"
			cat "$SHAREDFILE_PSAM"
		    	echo "===== prev status:"
			cat "$SHAREDFILE_PSAM_UWC"
		    fi

		    # restart webserver and update status file if:
		    # * this is not a checkonly test
		    # * this webserver is not the same as amserver
		    # ...
		    if [ "$CHECKONLY_WEB" = 0 ]; then
			if [ "$PS71ROLE_AMSERVER" != yes ]; then
			    "$PORTAL_SCRIPT" $PORTAL_SCRIPT_RESTART
			    sleep 10
			fi
			if [ "$CHECKONLY_STAT" = 0 ]; then
		    	    mv -f "$SHAREDFILE_PSAM_UWC" "$SHAREDFILE_PSAM_UWC.prev"
			    cp -p "$SHAREDFILE_PSAM" "$SHAREDFILE_PSAM_UWC"
			fi
		    fi
		    ;;
		*) # An error occurred
		    echo "ERROR: diff couldn't compare '$SHAREDFILE_PSAM_UWC' and '$SHAREDFILE_PSAM'" >&2
		    [ $CHECKONLY = 0 ] && rm -f "$LOCK"
		    exit 4
		    ;;
	    esac
	else
	    if [ -f "$SHAREDFILE_PSAM" -a ! -f "$SHAREDFILE_PSAM_UWC" ]; then
		[ "$VERBOSE" = -v ] && echo "===== status: new status file created, no previous data available"
	        if [ "$CHECKONLY_STAT" = 0 ]; then
		    cp -p "$SHAREDFILE_PSAM" "$SHAREDFILE_PSAM_UWC"
	        fi
	    fi
	fi
    fi

    if [ "$DO_CHECK_WEBMAILUWC" != 0 ]; then
	[ "$VERBOSE" = -v ] && echo "=== Checking WebmailUWC_alive..."
	"$CHECK_WEBMAILUWC_ALIVE" $CHECKONLY_FLAG $CHECK_WEBMAILUWC_ALIVE_PARAMS 2>&1
    fi

#// END OF 'PS71ROLE_MSG_UWC_SERVER = yes' logic
fi

if [ "$PS71ROLE_PSSERVER" = yes ]; then
    [ "$VERBOSE" = -v ] && echo "=== Running routines for PSSERVER"

    if [ "$USE_SHAREDIR" = yes ]; then
	if [ -f "$SHAREDFILE_PSAM" -a -f "$SHAREDFILE_PSAM_PORTAL" ]; then
	    diff "$SHAREDFILE_PSAM_PORTAL" "$SHAREDFILE_PSAM" >/dev/null 2>&1
	    case $? in
		0) # No differences were found
		    [ "$VERBOSE" = -v ] && echo "===== status: unchanged"
		    ;;
		1) # Differences were found
		    if [ "$VERBOSE" = -v ]; then
			echo "===== status: changed"
		    	echo "===== current status:"
			cat "$SHAREDFILE_PSAM"
		    	echo "===== prev status:"
			cat "$SHAREDFILE_PSAM_PORTAL"
		    fi

		    # restart webserver and update status file if:
		    # * this is not a checkonly test
		    # * this webserver is not the same as amserver
		    # ...
		    if [ "$CHECKONLY_WEB" = 0 ]; then
			if [ "$PS71ROLE_AMSERVER" != yes ]; then
			    "$PORTAL_SCRIPT" $PORTAL_SCRIPT_RESTART
			    sleep 10
			fi
			if [ "$CHECKONLY_STAT" = 0 ]; then
		    	    mv -f "$SHAREDFILE_PSAM_PORTAL" "$SHAREDFILE_PSAM_PORTAL.prev"
			    cp -p "$SHAREDFILE_PSAM" "$SHAREDFILE_PSAM_PORTAL"
			fi
		    fi
		    ;;
		*) # An error occurred
		    echo "ERROR: diff couldn't compare '$SHAREDFILE_PSAM_PORTAL' and '$SHAREDFILE_PSAM'" >&2
		    [ $CHECKONLY = 0 ] && rm -f "$LOCK"
		    exit 4
		    ;;
	    esac
	else
	    if [ -f "$SHAREDFILE_PSAM" -a ! -f "$SHAREDFILE_PSAM_PORTAL" ]; then
		[ "$VERBOSE" = -v ] && echo "===== status: new status file created, no previous data available"
	        if [ "$CHECKONLY_STAT" = 0 ]; then
		    cp -p "$SHAREDFILE_PSAM" "$SHAREDFILE_PSAM_PORTAL"
	        fi
	    fi
	fi
    fi


    if [ "$DO_CHECK_PORTAL" != 0 ]; then
	[ "$VERBOSE" = -v ] && echo "=== Checking Portal_alive..."
	"$CHECK_PORTAL_ALIVE" $CHECKONLY_FLAG $CHECK_PORTAL_ALIVE_PARAMS 2>&1
    fi

#// END OF 'PS71ROLE_PSSERVER = yes' logic
fi

### Be nice, clean up
[ $CHECKONLY = 0 ] && rm -f "$LOCK"

exit 0

