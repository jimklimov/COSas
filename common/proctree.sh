#!/bin/bash

# $Id: proctree.sh,v 1.12 2014/01/31 17:17:18 jim Exp $
# Lists or signals a process tree
# Builds a reverse tree (root at end, siblings at start)
# $0 [-n|-s signal] pid [pid...]
# (C) 2004-2005 by Jim Klimov, COS&HT for Aircopy project (up to v1.7)
# (C) 2004-2010 by Jim Klimov, COS&HT revisited for portability (v1.8+)
# (C) 2012 by Jim Klimov, COS&HT added recursive renice for children (v1.10+)
# (C) 2013-2014 by Jim Klimov, COS&HT added automated serial killer

# NOTE: Despite the name and intent, this is currently not quite a "tree"
# by default (see -t option).

# The root PID(s) are at the end, all processes immediately spawned by them
# go before them, above go all grandchildren of the root PID(s) and so on,
# even in recursive mode (see -r option).

# TODO: in recursive mode, the top-level parent PIDs (like init, zsched) are
# reported many times, for each pid in command-line parameters. Is this bad?

SIGNAL=""
ROOT=""
QUIET=1
PSTREE=0
PSFULL=0
PSPID=1
RENICE=""

KILL_AUTO=""
KILL_SLEEP=3
KILL_SIGNALS_FLAG="-n"
KILL_SIGNALS_LIST="1 2 3 15 9"

case "`uname -s`" in
    Linux)	PSFULL_CMD="ps -efwww" ;;
    SunOS|*)	PSFULL_CMD="ps -ef" ;;
esac

PS_FUNCTION="ps_children"

while [ $# -gt 0 ]; do
	case "$1" in
	-h|--help|-help) echo "Lists or signals a reversed process tree (root at end, siblings at start)"
		echo "$0 [-n|-s signal] [-k | -kn|ks 'sig sig sig' -kd sec] \\"
		echo "		[-N renice] [-q|-v] [-p] [-P] [-r] [-t] pid [pid...]"
		echo "Parameters:
    -n|-s	Pass a numbered or named signal to 'kill', don't list PIDs
    -k		Kill the processes automatically with a series of kills:
    -kn|-ks	* use numbered or named LIST OF signals in given order
		  (default '$KILL_SIGNALS_FLAG' '$KILL_SIGNALS_LIST')
    -kd		* delay between kills (default $KILL_SLEEP seconds)
		  any of these -k* options enables serial killer
    -N		Try to renice found processes (may fail), don't list PIDs
    -q|-v	Quiet(default) or Verbose mode - more text around output
    -P		List '${PSFULL_CMD}' for found PIDs
    -p		Force listing of PIDs (default action when without signals)
    -r		Recursive mode (show parents of given PIDs), disables signals
    -t		Build indented PID-list by recursive algorithm (seen with -p)
    -h		Display this help and exit"
		exit 0
		;;
	-n|-s) SIGNAL="$1 $2"
		# Method above is more generic, but the one below seems
		# to work better in Linux and Solaris
#		SIGNAL="-"`echo "$SIGNAL" | awk '{ print $2}'`
		SIGNAL="-$2"

		shift
		shift
		PSPID=$(($PSPID-1))
		;;

	-kn)	KILL_SIGNALS_FLAG="-n"
		KILL_SIGNALS_LIST="$2"
		KILL_AUTO=yes
		shift
		shift
		PSPID=$(($PSPID-1))
		;;
	-ks)	KILL_SIGNALS_FLAG="-s"
		KILL_SIGNALS_LIST="$2"
		KILL_AUTO=yes
		shift
		shift
		PSPID=$(($PSPID-1))
		;;
	-kd)	KILL_SLEEP="$2"
		KILL_AUTO=yes
		shift
		shift
		PSPID=$(($PSPID-1))
		;;
	-k)	KILL_AUTO=yes
		shift
		PSPID=$(($PSPID-1))
		;;

	-N) # This can be an absolute value like "-5" or a single-token
	    # increment like "-n -5"
		RENICE="$2"
		shift
		shift
		PSPID=$(($PSPID-1))
		;;
	-P)	PSFULL=1 ; shift ;;
	-p)	PSPID=$(($PSPID+1)) ; shift ;;
	-t)	PSTREE=1 ; shift ;;
	-r) # Disable signals/renice - we don't want to shutdown OS by mistake
	    # Signals/renice can be enabled if they *follow* this flag, though.
		PS_FUNCTION="ps_parents"
		SIGNAL=""
		RENICE=""
		PSPID=$(($PSPID+1))
		shift ;;
	-q)	QUIET=1 ; shift ;;
	-v)	QUIET=0 ; shift ;;
	*) if [ x"$1" != x -a "$1" -gt 0 ]; then ROOT="$ROOT $1"; fi
		shift
		;;
	esac
done

if [ x"$ROOT" = x ]; then ROOT="$PPID"; fi

PS_ALL="`${PSFULL_CMD}`"

ROOT=`for P in $(echo "$ROOT" | sed 's/\([^0123456789]\)/ /g'); do echo "$P"; done | sort -n | uniq | egrep -v '^$'`
ROOT=`for P in $ROOT; do echo "$PS_ALL" | awk '{ if ( $2 == '"$P"' ) { print $2 } }'; done`

PID_ALL="$ROOT"
PID_LEVEL_THIS=""
PID_LEVEL_PARENT="$ROOT"
PID_LEVEL_DEPTH=0

if [ x"$QUIET" = x0 ]; then
	if [ x"$SIGNAL" != x -a x"$RENICE" != x ]; then 
		echo -n "Signaling '$SIGNAL' and renicing '$RENICE' "
	fi

	if [ x"$SIGNAL" = x -a x"$RENICE" != x ]; then 
		echo -n "Renicing '$RENICE' "
	fi

	if [ x"$SIGNAL" != x -a x"$RENICE" = x ]; then 
		echo -n "Signaling '$SIGNAL' "
	fi

	if [ x"$SIGNAL" = x -a x"$RENICE" = x ]; then 
		echo -n "Listing "
	fi

	if [ x"$PS_FUNCTION" = x"ps_parents" ]; then
		echo -n "in reverse "
	fi

	echo "the tree(s) of processes spawned by PID(s):
$ROOT"
fi

ps_children() {
	if [ $# = 0 ]; then return; fi
	for PARENT in $@; do
		echo "$PS_ALL" | awk '{ if ( $3 == '"$PARENT"' ) { print $2 } }' | fgrep -vx "$$"
	done
}

ps_parents() {
	if [ $# = 0 ]; then return; fi
	for CHILD in $@; do
		echo "$PS_ALL" | awk '{ if ( $2 == '"$CHILD"' && $2 != $3 ) { print $3 } }' | fgrep -vx "$$"
	done
}

ps_dig() {
	PID_LEVEL_PARENT="$ROOT"
	while [ x"$PID_LEVEL_PARENT" != x ]; do
		PID_LEVEL_THIS=`$PS_FUNCTION $PID_LEVEL_PARENT`
		PID_LEVEL_DEPTH=$(($PID_LEVEL_DEPTH+1))
		if [ x"$PS_FUNCTION" = xps_children ]; then
			PID_ALL="$PID_LEVEL_THIS $PID_ALL"
		else
			PID_ALL="$PID_ALL $PID_LEVEL_THIS"
		fi
		PID_LEVEL_PARENT="$PID_LEVEL_THIS"
	done

	PID_ALL=`for P in $PID_ALL; do echo "$P"; done`
}

ps_dig_recurse() {
	### NOTE: named vars are overwritten upon shell recursion!
	#_INDENT="$1"
	#_PARENT="$2"

	[ x"$PS_FUNCTION" = xps_parents ] && echo "$1$2"

	for P in `$PS_FUNCTION $2`; do
	    ps_dig_recurse "$1 " "$P"
	done

	[ x"$PS_FUNCTION" = xps_children ] && echo "$1$2"
}

ps_dig_tree() {
	PID_ALL=`for P in $ROOT; do ps_dig_recurse "" $P; done`
}

if [ x"$PSTREE" = x0 ]; then
	ps_dig
else
	ps_dig_tree
fi

if [ x"$QUIET" = x0 ]; then
	echo "-------"
fi

if [ x"$PSFULL" = x1 ]; then
	for P in $PID_ALL; do 
	    echo "$PS_ALL" | awk '{ if ( $2 == '"$P"' ) { print } }'
	done
else
	if [ "$PSPID" -ge 1 ]; then
		echo "$PID_ALL"
	fi
fi

if [ x"$SIGNAL" != x ]; then
	###	kill $SIGNAL $PID_ALL
	if [ x"$QUIET" = x0 ]; then
		echo "------- Killing '$PID_ALL' with '$SIGNAL'"
	fi

	kill $SIGNAL $PID_ALL
fi

if [ x"$KILL_AUTO" = xyes ]; then
	if [ x"$QUIET" = x0 ]; then
		echo "------- Serial-killing '$PID_ALL' with '$KILL_SIGNALS_FLAG' '$KILL_SIGNALS_LIST' with delay of '$KILL_SLEEP'"
	fi

	for S in $KILL_SIGNALS_LIST; do
	    [ x"$QUIET" = x0 ] && echo "-------- Signalling $S:"
	    kill $KILL_SIGNALS_FLAG $S $PID_ALL
	    sleep $KILL_SLEEP
	done
fi

if [ x"$RENICE" != x ]; then
	### "$RENICE" may be a single number "1" or two-word increment "-n 1"
	###	renice $RENICE $PID_ALL
	if [ x"$QUIET" = x0 ]; then
		echo "------- Renicing with '$RENICE'"
	fi

	renice $RENICE $PID_ALL
fi
