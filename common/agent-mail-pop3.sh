#!/bin/bash

# agent-mail-pop3.sh
# (C) Jun 2008-Dec 2010 by Jim Klimov, COS&HT
# $Id: agent-mail-pop3.sh,v 1.5 2015/05/15 08:09:57 jim Exp $

# Usage: agent-mail-pop3 [-t timeout] [host [port]]

# This script probes the specified host and optional port (if not 110)
# to see if there's any reply in a reasonable time

AGENTNAME="`basename "$0"`"
AGENTDESC="Try to access and probe a mailserver (don't check returned data)"

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
	COSAS_BINDIR=`pwd`
fi
TCPTIMERUN="$COSAS_BINDIR/agent-tcpip.sh"
TCPTIMEOUT=10

DEBUG=0

### NOTE: Do not set CONNHOST and CONNPORT here, their emptiness is required for
### CLI parameter parsing

do_help() {
        echo "Utility:  $AGENTNAME"
        echo "  $AGENTDESC"

        echo "Usage: $0 [-t timeout] [host [port]]"
        echo "Defaults: timeout=$TCPTIMEOUT, host=$CONNHOST, port=$CONNPORT"
}

# Source optional config files
[ x"$COSAS_CFGDIR" = x ] && COSAS_CFGDIR="$COSAS_BINDIR/../etc"
if [ -d "$COSAS_CFGDIR" ]; then
    [  -f "$COSAS_CFGDIR/COSas.conf" ] && \
        . "$COSAS_CFGDIR/COSas.conf"
    [  -f "$COSAS_CFGDIR/`basename "$0"`.conf" ] && \
        . "$COSAS_CFGDIR/`basename "$0"`.conf"
fi

while [ $# -gt 0 ]; do
        case "$1" in
                -h) do_help; exit 0;;
		-d) DEBUG=1;;
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
[ x"$CONNPORT" = x ] && CONNPORT=110

if [ ! -x "$TCPTIMERUN" ]; then
	echo "Requires: tcptimerun '$TCPTIMERUN'" >&2
	exit 1
fi

OUTPUT=`( echo 'QUIT' ) | "$TCPTIMERUN" "$TCPTIMEOUT" "$CONNHOST" "$CONNPORT"`
RESULT=$?

if [ $RESULT != 0 ]; then
	echo "Connection Status:	FAILED" >&2
else
	echo "Connection Status:	OK" >&2

	POP3_GREETING=no
	POP3_CLOSING=no

	# Check for POP3 in greeting
	if echo "$OUTPUT" | egrep -i '^\+OK .*POP3.*$' > /dev/null; then
		POP3_GREETING=yes
		echo "check_pop3_greeting:	OK" >&2
	else
		echo "check_pop3_greeting:	FAILED" >&2
		RESULT=2
	fi

	# Check for POP3 closing phrase
	if echo "$OUTPUT" | egrep -i '^\+OK .*closing connection.*$|^\+OK +Sayonara$|^\+OK .*[bB]ye.*' > /dev/null; then
		POP3_CLOSING=yes
		echo "check_pop3_closing:	OK" >&2
	else
		echo "check_pop3_closing:	FAILED (not fatal)" >&2
#		RESULT=2
	fi
fi

if [ $RESULT != 0 ]; then
	echo "Status:	FAILED" >&2
else
	echo "Status:	OK" >&2
fi

if [ x"$DEBUG" = x1 ]; then
    echo ">>> Client Output:
QUIT"
    echo "<<< Server Output:
$OUTPUT"
fi

exit "$RESULT"
