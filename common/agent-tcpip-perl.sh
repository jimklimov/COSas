#!/bin/bash

# agent-tcpip-perl.sh
# (C) Nov 2005-Dec 2008 by Jim Klimov, COS&HT
# $Id: agent-tcpip-perl.sh,v 1.15 2015/05/15 08:09:57 jim Exp $
# (C) 2005-2015 by Jim Klimov, COS&HT revisited for portability (v1.10+)

# Usage: agent-tcpip timeout host port 
# This script probes the specified host with data received from stdin
# and directs server's reply to stdout. The test is done by telnet.
# It may take the server some time to reply, while telnet closes after
# its piped stdin completes. Maybe will rely on netcat or a perl script
# later... So far only may be good with text-based servers.

# This variant parses telnet's output thru perl instead of multiple greps
# per line and should be a lot faster.

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

export LOCK

### This requires an stdin, even if empty like this:
###   echo "" | agent-tcpip.sh
( cat
C=0
while [ $C -lt "$TIMEOUT" ]; do
	sleep 1
	if [ -f "$LOCK" ]; then 
		echo "ACK" > "$LOCK"
		exit 0
	fi
	C=$(($C+1))
done
# echo "$$ Timed out!" >&2
TELPID=`ps -ef | grep -w 'telnet' | grep -w $$ | grep -v grep | awk '{ print $2 }' `
[ x"$TELPID" != x ] && kill -2 "$TELPID" ) | telnet "$CONNHOST" "$CONNPORT" 2>&1 | \
  egrep -v '^(Connected to|Escape character is|Trying) ' | \
  perl -e '
	$LOCK=$ENV{LOCK};
	print STDERR "=== LOCKFILE: $LOCK\n" ;

	while ( <STDIN> ) {
		chomp $_;

		### Enforce chomping of partial CR/LF components
		### Workaround linux telnet
		s/^(.*[^\r\n])[\r\n]+$/$1/;

		### Debug
		#print STDERR "=== [$_]\n";

		if ( $_ eq "telnet: Unable to connect to remote host: Connection refused" ||
		      /^telnet: connect to address .*: Connection refused$/ ) {
			print STDERR ">>> Connection REFUSED\n";
			`touch "$LOCK"` ;
			exit 32;
		} elsif ( $_ eq "telnet: Unable to connect to remote host: Connection timed out" ) {
			print STDERR ">>> Connection REFUSED: Timed out\n";
			`touch "$LOCK"` ;
			exit 33;
		} elsif ( /: Unknown host|: node name or service name not known/ ) {
			print STDERR ">>> Connection REFUSED: Unknown host\n";
			`touch "$LOCK"` ;
			exit 34;
		} elsif ( $_ eq "telnet: Unable to connect to remote host: Network is unreachable" ) {
			print STDERR ">>> Connection REFUSED: Network is unreachable\n";
			`touch "$LOCK"` ;
			exit 35;
		} elsif ( $_ eq  "telnet: Unable to connect to remote host: No route to host" ||
		      /^telnet: connect to address .*: No route to host$/ ) {
			print STDERR ">>> Connection REFUSED: No route to host\n";
			`touch "$LOCK"` ;
			exit 36;
		} elsif ( /^(.*)Connection to .+ closed by foreign host\.?$/ ||
			  /^(.*)Connection closed by foreign host\.?$/
			) {
			### Last line may have been glued with telnets goodbye...
			print "$1\n";
			print STDERR ">>> Connection CLOSED\n";
			`touch "$LOCK"` ;
			exit 0;
		}
		print "$_\n";
	}
	print STDERR ">>> Connection FINISHED, status unknown to agent/not detected\nLast line was:\n'$_'\n";
	`touch "$LOCK"` ;
	exit 0;
' > "$LOCK.reply"

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
