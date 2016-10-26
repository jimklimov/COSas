#!/bin/bash

# agent-web-portalOra.sh
# agent-web-amloginHost.sh merged with agent-web-amlogin.sh
# (C) Nov 2005-May 2015 by Jim Klimov, COS&HT
# $Id: agent-web-portalOra.sh,v 1.20 2015/05/15 08:09:57 jim Exp $

# Usage: agent-web-portalOra.sh [-t timeout] [-l minlines] [-V] [-r|+r] [-u URL] [-P POSTDATA] [-H] [host [port]]
# Usage: agent-web-amloginHost.sh [-t timeout] [-V] [-r|+r] [-u URL] [-P POSTDATA] [host [port]]

# This script probes the specified host and optional port (if not 80)
# to fetch an URL (default: '/portal/dt') or an Access Manager/OpenSSO
# Login URL with a test user login name and password and see if there's
# any reply in a reasonable time.
### agent-web-portalOra.sh: The response text is parsed to check for HTTP
# error states or known error reports of the site engine (JDBC errors,
# stack traces, whatever) or ABSENCE of required text in HTML markup.
### agent-web-amlogin*.sh: The response text is parsed to see if there
# is any Access Manager/OpenSSO login failure
# agent-web-amlogin.sh differs from agent-web-amloginHost.sh only in that
# the script agent-web-amloginHost.sh also requests "Host: host:port" line

# NOTE that the name is historical, and the script is not limited to
# Sun Portal servers nor Oracle/Fatwire stack-traces if configured
# to check some other web-site template via config files.

AGENTNAME="`basename "$0"`"

### Lines caught by this regexp always cause reporting of error:
[ x"$ERRORREGEXINSTANT" = x ] && ERRORREGEXINSTANT='^HTTP\/1\..*(50|40)'

### These strings must exist in output (if var is not empty or dash '-')
### And how many lines (minumum) should be matched?
[ x"$ERRORREGEXINSTANT_ABSENT_THRESHOLD" = x ] && ERRORREGEXINSTANT_ABSENT_THRESHOLD=1
[ x"$ERRORREGEXINSTANT_ABSENT" = x ] && ERRORREGEXINSTANT_ABSENT='<[ 	]*/[ 	]*[hH][tT][mM][lL][ 	]*>'

### Also support redirects as a not-error (server responds)
### Following redirected URLs is not (yet) implemented, might be a flag...
[ x"$REDIRECTREGEX" = x ] && REDIRECTREGEX='^(HTTP\/1\..* 30|Location: )'
[ x"$REDIRECT_MINLINES" = x ] && REDIRECT_MINLINES=2
[ x"$REDIRECT_IS_OK" = x ] && REDIRECT_IS_OK=yes

### How many lines should be in output file, including
### HTTP response header, empty line and output?
[ x"$MINLINES" = x ] && MINLINES=3

### Custom settings for symlinked scripts
case "$AGENTNAME" in
    *portalOra*)
	AGENTDESC="Try to access and probe a webserver (check returned data for Oracle/FatWire errors by default)"
	### Portal desktop URL
	#TESTURL='/portal/dt?provider=HMAOFirstPageContainer'
	[ x"$TESTURL" = x ] && TESTURL='/portal/dt'

	### Where to dump the desktop output
	[ x"$TEMPFILE" = x ] && TEMPFILE=/tmp/portalOra.test.html

	### Regexp characteristic of the error
	### Simply "error" may be bad - if this word CAN be found in
	### the content of the checked page
	#[ x"$ERRORREGEX" = x ] && ERRORREGEX='error|An error occurred during processing. Check the info log\.'
	[ x"$ERRORREGEX" = x ] && ERRORREGEX='error'

	### How many matches of regex sign the error?
	ERRORTHRESHOLD=3

	REDIRECT_IS_OK=no
	;;
    *amlogin*|*sso*)
	AGENTDESC="Try to access and probe a webserver (check returned data for AM Login errors)"
	### Example AMServer/OpenSSO login URLs including login and password
	[ x"$TESTURL" = x ] && case "$AGENTNAME" in
	    *amlogin*)	TESTURL='/amserver/UI/Login?module=LDAP&org=orgalias&IDToken1=testname&IDToken2=testpass' ;;
	    *sso*)	TESTURL='/amserver/UI/Login?module=LDAP&IDToken1=testname&IDToken2=testpass' ;;
	esac
	### Where to dump the desktop output
	[ x"$TEMPFILE" = x ] && TEMPFILE=/tmp/amlogin.test.html

	### In case of Access Manager, errors include showing the login page
	### again after providing correct credentials
	[ x"$ERRORREGEX" = x ] && ERRORREGEX='error|Authentication failed|Return to Login page|This server uses LDAP Authentication'

	### How many matches of regex sign the error?
	ERRORTHRESHOLD=1

	### HTML markup is not required for AM redirect replies
	ERRORREGEXINSTANT_ABSENT="-"
	ERRORREGEXINSTANT_ABSENT_THRESHOLD=0

	### Successful login redirects to the landing paeg
	REDIRECT_IS_OK=yes
	;;
    *)
	AGENTDESC="Try to access and probe a webserver and check returned markup for errors by user-configured template"
	[ x"$TESTURL" = x ] && TESTURL='/'
	[ x"$TEMPFILE" = x ] && TEMPFILE="/tmp/webcheck-$AGENTNAME.test.html"
	[ x"$ERRORREGEX" = x ] && ERRORREGEX='error'
	ERRORTHRESHOLD=3
	;;
esac
[ x"$ERRORREGEXINSTANT_ABSENT" = x- ] && ERRORREGEXINSTANT_ABSENT=''

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
	COSAS_BINDIR=`pwd`
fi
TCPTIMERUN="$COSAS_BINDIR/agent-tcpip.sh"
TCPTIMEOUT=20

[ x"$VERBOSE_OUT" = x ] && VERBOSE_OUT=0
[ x"$HTTP_METHOD" = x ] && HTTP_METHOD=GET
CONNHOST="127.0.0.1"
CONNPORT="80"
HDR_HOST_NAME=""
[ x"$HDR_HOST" = x ] && case "$AGENTNAME" in
    *amloginHost*|*sso*Host*)	HDR_HOST=yes ;;
    *amlogin*|*sso*)		HDR_HOST=no ;;
    *portalOra*)		HDR_HOST=no ;;
    *)				HDR_HOST=no ;;
esac

# Source optional config files
[ x"$COSAS_CFGDIR" = x ] && COSAS_CFGDIR="$COSAS_BINDIR/../etc"
if [ -d "$COSAS_CFGDIR" ]; then
    [  -f "$COSAS_CFGDIR/COSas.conf" ] && \
        . "$COSAS_CFGDIR/COSas.conf"
    [  -f "$COSAS_CFGDIR/`basename "$0"`.conf" ] && \
        . "$COSAS_CFGDIR/`basename "$0"`.conf"
fi

### Historical backward compatibility - overrides default presets
[ x"$PSDESKTOP" != x ] && TESTURL="$PSDESKTOP"
[ x"$PSDESKTOPURL" != x ] && TESTURL="$PSDESKTOPURL"

do_help() {
        echo "Utility:  $AGENTNAME"
        echo "  $AGENTDESC"

        echo "Usage: $0 [-t timeout] [-l minlines] [-V] [-r|+r] [-u URL] [-P POSTDATA] [-H|-Hn hostname] [host [port]]"
        echo "Defaults: timeout=$TCPTIMEOUT, host=$CONNHOST, port=$CONNPORT, URL='$TESTURL', Host:header: '$HDR_HOST_NAME' ($HDR_HOST)"
}
				
while [ $# -gt 0 ]; do
        case "$1" in
                -h) do_help; exit 0;;
		-H) HDR_HOST=yes;;
		-Hn) HDR_HOST_NAME="$2"; HDR_HOST=yes; shift 1;;
		-r) REDIRECT_IS_OK=no ;;
		+r) REDIRECT_IS_OK=yes ;;
		-V) VERBOSE_OUT=1 ;;
		-u)
                        shift 1
			TESTURL="$1"
			;;
		-P) HTTP_METHOD=POST; HTTP_POSTDATA="$2"; shift 1;;
                -t)
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
		-l)
                        shift 1
                        OK=no
                        if [ x"$1" != x ]; then
                                if [ "$1" -gt 0 ]; then
                                        MINLINES="$1"
                                        OK=yes
                                fi
                        fi
                        if [ $OK = no ]; then
                                echo "Wrong minlines, using default" >&2
                        fi
                        ;;
                *) case $# in
                        1)
                           GOTWORK=1
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
[ "$HDR_HOST" = yes -a x"$HDR_HOST_NAME" = x ] && HDR_HOST_NAME="$CONNHOST"

if [ ! -x "$TCPTIMERUN" ]; then
	echo "Requires: tcptimerun '$TCPTIMERUN'" >&2
	exit 1
fi

( echo "$HTTP_METHOD $TESTURL HTTP/1.0"
  [ "$HDR_HOST" = yes ] && echo "Host: $HDR_HOST_NAME:$CONNPORT"
  echo ''
  [ x"$HTTP_POSTDATA" != x -a x"$HTTP_METHOD" = xPOST ] && echo "$HTTP_POSTDATA" ) | \
    "$TCPTIMERUN" "$TCPTIMEOUT" "$CONNHOST" "$CONNPORT" > "$TEMPFILE"

RESULT=$?

if [ ! -s "$TEMPFILE" ]; then
        echo "Status:   EMPTYREPLY" >&2
        RESULT=10
	exit "$RESULT"
fi

[ "$VERBOSE_OUT" = 1 ] && cat "$TEMPFILE"

if [ "$MINLINES" -ge 1 ]; then
        NUMLINES="`cat "$TEMPFILE" | wc -l | sed 's/ //g'`"
	if [ "$NUMLINES" -lt "$MINLINES" ]; then
    	    echo "Status:   SHORTREPLY" >&2
    		RESULT=10
		exit "$RESULT"
        fi
fi

if [ $RESULT != 0 ]; then
	echo "Status:	FAILED" >&2
else
	### Test for redirects first
	if [ x"$REDIRECTREGEX" != x -a \
	     x"$REDIRECTREGEX" != x- -a \
	      "$REDIRECT_MINLINES" -gt 0 ]; then
	    A=`egrep -c "$REDIRECTREGEX" "$TEMPFILE"`
	    if [ "$A" -ge "$REDIRECT_MINLINES" ]; then
		### TODO: Flag to follow redirects?
		if [ x"$REDIRECT_IS_OK" = xyes ]; then
			echo "Status:   OK_REDIRECTED" >&2
			RESULT=0
			exit $RESULT
		else
			echo "Status:   FAIL_REDIRECTED" >&2
			RESULT=2
			exit $RESULT
		fi
	    fi
	fi

	if [ x"$ERRORREGEXINSTANT_ABSENT" != x -a \
	     x"$ERRORREGEXINSTANT_ABSENT" != x- -a \
	      "$ERRORREGEXINSTANT_ABSENT_THRESHOLD" -gt 0 ]; then
	    A=`egrep -c "$ERRORREGEXINSTANT_ABSENT" "$TEMPFILE"`
	    if [ "$A" -lt "$ERRORREGEXINSTANT_ABSENT_THRESHOLD" ]; then
		case "$AGENTNAME" in
	          *amlogin*|*sso*)	echo "Status:   AMLOGINFAILED" >&2 ;;
		  *)			echo "Status:   ORACLEFAILED" >&2 ;;
		esac
		RESULT=2
	    fi
	fi

	if [ x"$RESULT" = x0 ]; then
	    N=`egrep -c "$ERRORREGEX" "$TEMPFILE"`
	    M=`egrep -c "$ERRORREGEXINSTANT" "$TEMPFILE"`

	    if [ "$N" -gt "$ERRORTHRESHOLD" -o "$M" -gt 0 ]; then
		case "$AGENTNAME" in
	          *amlogin*|*sso*)	echo "Status:   AMLOGINFAILED" >&2 ;;
		  *)			echo "Status:   ORACLEFAILED" >&2 ;;
		esac
		RESULT=2
	    else
		echo "Status:	OK" >&2
	    fi
	fi
fi

exit "$RESULT"
