#!/bin/bash

# agent-web.sh
# (C) Nov 2005-May 2015 by Jim Klimov, COS&HT
# $Id: agent-web.sh,v 1.18 2015/05/15 08:09:57 jim Exp $

# Usage: agent-web [-t timeout] [-V] [-u url] [-P POSTDATA] [-H|-Hn hostname] [host [port]]

# This script probes the specified host and optional port (if not 80)
# to see if there's any reply in a reasonable time
# Nominally accepts parameters for URL and Host: header, but the
# response text is not checked. ANY successful connection is a SUCCESS.
# Use -V to output the (HTTP) response to stdout.
# NOTE: default host is 127.0.0.1, even if "-Hn hostname" is used!

AGENTNAME="`basename "$0"`"
AGENTDESC="Try to access and probe a webserver (don't check returned data)"

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
	COSAS_BINDIR=`pwd`
fi
TCPTIMERUN="$COSAS_BINDIR/agent-tcpip.sh"

### Sample Portal desktop URLs
#TESTURL='/portal/dt?provider=HMAOFirstPageContainer'
#TESTURL='/amserver/isAlive.jsp'
#TESTURL='/alfresco'
#TESTURL='/cs'
#TESTURL='/cda'
#TESTURL='/cma'

case "$0" in
    *agent-web-portal*)
	TESTURL='/portal/dt'
	TCPTIMEOUT=20
	;;
    *)
	TESTURL='/'
	TCPTIMEOUT=10
	;;
esac

test_vars() {
	[ x"$CONNHOST" = x ] && CONNHOST=127.0.0.1
	[ x"$CONNPORT" = x ] && CONNPORT=80
	[ x"$HDR_HOST" != xyes ] && HDR_HOST=no
	[ "$HDR_HOST" = yes -a x"$HDR_HOST_NAME" = x ] && HDR_HOST_NAME="$CONNHOST"
}

do_help() {
        echo "Utility:  $AGENTNAME"                
        echo "  $AGENTDESC"

        echo "Usage: $0 [-t timeout] [-V] [-u url] [-P POSTDATA] [-H|-Hn hostname] [host [port]]"

	test_vars
        echo "Defaults: timeout=$TCPTIMEOUT, host=$CONNHOST, port=$CONNPORT, URL='$TESTURL', hostname='$HDR_HOST_NAME' ($HDR_HOST)"
	echo "Use -V to dump the server's reply to stdout"
}

### No defaults for CONNHOST and CONNPORT, defined below if needed
[ x"$VERBOSE_OUT" = x ] && VERBOSE_OUT=0
[ x"$HTTP_METHOD" = x ] && HTTP_METHOD=GET
HDR_HOST=no
HDR_HOST_NAME=""

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

while [ $# -gt 0 ]; do
        case "$1" in
                -h) do_help; exit 0;;
		-H) HDR_HOST=yes;;
		-Hn) HDR_HOST_NAME="$2"; HDR_HOST=yes; shift 1;;
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
                -u)
                        shift
                        TESTURL="$1"
                        ;;
		-P) HTTP_METHOD=POST; HTTP_POSTDATA="$2"; shift 1;;
		-V)
			VERBOSE_OUT=1
			;;
                *) case $# in
                        1)
                                if [ x"$CONNHOST" = x ]; then
                                        CONNHOST="$1"
                                else
                                        CONNPORT="$1"
                                fi
                                ;;
                        2) CONNHOST="$1"; CONNPORT="$2"; shift 1;;
                        *) do_help >&2; exit 1;;
                esac ;;
        esac
        shift
done

test_vars

if [ ! -x "$TCPTIMERUN" ]; then
	echo "Requires: tcptimerun '$TCPTIMERUN'" >&2
	exit 1
fi

[ "$VERBOSE_OUT" = 0 ] && exec > /dev/null
( echo "GET $TESTURL HTTP/1.0"
  [ "$HDR_HOST" = yes ] && echo "Host: $HDR_HOST_NAME:$CONNPORT"
  echo '' ) | "$TCPTIMERUN" "$TCPTIMEOUT" "$CONNHOST" "$CONNPORT"
RESULT=$?

if [ "$RESULT" != 0 ]; then
	echo "Status:	FAILED" >&2
else
	echo "Status:	OK" >&2
fi

exit "$RESULT"
