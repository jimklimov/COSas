#!/bin/bash

# timerun.sh
# (C) Nov 2005 by Jim Klimov
# (C) 2010 by Jim Klimov, COS&HT revisited for portability (v1.3+)
# (C) 2013 by Jim Klimov, COS&HT revisited for parameters with spaces (v1.6+)
# $Id: timerun.sh,v 1.6 2013/06/05 16:06:08 jim Exp $

# Usage: timerun timeout cmd params
# This script runs the specified process and kills it
# if it does not complete within specified timeout
# returns error -1 in this case and writes to stderr, 
# otherwise returns whatever the process returned

# Should be useful in agents to freezing processes
# like checking a dead webserver or NFS share
# Induces about 1 second lag for quickly-completing
# processes.

# Important that this it runs an actual resource-accessing
# process binary, not a subshell! We usually kill it 
# directly with -9, cause -2 fails (waits too long)...
# If this is a top of a multiprocess tree, subprocesses
# remain without their leader (not so if proctree script
# is found and used)...

# Optional - script which kills a tree of processes
# It's "a bit" slow (may work for 1-2 seconds for a
# tree of 5-10 processes) and may fail to kill already
# dead processes. But it works. :)
# May also fail if chaining timerun's (deep spawned
# processes may have PPID==1)
COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
	COSAS_BINDIR=`pwd`
fi
PROCTREE="$COSAS_BINDIR/proctree.sh"

if [ $# -lt 2 ]; then
	echo "Usage: $0 timeout cmd [params]"
	exit -2
fi

TIMEOUT="$1"
shift

if [ "$TIMEOUT" -le 0 ]; then
	echo "Usage: $0 timeout cmd [params]"
	exit -2
fi

### For diags output
CMD="$1"
CMDLINE="$*"

### Kills either the master process or the tree of its siblings
do_kill() {
	VICTIMPID="$1"

	if [ -x "$PROCTREE" ]; then
		CHILDREN=`ps -ef | grep "$CMD" | grep -v grep | awk '{print $3}' | grep -w "$VICTIMPID"`

		### A script can do "exec" and its CMD name changes
		[ x"$CHILDREN" = x ] && CHILDREN=`ps -ef | grep -v grep | awk '{print $3}' | grep -w "$VICTIMPID"`

		if [ x"$CHILDREN" = x ]; then
			### This is faster, a lot
			kill -9 "$VICTIMPID"
		else
			### This is quite slow but handles trees
			"$PROCTREE" -n 9 "$VICTIMPID" 2>/dev/null
		fi
	else
		kill -9 "$VICTIMPID"
	fi
}

do_wait_kill() {
	COUNT=0
	while (( $COUNT < $TIMEOUT )); do
		if [ -s "$LOCK" ]; then
			### Waiter below succeeded, process completed on time
			rm -f "$LOCK"
			return 0
		fi

		### If executed command was really fast,
		### we might not need sleep at top of cycle
		COUNT=$(($COUNT+1))
		sleep 1
	done

	### If we didn't exit yet, the process should be killed
	### Check changes during last sleep cycle
	if [ -s "$LOCK" ]; then
		### Waiter below succeeded, process completed on time
		rm -f "$LOCK"
		return 0
	fi

	### Check that it has the same name as we spawned ;)
	KILLPID=`ps -ef | grep "$CMD" | grep -v grep | awk '{print $2}' | grep -w "$RUNPID"`

	### A script can do "exec" and its CMD name changes
	[ x"$KILLPID" = x ] && KILLPID=`ps -ef | grep -v grep | awk '{print $2}' | grep -w "$RUNPID"`

	if [ x"$KILLPID" != x ]; then
		echo "Timed out: Killing [$RUNPID] after $TIMEOUT secs: $CMDLINE" >&2
		do_kill "$RUNPID"
		return 1
	fi
	return 0
}

### Spawn the requested process...

"$@" &
RUNPID=$!
LOCK="/tmp/timerun.$RUNPID.lock"

### Spawn the waiting killer...
do_wait_kill &
KILLERPID=$!

### Wait for them to complete
wait $RUNPID
RUNSTATUS=$?
echo "ok, $RUNSTATUS" > "$LOCK"

### Wait if killer is still alive
wait $KILLERPID
KILLSTATUS=$?
# echo "[$$]ks='$KILLSTATUS', rs='$RUNSTATUS'"

if [ -s "$LOCK" ]; then
	rm -f "$LOCK"
fi

if [ $KILLSTATUS = 0 ]; then
	exit "$RUNSTATUS"
else
	exit "-1"
fi
