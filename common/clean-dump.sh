#!/bin/bash

# clean-dump.sh
# (C) Nov 2005-Dec 2014 by Jim Klimov, COS&HT
# $Id: clean-dump.sh,v 1.47 2015/06/09 15:07:26 jim Exp $

# clean-dump.sh [-v] -d dir [-m mountpoint] [-k freekb] [-p freepct] [-if freeinodes] [-ip freeinodespct] [-ac age] [-aa age] [-Ac age] [-Aa age] [-syncsleep syncsec] [-synctwice] [-n]
# Cleans a dump dir (-d) if there's a problem with free space
# on its mountpoint (-m) or if files' age exceeds (-a), if specified
# This version works for one dir, may be later expanded or dispatched
# to clean several dirs.
# It checks that only one copy of this script is run at a time.
# May take ages to prepare work with large dirs (many files), also
# untested and may fail in that case (took about 7 min to build a
# file-size-age list in 4k file dir on test host, and a lifetime
# to clean them up with quick checks on every run, about 40min)...
# "Optimized" for dump dirs - with few large files.

# Needs some field testing, but seems suitable to run from CRON

# TODO: find a scriptable way to discover actual mountpoints.
# IDEA= Parse 'df' output for last field - works ok in sol8+
# IDEA= Check tomcat startscripts for link dereferencing, then
#       compare with `mount`ed paths while cutting off dirnames
# TODO: add usage of masks to select files (like *.gz) in dumpdir

AGENTNAME="`basename "$0"`"
AGENTDESC="Check and clean a log/dump directory"

TIMEOUT=15

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
	COSAS_BINDIR=`pwd`
fi
AGENT_FREESPACE="$COSAS_BINDIR/agent-freespace.sh"
TIMERUN="$COSAS_BINDIR/timerun.sh"

# We require a GNU date with +%s param
GDATE_LIST="/opt/COSac/bin/gdate /usr/gnu/bin/gdate /usr/gnu/bin/date /opt/sfw/bin/gdate /usr/local/bin/date /usr/local/bin/gdate /usr/sfw/bin/gdate /usr/sfw/bin/date"
[ x"`uname -s`" = xLinux ] && GDATE_LIST="$GDATE_LIST /bin/date"
GDATE=""

# Params for lockfile
BUGMAIL="postmaster"
HOSTNAME=`hostname`

# TODO Lockfile name should depend on params (dir)
LOCK_BASE="/tmp/$AGENTNAME.lock"
# Set WAIT_C=0 to skip waits
WAIT_C=5
WAIT_S=15

# Don't let maintenance script break server's real works
[ x"$RENICE" = x ] && RENICE=17
[ x"$RENICE" = x- ] && RENICE=""

do_help() {
	echo "Utility:	$AGENTNAME"
	echo "	$AGENTDESC"

	echo "Usage: $0 [-v [-v]] [-t timeout] [-N nice] [-p freepct] [-k freekb] [-if freeinodes] [-ip freeinodespct] -d dir [-m mountpoint] [-ac age] [-aa age] [-syncsz synckb] [-syncsleep syncsec] [-synctwice] [-follow] [-deldirs]"
	echo "Parameters for this script and sub-scripts:"
	echo "	-v (-v)		enable more verbose reports from this (and sub) agents"
	echo "	-n (-n)		read-only run for diagnostics/debug (+1 fake RM success)"
	echo "	-follow		treat symlinks to dirs like dirs which may contain files"
	echo "	-deldirs	delete empty directories (loop until all are removed)"
	echo "			NOTE: 'touch .cleandump-retain' in a directory to always keep"
	echo "	dir		dir under which we check and delete files, from root /"
	echo "	mountpoint	should go from root node / and contain the dump dir"
	echo "			WARNING: it's not yet confirmed by script, be careful!"
	echo "	-ac, -aa age	if specified>0, delete files OLDER than age seconds"
	echo "			(default: Creation=$MAXAGEC, Access=$MAXAGEA)"
	echo "	-Ac, -Aa age	if specified>0, keep files YOUNGER than age seconds"
	echo "			(default: Creation=$MINAGEC, Access=$MINAGEA)"
	echo "	  NB: age checks Creation (hires) and/or Access (lowres) time of files"
	echo "	-syncsz synckb	if specified>0, only issue sync/lockfs when a bunch of"
	echo "			files amounting to 'synckb' kilobytes was deleted (def: 0)"
	echo "	-syncsleep syncsec	if specified>0, sleep after sync requests (this"
	echo "			may be needed with larger files on slower systems)"
	echo "	-synctwice	after lockfs-or-sync, also do a sync before optional sleeping"
	echo "	nice		renice to priority nice before work (default: $RENICE)"
	echo "			specify '-N -' to avoid renicing in this script"
	echo "Params below are passed to sub-agents and are not used by this script itself:"
	echo "	timeout		default 5 sec (also used by script to run sync/lockfs)"
	echo "	freepct 	check fails if less than this %free is reported"
	echo "	freekb		check fails if less than this kb free is reported"
	echo "	freeinodes	check fails if less than this inodes free is reported"
	echo "	freeinodespct	check fails if less than this inodes % free is reported"
	echo "			! inodes are checked if applicable to this FStype"
}

### Include this after config files, in case of RUNLEVEL_NOKICK mask override
RUN_CHECKLEVEL=""
[ -s "$COSAS_BINDIR/runlevel_check.include" ] && \
    . "$COSAS_BINDIR/runlevel_check.include" && \
    block_runlevel

# will pass freespace params to agent-freespace.sh
FREESPACE_PARAMS=""

# Parse params
GOTWORK=0
DUMPDIR=""
MOUNTPT=""
VERBOSE=no
DELDIRS=no
SYNCKB="0"
SYNC_SLEEP="0"
SYNC_TWICE=no
MAXAGEC="0"
MAXAGEA="0"

# By default, keep recent (unfinished) dumps for 30 min
MINAGEC="1800"
MINAGEA="1800"

# If == 1, don't delete files, but check no locking either
CHECKONLY=0

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
		-N) RENICE="$2"; shift;;
		-n) CHECKONLY=$(($CHECKONLY+1)) ;;
		-v)	if [ $VERBOSE = -v ]; then
				FREESPACE_PARAMS="$FREESPACE_PARAMS $1"
			fi
			VERBOSE=-v
			;;
		-follow) FIND_FOLLOW="-follow" ;;
		-deldirs) DELDIRS="yes" ;;
		-t)	shift 1
			OK=no
			if [ x"$1" != x ]; then
				if [ "$1" -gt 0 ]; then
					TIMEOUT="$1"
					OK=yes
				fi
			fi
			if [ $OK = no ]; then
				echo "Wrong timeout, using default" >&2
			fi
			;;
		-syncsz|-synckb)
			shift 1
			OK=no
			if [ x"$1" != x ]; then
				if [ "$1" -ge 0 ]; then
					SYNCKB="$1"
					OK=yes
				fi
			fi
			if [ $OK = no ]; then
				echo "Wrong sync size, using default" >&2
			fi
			;;
		-syncsleep|-syncsec)
			shift 1
			OK=no
			if [ x"$1" != x ]; then
				if [ "$1" -ge 0 ]; then
					SYNC_SLEEP="$1"
					OK=yes
				fi
			fi
			if [ $OK = no ]; then
				echo "Wrong sync sleep delay, using default" >&2
			fi
			;;
		-synctwice)
			SYNC_TWICE=yes
			;;
		-ac|-am)
			shift 1
			OK=no
			if [ x"$1" != x ]; then
				if [ "$1" -gt 0 ]; then
					MAXAGEC="$1"
					OK=yes
				fi
			fi
			if [ $OK = no ]; then
				echo "Wrong maxageC" >&2
			fi
			;;
		-aa)	shift 1
			OK=no
			if [ x"$1" != x ]; then
				if [ "$1" -gt 0 ]; then
					MAXAGEA="$1"
					OK=yes
				fi
			fi
			if [ $OK = no ]; then
				echo "Wrong maxageA" >&2
			fi
			;;
		-Ac|-Am)
			shift 1
			OK=no
			if [ x"$1" != x ]; then
				if [ "$1" -gt 0 ]; then
					MINAGEC="$1"
					OK=yes
				fi
			fi
			if [ $OK = no ]; then
				echo "Wrong minageC" >&2
			fi
			;;
		-Aa)	shift 1
			OK=no
			if [ x"$1" != x ]; then
				if [ "$1" -gt 0 ]; then
					MINAGEA="$1"
					OK=yes
				fi
			fi
			if [ $OK = no ]; then
				echo "Wrong minageA" >&2
			fi
			;;
		-p|-k|-if|-ip) FREESPACE_PARAMS="$FREESPACE_PARAMS $1 $2"; shift ;;
		-d) DD="`echo "$2" | sed 's,\(.\)/$,\1,' | sed 's,^//,/,'`"
		    if [ x"$DUMPDIR" = x ]; then
			if [ -d "$DD" -a -x "$DD" -a -w "$DD" -a -r "$DD" ]; then
				GOTWORK=$(($GOTWORK+1))
				DUMPDIR="$DD"
			else
				echo "Proposed dump dir '$DD' is not a dir or not modifiable. Aborting!" >&2
				exit 1
			fi
		    else
			echo "Proposed dump dir '$DD' ignored: a valid dir already specified ($DUMPDIR)" >&2
		    fi
		    shift
		    ;;
		-m) DD="`echo "$2" | sed 's,\(.\)/$,\1,' | sed 's,^//,/,'`"
		    if [ x"$MOUNTPT" = x ]; then
			if [ -d "$DD" -a -x "$DD" ]; then
				# For mountpoints we should be able to see thru them...
				GOTWORK=$(($GOTWORK+1))
				MOUNTPT="$DD"
			else
				echo "Proposed dump dir mountpt '$DD' is not a dir or not accessible. Aborting!" >&2
				exit 1
			fi
		    else
			echo "Proposed dump dir mountpt '$DD' ignored: a valid one already specified ($MOUNTPT)" >&2
		    fi
		    shift
		    ;;
		*) echo "Unknown param:	$1" >&2;;
	esac
	shift
done

# Sanity Checkers

[ x"$FIND_FOLLOW" != x"-follow" ] && FIND_FOLLOW=""
[ x"$RENICE" = x- ] && RENICE=""

if [ "$MAXAGEC" -gt 0 -a "$MINAGEC" -gt 0 ]; then
	if [ "$MAXAGEC" -le "$MINAGEC" ]; then
		echo "maxageC ($MAXAGEC) must be larger than minageC ($MINAGEC)" >&2
		exit 1
	fi
fi

if [ "$MAXAGEA" -gt 0 -a "$MINAGEA" -gt 0 ]; then
	if [ "$MAXAGEA" -le "$MINAGEA" ]; then
		echo "maxageA ($MAXAGEA) must be larger than minageA ($MINAGEA)" >&2
		exit 1
	fi
fi

if ! [ "$SYNCKB" -ge 0 ]; then
	echo "Sync size specified wrong ($SYNCKB), defaulting to disabled" >&2
	SYNCKB=0
fi

if ! [ "$SYNC_SLEEP" -ge 0 ]; then
	echo "Sync delap specified wrong ($SYNC_SLEEP), defaulting to disabled" >&2
	SYNC_SLEEP=0
fi

if [ ! -x "$AGENT_FREESPACE" ]; then
	echo "Requires: agent-freespace '$AGENT_FREESPACE'" >&2
	exit 1
fi

if [ ! -x "$TIMERUN" ]; then
	echo "Requires: timerun '$TIMERUN'" >&2
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

TS_START=`$GDATE +%s`
if [ ! "$TS_START" -gt 0 ]; then
	echo "Requires: GNU date with +%s parameter ('$GDATE' not OK)" >&2
	exit 1
fi

case "$DUMPDIR" in
	/*) 	;;
	*)	DUMPDIR="`pwd`/$DUMPDIR/"
		[ "$VERBOSE" = -v ] && echo "Replaced DUMPDIR value: '$DUMPDIR'"
		;;
esac

if [ ! -d "$DUMPDIR" -o ! -x "$DUMPDIR" ] || [ "$DUMPDIR" = / ]; then
	echo "Invalid dumpdir path: '$DUMPDIR'" >&2
	exit 1
fi

if [ x"$MOUNTPT" = x ]; then
	DD=`"$TIMERUN" "$TIMEOUT" df -k "$DUMPDIR" | tail -1 | awk '{ print $NF }'`
	if [ $? = 0 ]; then
		DD=`echo "/$DD" | sed 's/\/$//' | sed 's/^\/\//\//'`
		if [ -d "$DD" -a -x "$DD" ]; then
			# For mountpoints we should be able to see thru them...
			GOTWORK=$(($GOTWORK+1))
			MOUNTPT="$DD"
			echo "Determined mountpoint for dump dir: '$MOUNTPT'"
		else
			echo "Proposed dump dir mountpt '$DD' is not a dir or not accessible. Aborting!" >&2
			exit 1
		fi
	else
		echo "Could not retrieve mountpoint for dump dir. Aborting!" >&2
		exit 1
	fi
fi

if [ "$GOTWORK" != 2 ]; then
	echo "Wrong number of required params received. Aborting!"
	exit 1
fi

LOCK="$LOCK_BASE.`echo "$DUMPDIR" | sed 's/\//_/g'`"

if [ "$VERBOSE" != no ]; then
	echo "My params: d=$DUMPDIR m=$MOUNTPT gdate=$GDATE lock=$LOCK readonly=$CHECKONLY syncsz=$SYNCKB syncsec=$SYNC_SLEEP synctwice=$SYNC_TWICE"
fi

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

if [ x"$LSMODE" = x ]; then
	ls -uE / >/dev/null 2>&1 && LSMODE="ExtDate"
fi

### Define a few routines...

rmfile() {
# Do a few checks whether the file should be kept, and delete it if they fail
	FILE="$1"

	check_minage "$FILE"
	RESULT_MINAGE=$?
	if [ "$RESULT_MINAGE" = 0 ]; then
		if [ $CHECKONLY = 0 ]; then
			rm -f "$FILE"
			RESULT_RM=$?

			if [ $RESULT_RM = 0 ]; then
				echo "+ Successfully removed $FILE"
			else
				echo "- Failed ($RESULT_RM) to remove $FILE"
			fi

			return $RESULT_RM
		else
			# CHECKONLY != 0
			echo "= READ-ONLY mode, not actually removing '$FILE'"

			[ "$CHECKONLY" -gt 1 ] && return 0
			# make believe that RM succeeded

			return 1
		fi
	fi
	return $RESULT_MINAGE
}

check_minage() {
# Check if the file is too young to die
# return 0 if ok to kill
# NOTE: if the file is written/accessed while the clean-dump.sh script
# is running, the corresponding age can seem negative from the main cycle
# (since $TS_START value is frozen)
	FILE="$1"

	TS_NOW=`$GDATE +%s`
	ELAPSED=$(($TS_NOW-$TS_START))
	[ "$ELAPSED" -le 0 ] && ELAPSED=0

	if [ ! -e "$FILE" ]; then
		echo "ERROR: Asked to check age of absent '$FILE'" >&2
		return 0
		# Try to kill anyway; perhaps rm will succeed
	fi

	if [ "$MINAGEC" -gt 0 ]; then
		# Get modification (~creation) time of file,
		# this leads to its extreme age
		TS_M=`getMtime "$FILE"`
		FILEAGE_M=$(($TS_START-$TS_M))

		if [ "$FILEAGE_M" -le "$MINAGEC" -a "$FILEAGE_M" -ge "-$ELAPSED" ]; then
			echo "= Too young to die (Mtime: $FILEAGE_M): $FILE"
			return 1
		fi
	fi

	if [ "$MINAGEA" -gt 0 ]; then
		# Get access (last submit attempt) time of file,
		# retry some time after that
		TS_A=`getAtime "$FILE"`
		FILEAGE_A=$(($TS_START-$TS_A))

		if [ "$FILEAGE_A" -le "$MINAGEA" -a "$FILEAGE_A" -ge "-$ELAPSED" ]; then
			echo "= Too young to die (Atime: $FILEAGE_A): $FILE" 
			return 2
		fi
	fi

	return 0
}

clean_abandoned() {
	PWD_ABANDONED=`pwd`

	cd "$DUMPDIR"
	if [ $? != 0 ]; then
		echo "ERROR: Couldn't cd to dump dir '$DUMPDIR'" >&2
		return 2
	fi

	# We have another special sort of files, incomplete dumps due to killed dumpers
	# They are less useful than complete older dumps and take space of future ones ;)
	for FILE in `find . $FIND_FOLLOW -type f -name '*.__WRITING__'`; do
		# check for no spaces, etc ;)
		if [ -f "$FILE" ]; then
			# fuser returns PID of accessing process in stdout
			# but this only works on local host (not NFS dump server)
			FUSER_PID=`fuser "$FILE" 2>/dev/null`
			if [ x"$FUSER_PID" = x ]; then
				# abandoned unfinished file...
				echo "Removing '$DUMPDIR/$FILE': abandoned unfinished dump"

				rmfile "$FILE"
				if [ $? = 0 ]; then
					CLEANEDOLD=$(($CLEANEDOLD+1))
				fi
			else
				echo "Not removing '$DUMPDIR/$FILE': unfinished dump accessed by PID(s): $FUSER_PID"
			fi
		fi
	done

	cd "$PWD_ABANDONED"
}

getMtime() {
	# Get modification (~creation) time of file,
	# this leads to its extreme age

	$GDATE -r "$1" +%s
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
		$GDATE -d "$(ls -uE "$FILE" | awk '{print $6" "$7" "$8 }' | sed 's/^\(.*\)\..*\( .*\)$/\1\2/' )" +%s
	else
		$GDATE -d "$(ls -ul "$FILE" | awk '{print $6" "$7" "$8 }')" +%s
	fi
}

do_build_list() {
	[ $VERBOSE = -v ] && echo "=== Building a file-size list to sort and process. Unsorted data:" >&2
	[ $VERBOSE = -v ] && echo "===	Mtime		Size	Inodes	Filename" >&2

	RL_COUNT=0
	for FILE in `find . $FIND_FOLLOW -type f`; do
		# Could also search by 'not newer', but it requires a file for comparison

		### Check that we're not yet shutting down
		if [ x"$RUN_CHECKLEVEL" != x ]; then
			if [ "$RL_COUNT" -ge 50 ]; then
				block_runlevel
				RL_COUNT=0
			fi
			RL_COUNT=$(($RL_COUNT+1))
		fi

		case "$FILE" in
		    */.lastsync*|*/.lastbackup.*)
			[ $VERBOSE = -v ] && echo "Not removing '$DUMPDIR/$FILE': touch-files needed for automatic backups" >&2
			continue
			;;
		    */.cleandump-retain*)
			[ $VERBOSE = -v ] && echo "Not removing '$DUMPDIR/$FILE': touch-file request to keep this directory" >&2
			continue
			;;
		esac

		# fuser returns PID of accessing process in stdout
		FUSER_PID=`fuser "$FILE" 2>/dev/null`
		if [ x"$FUSER_PID" = x ]; then
			# file not used...

			# Get modification (~creation) time of file
			TS_M=`getMtime "$FILE"`
			INODES=`ls -la "$FILE" | awk '{ print $2 }'`
			# This is a more true size than ls's column 5 in case of sparse or compressed files
			SZ=`du -ks "$FILE" | awk '{ print $1 }'`

			[ $VERBOSE = -v ] && echo "...	$TS_M	$SZ	$INODES	$FILE" >&2
			echo "$TS_M	$SZ	$INODES	$FILE"
		else
			echo "INFO: Skipping file [$TS_M	$SZ	$INODES	$FILE] accessed by PID(s) $FUSER_PID" >&2
		fi
	done | sort -k 1n -k 2rn 
}

deldirs() {
	### Find all empty branch dirs and remove them
	find . -depth -type d | while read D; do
		DD="`LANG=C ls -lA "$D"`"
		if [ x"$DD" = x'total 0' -o x"$DD" = x ] && \
		   [ x"$D" != x. -a x"$D" != x/ ]; then
			echo "$D"
			[ $CHECKONLY = 0 ] && rm -rf "$D" &
		fi
	done
	wait
	sync
}

### Do some work now...

if [ x"$RENICE" != x ]; then
	[ "$VERBOSE" = -v ] && \
		echo "INFO: Setting process priority for work: '$RENICE'"
	renice "$RENICE" $$
fi

### Cleaner algorithm
# Before-Loop:
# 0) check availability of device and presence of problems
# 1) find and remove old files (if requested)
# Loop:
# 2) check availability and free space (if [1] was done)
#	remember current free space for future estimates
#	so we don't call agent after every deletion
# 3) if no problems or empty dumpdir or nothing cleaned
#	on last run - abort the loop
# 4) by some prioritization (e.g. oldest+biggest files)
#	unlink files and remember their size (+number
#	of inodes), estimate free space changes if it
#	was the last inode of the file
# 5) when we have a hypothesis that enough space was 
#	reclaimed, loop to next cycle [2], otherwise
#	we risk many long checks after cleaning small
#	files
# After-loop:
# 1) if "-deldirs" flag was given, run a loop of removing
#	all empty directories (may be nested, thus a loop)
#	under current target

# Running the agent takes some time due to timeouts (min 5 sec of little work)
# It ensures that working mountpoint is available and whether it needs cleanup
[ $VERBOSE = -v ] && echo "=== Checking with agent-freespace"

OUTPUT=`"$AGENT_FREESPACE" -t "$TIMEOUT" $FREESPACE_PARAMS "$MOUNTPT" 2>&1`
RESULT=$?
[ $VERBOSE = -v ] && echo "===== result: $RESULT"

ABORTLOOP_FILES=no
ABORTLOOP_DIRS=yes
[ x"$DELDIRS" = xyes ] &&
	ABORTLOOP_DIRS=no

CLEANEDOLD=0
case "$RESULT" in
	255|65535)
		echo "ERROR: Access to '$MOUNTPT' timed out. Aborting!" >&2
		[ $CHECKONLY = 0 ] && rm -f "$LOCK"
		exit $RESULT
		;;
	1) echo "ERROR: failed to run agent-freespace (params). Aborting!" >&2
		[ $CHECKONLY = 0 ] && rm -f "$LOCK"
		exit $RESULT
		;;
	2) echo "ERROR: failed to run agent-freespace (mountpt). Aborting!" >&2
		[ $CHECKONLY = 0 ] && rm -f "$LOCK"
		exit $RESULT
		;;
	0) if [ "$MAXAGEC" = 0 -a "$MAXAGEA" = 0 ]; then
		# Got enough free space, not required to kill old files
		clean_abandoned
		[ $VERBOSE = -v ] && echo "===== Got no work right now"
		ABORTLOOP_FILES=yes
	   fi
	   ;;
esac

cd "$DUMPDIR"
if [ $? != 0 ]; then
	echo "ERROR: Couldn't cd to dump dir '$DUMPDIR'" >&2
	[ $CHECKONLY = 0 ] && rm -f "$LOCK"
	exit 2
fi

# If we are here then agent reported an error and/or we should check files' age
# Also the work directory is accessible...

[ x"$ABORTLOOP_FILES" = xno -o x"$ABORTLOOP_DIRS" = xno ] && \
	[ $VERBOSE = -v ] && echo "=== Proceeding to actual work"

[ x"$ABORTLOOP_FILES" = xno ] && \
	if [ `find . $FIND_FOLLOW -type f | wc -l | awk '{ print $1 }'` = 0 ]; then
		echo "No more files under dumpdir"
		ABORTLOOP_FILES=yes
	fi

[ x"$ABORTLOOP_FILES" = xno ] && \
	clean_abandoned

[ x"$ABORTLOOP_FILES" = xno ] && \
    if [ "$MAXAGEC" != 0 -o "$MAXAGEA" != 0 ]; then
	[ $VERBOSE = -v ] && echo "=== Checking file ages"
	for FILE in `find . $FIND_FOLLOW -type f`; do
		# Could also search by 'not newer', but it requires a file for comparison

		# Get modification (~creation) time of file,
		# this leads to its extreme age
		TS_M=`getMtime "$FILE"`
		FILEAGE_M=$(($TS_START-$TS_M))

		# Get access (last submit attempt) time of file,
		# retry some time after that
		# WARNING: This is a very approximate measurement
		# (minutes for a fresh file, days for old one)
		# Updateable by 'touch -a FILE'
		TS_A=`getAtime "$FILE"`
		FILEAGE_A=$(($TS_START-$TS_A))

		if [ "$FILEAGE_M" -ge "$MAXAGEC" -a "$MAXAGEC" -gt 0 ]; then
			### File was created too long ago
			echo "Removing '$DUMPDIR/$FILE': created too long ago ($MAXAGEC < $FILEAGE_M)"
			rmfile "$FILE"
			if [ $? = 0 ]; then
				CLEANEDOLD=$(($CLEANEDOLD+1))
			fi
		fi

		if [ "$FILEAGE_A" -ge "$MAXAGEA" -a -s "$FILE" -a "$MAXAGEA" -gt 0 ]; then
			### File was accessed too long ago
			echo "Removing '$DUMPDIR/$FILE': accessed too long ago ($MAXAGEA < $FILEAGE_A)"
			rmfile "$FILE"
			if [ $? = 0 ]; then
				CLEANEDOLD=$(($CLEANEDOLD+1))
			fi
		fi
	done
    fi

# Force quick-running the agent regardless of removed old files
RUN_AGENT=1
if [ $CLEANEDOLD != 0 ]; then
#	RUN_AGENT=1
	CLEANEDOLD=0
fi

[ x"$ABORTLOOP_FILES" = xno ] && \
	if [ `find . $FIND_FOLLOW -type f | wc -l | awk '{ print $1 }'` = 0 ]; then
		echo "No more files under dumpdir"
		ABORTLOOP_FILES=yes
	fi

# TODO: later move it to cycle below
[ x"$ABORTLOOP_FILES" = xno ] && \
	FILESIZELIST=`do_build_list`

while [ "$ABORTLOOP_FILES" = no ]; do
	### Check that we're not yet shutting down
	[ x"$RUN_CHECKLEVEL" != x ] && block_runlevel

	# Recursively clean up
	[ $VERBOSE = -v ] && echo "=== Cycle start (CLEANEDOLD = $CLEANEDOLD)..."

	if [ $RUN_AGENT != 0 ]; then
		# Running the agent takes some time due to timeouts (min 5 sec of little work)
		# It ensures that working mountpoint is available and whether it needs cleanup
		[ $VERBOSE = -v ] && echo "=== Checking with agent-freespace (quick mode)"
		OUTPUT=`"$AGENT_FREESPACE" -q -t "$TIMEOUT" $FREESPACE_PARAMS "$MOUNTPT" 2>&1`
		RESULT=$?
		[ $VERBOSE = -v ] && echo "===== result: $RESULT"
#		[ $VERBOSE = -v ] && echo "===== OUTPUT: "
#		[ $VERBOSE = -v ] && echo "$OUTPUT"

		case "$RESULT" in
			255|65535)
			    echo "ERROR: Access to '$MOUNTPT' timed out. Aborting!" >&2
			    [ $CHECKONLY = 0 ] && rm -f "$LOCK"
			    exit $RESULT
			    ;;
			1)  echo "ERROR: failed to run agent-freespace (params). Aborting!" >&2
			    [ $CHECKONLY = 0 ] && rm -f "$LOCK"
			    exit $RESULT
			    ;;
			2)  echo "ERROR: failed to run agent-freespace (mountpt). Aborting!" >&2
			    [ $CHECKONLY = 0 ] && rm -f "$LOCK"
			    exit $RESULT
			    ;;
			0)
			    [ $VERBOSE = -v ] && echo "===== Got no work right now"
			    ABORTLOOP_FILES=yes
			    ;;
		esac

		RUN_AGENT=0
		CLEANEDOLD=0

		# TODO: later enable this (when we use estimates to call agents)
		# FILESIZELIST=`do_build_list`
	fi

	# TODO: for now -
	#	Select files to kill and kill them
	#	always check agent (in quick mode) and skip the counters
	# Later -
	#	Remember current free space
	#	Select files to kill and kill them
	#	Update counter if inode count was == 1
	#	Estimate free space changes, set RUN_AGENT=1 if desired

	# find the oldest files, among them find the biggest files
	# repeat cycle, maybe checking the free space on the way

	[ x"$ABORTLOOP_FILES" = xno ] && \
	if [ `find . $FIND_FOLLOW -type f | wc -l | awk '{ print $1 }'` = 0 ]; then
		echo "No more files under dumpdir"
		ABORTLOOP_FILES=yes
	fi

	SYNCKB_COUNT=0
	[ x"$ABORTLOOP_FILES" = xno ] && \
	CLEANEDOLD_ONE=$( CLEANEDOLD=0; echo "$FILESIZELIST" | while IFS="	" read TS_M SZ INODES FILE; do

		# We thus selected the oldest file (min TS) with biggest size
		# to be the first line of the selection, repeat until we can
		# delete a file (i.e. if permissions forbid), then break out

		if [ -f "$FILE" ]; then
			echo "Removing '$DUMPDIR/$FILE' as oldest+biggest	($TS_M, $SZ kb, $INODES inodes)..." >&2
			rmfile "$FILE" >&2
			# false
			if [ $? = 0 ]; then
				if [ x"$INODES" != x1 ]; then					
					echo "+ Successfully unlinked $FILE, it has $(($INODES-1)) inodes left; going on" >&2
				else
					CLEANEDOLD=$(($CLEANEDOLD+$SZ))
					echo "$CLEANEDOLD"

					DO_SYNC=yes
					if [ "$SYNCKB" -gt 0 ]; then
						DO_SYNC=no
						SYNCKB_COUNT=$(($SYNCKB_COUNT+$SZ))
						if [ "$SYNCKB_COUNT" -ge "$SYNCKB" ]; then
							DO_SYNC=yes
							SYNCKB_COUNT=0
						fi
					fi

					if [ x"$DO_SYNC" = xyes ]; then
						echo "+ Successfully removed $FILE, syncing and breaking for space checks" >&2
						### Without sync we can delete too much and then have too 
						### much free space (and too few actual backups left).
						### With sync we can wait to complete other FSes writes 
						### or even freeze.
						[ -x "/usr/sbin/lockfs" ] && \
							"$TIMERUN" "$TIMEOUT" /usr/sbin/lockfs -f "$MOUNTPT" >&2 || \
							"$TIMERUN" "$TIMEOUT" sync >&2
						[ x"$SYNC_TWICE" = xyes ] && \
							"$TIMERUN" "$TIMEOUT" sync >&2
						[ x"$SYNC_SLEEP" != x ] && \
							echo "+++ Additionally sleeping $SYNC_SLEEP seconds" >&2 && \
							sleep "$SYNC_SLEEP" >&2
						break
					else
						echo "+ Successfully removed $FILE, but it was small - going on" >&2
					fi
				fi
			else
				echo "- Failed to remove file, trying next" >&2
			fi
		fi
	done )

	if [ x"$CLEANEDOLD_ONE" != x ]; then
		### Increment counter of known-freed space
		for I in $CLEANEDOLD_ONE; do
			CLEANEDOLD=$(($CLEANEDOLD+$I))
		done
		RUN_AGENT=1
	fi

	# later surround this with conditions based on inodes and size hypotheses
	RUN_AGENT=1

	# Check if we should exit the loop (if no work was done, includes empty dump dir)
	[ x"$ABORTLOOP_FILES" = xno ] && \
	if [ $CLEANEDOLD = 0 ]; then
		echo "CLEANEDOLD = $CLEANEDOLD, exiting"
		ABORTLOOP_FILES=yes
	fi

	[ x"$ABORTLOOP_FILES" = xno ] && \
	if [ $CHECKONLY != 0 ]; then
		echo "Read-only mode used for debugging. Aborting after first loop is complete."
		ABORTLOOP_FILES=yes
	fi
done

CLEANEDDIRS=0
OUT=""
while [ "$ABORTLOOP_DIRS" = no ]; do
	### Check that we're not yet shutting down
	[ x"$RUN_CHECKLEVEL" != x ] && block_runlevel

	# Recursively clean up
	[ $VERBOSE = -v ] && echo "=== Dir-clean cycle start (CLEANEDDIRS = $CLEANEDDIRS)..."

	OUT_PREV="$OUT"
	OUT="`deldirs`"
	RES=$?

	### We might find no dirs to delete, or those remaining empty might
	### be not-removable (access rights, mountpoints, etc.)
	### Either of those conditions would be end-of-loop.
	if [ x"$OUT" != x -a x"$OUT" != x"$OUT_PREV" -a "$RES" = 0 ]; then
		if [ "$VERBOSE" = -v ]; then
			echo "Deleted dirs:"
			echo "$OUT"
		fi
		CLEANEDDIRS=$(($CLEANEDDIRS+`echo "$OUT" | wc -l`))
	else
		[ $VERBOSE = -v ] && echo "=== Dir-clean loop finished (CLEANEDDIRS = $CLEANEDDIRS)..."
		ABORTLOOP_DIRS=yes
	fi

	[ x"$ABORTLOOP_DIRS" = xno ] && \
	if [ $CHECKONLY != 0 ]; then
		echo "Read-only mode used for debugging. Aborting after first loop is complete."
		echo "Dir-clean loop could remove $CLEANEDDIRS dirs"
		[ $VERBOSE != -v ] && echo "$OUT"
		ABORTLOOP_DIRS=yes
	fi
done

# Be nice, clean up
[ $CHECKONLY = 0 ] && rm -f "$LOCK"

exit 0
