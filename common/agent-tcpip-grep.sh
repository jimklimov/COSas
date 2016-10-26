#!/bin/bash

# agent-tcpip-grep.sh
# (C) Nov 2005-Dec 2008 by Jim Klimov, COS&HT
# (C) 2005-2015 by Jim Klimov, COS&HT revisited for portability (v1.9+)
# $Id: agent-tcpip-grep.sh,v 1.13 2015/05/15 08:09:57 jim Exp $

# Usage: agent-tcpip timeout host port 
# This script probes the specified host with data received from stdin
# and directs server's reply to stdout. The test is done by telnet.
# It may take the server some time to reply, while telnet closes after
# its piped stdin completes. Maybe will rely on netcat or a perl script
# later... So far only may be good with text-based servers.

# This variant parses telnet's output thru multiple greps per line and
# should be quite slow, but portable.

AGENTNAME="`basename "$0"`"
AGENTDESC="Try to access and probe a tcp/ip server (don't check returned data)"

if [ "$1" = -h ]; then
	echo "Agent:	$AGENTNAME"
	echo "	$AGENTDESC"

	echo "Usage: echo REQUEST | $0 timeout host port | read REPLY"
	echo "	timeout	how many sec can we wait"
	echo "	host	hostname or IP good for telnet"
	echo "	port	TCP port"
	exit 0
fi

if [ $# != 3 -o "$1" = -h ]; then
	echo "Usage: $0 timeout host port" >&2
	exit 1
fi

TIMEOUT="$1"
CONNHOST="$2"
CONNPORT="$3"

if [ "$TIMEOUT" -lt 1 ]; then
	echo "timeout too small [$TIMEOUT]" >&2
	exit 1
fi

if [ "$CONNPORT" -lt 1 -o "$CONNPORT" -gt 65535 ]; then
	echo "port out of range [$CONNPORT]" >&2
	exit 1
fi

LOCK="/tmp/$AGENTNAME.$$.lock"

rm -f "$LOCK"

echo "=== LOCKFILE: $LOCK" >&2

### This requires an stdin, even if empty like this:
###   echo "" | agent-tcpip.sh
( cat
C=0
while [ $C -lt "$TIMEOUT" ]; do
	sleep 1
	if [ -f "$LOCK" ]; then 
		echo "ACK" > "$LOCK"
		exit
	fi
	C=$(($C+1))
done
# echo "$$ Timed out!" >&2
TELPID=`ps -ef | grep -w 'telnet' | grep -w $$ | grep -v grep | awk '{ print $2 }' `
[ x"$TELPID" != x ] && kill -2 "$TELPID" ) | telnet "$CONNHOST" "$CONNPORT" 2>&1 \
  | egrep -v '^(Connected to|Escape character is|Trying) ' \
  | ( while IFS= read LINE; do
	### Enforce chomping of partial CR/LF components
	### Workaround linux telnet
	LINE="`echo "$LINE" | sed 's/^\(.*[^\r\n]\)[\r\n]*$/\1/'`"

	### Debug
	#echo "===[$LINE]" >&2

	if echo "$LINE" | fgrep 'telnet: Unable to connect to remote host: Connection refused' > /dev/null; then
		echo ">>> Connection REFUSED" >&2
		touch "$LOCK"
		exit 32
	fi
	if echo "$LINE" | egrep '^telnet: connect to address .*: Connection refused$' > /dev/null; then 
		echo ">>> Connection REFUSED" >&2
		touch "$LOCK"
		exit 32
	fi
	if echo "$LINE" | fgrep 'telnet: Unable to connect to remote host: Connection timed out' > /dev/null; then
		echo ">>> Connection REFUSED: Timed out" >&2
		touch "$LOCK"
		exit 33
	fi
	if echo "$LINE" | fgrep ': Unknown host' > /dev/null; then
		echo ">>> Connection REFUSED: Unknown host" >&2
		touch "$LOCK"
		exit 34
	fi
	if echo "$LINE" | fgrep ': node name or service name not known' > /dev/null; then
		echo ">>> Connection REFUSED: Unknown host" >&2
		touch "$LOCK"
		exit 34
	fi
	if echo "$LINE" | fgrep 'telnet: Unable to connect to remote host: Network is unreachable' > /dev/null; then
		echo ">>> Connection REFUSED: Network is unreachable" >&2
		touch "$LOCK"
		exit 35
	fi
	if echo "$LINE" | fgrep 'telnet: Unable to connect to remote host: No route to host' > /dev/null; then
		echo ">>> Connection REFUSED: No route to host" >&2
		touch "$LOCK"
		exit 36
	fi
	if echo "$LINE" | egrep '^telnet: connect to address .*: No route to host$' > /dev/null; then
		echo ">>> Connection REFUSED: No route to host" >&2
		touch "$LOCK"
		exit 36
	fi
	if echo "$LINE" | egrep 'Connection to .+ closed by foreign host\.$' > /dev/null; then
		### Last line may have been glued with telnet's goodbye...
		echo "$LINE" | sed 's/^\(.*\)Connection to .+ closed by foreign host\.$/\1/'
		echo ">>> Connection CLOSED" >&2
		touch "$LOCK"
		exit 0
	fi
	if echo "$LINE" | egrep 'Connection closed by foreign host\.?$' > /dev/null; then
		echo "$LINE" | sed 's/^\(.*\)Connection closed by foreign host\.?$/\1/'
		echo ">>> Connection CLOSED" >&2
		touch "$LOCK"
		exit 0
	fi
#        echo "$LINE" >&3
	echo "$LINE"
# done 3>&1
  done

  echo ">>> Connection FINISHED, status unknown to agent/not detected
Last line was:
'$LINE'" >&2
  touch "$LOCK"
  exit 0
  ) >"$LOCK.reply"

RESULT=$?
NL=-1
[ -s "$LOCK.reply" ] && NL=`wc -l "$LOCK.reply" | awk '{ print $1 }'`

### File appears only if the conection was detected as closed (or unestablished)
### It is not empty only if the STDIN waiter also detected it while it was alive
if [ ! -s "$LOCK" ]; then
	if [ $NL -gt -1 ]; then
        	echo ">>> Request ok, reply timeout exceeded, received $NL lines overall" >&2
        	RESULT=0
	else
		echo ">>> Request timed out" >&2
		RESULT=-1
	fi
fi

[ -s "$LOCK.reply" ] && cat "$LOCK.reply"

rm -f "$LOCK" "$LOCK.reply"

exit "$RESULT"
