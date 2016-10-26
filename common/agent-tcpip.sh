#!/bin/bash

# agent-tcpip.sh
# (C) Nov 2005-Dec 2010 Jim Klimov
# $Id: agent-tcpip.sh,v 1.3 2010/11/15 14:32:11 jim Exp $

# Usage: agent-tcpip timeout host port 

# This script is a dispatcher for agent-tcpip-perl.sh or agent-tcpip-grep.sh 
# versions. See them for more authoritative descriptions.

AGENTNAME="`basename "$0"`"
AGENTDESC="Try to access and probe a tcp/ip server (don't check returned data)"

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
	COSAS_BINDIR=`pwd`
fi
TCPTIMERUN_GREP="$COSAS_BINDIR/agent-tcpip-grep.sh"
TCPTIMERUN_PERL="$COSAS_BINDIR/agent-tcpip-perl.sh"

if [ -x /usr/bin/perl -a -x "$TCPTIMERUN_PERL" ]; then
	# This is faster
	"$TCPTIMERUN_PERL" $@
	exit $?
fi

if [ -x "$TCPTIMERUN_GREP" ]; then
	# This only needs grep
	"$TCPTIMERUN_GREP" $@
	exit $?
fi

echo "Requires ($TCPTIMERUN_GREP) or (PERL and $TCPTIMERUN_PERL)" >&2
exit 1
