#!/bin/bash

# dumper-pgsql-export.sh
# (C) Mar 2009-Jan 2014 by Jim Klimov, COS&HT
# $Id: dumper-pgsql-export.sh,v 1.14 2014/01/25 11:57:16 jim Exp $
# Creates a dump of specified pgsql database schema
# Used from command-line or other scripts

AGENTNAME="`basename "$0"`"
AGENTDESC="Pgsql exporter: creates a compressed tar archive, prints name to >&3"

[ x"$PGSQL_USER" = x ] && PGSQL_USER="postgres"

for D in \
    "/opt/pgsql" \
    "/usr/postgres/8.3" \
    "`getent passwd $PGSQL_USER | awk -F: '{print $6}'`" \
; do
    [ x"$PGSQL_HOME" = x -a -d "$D" ] && PGSQL_HOME="$D"
done

# Options for pg_dump (named-database) mode
[ x"$PGSQL_DUMPOPTIONS" = x ] && \
    PGSQL_DUMPOPTIONS="--blobs --create --column-inserts --disable-dollar-quoting"

# Options for pg_dumpall mode
[ x"$PGSQL_DUMPOPTIONS_ALLDB" = x ] && \
    PGSQL_DUMPOPTIONS_ALLDB="--ignore-version --column-inserts --disable-triggers --disable-dollar-quoting"

for F in "$PGSQL_HOME/bin/64/pg_dump" "$PGSQL_HOME/bin/pg_dump"; do
    [ x"$PGSQL_DUMPBIN" = x -a -x "$F" ] && PGSQL_DUMPBIN="$F"
done

# Configuration file for pgsql environment variables
# Overrides env var defaults exported by caller, may be turned off
PGSQL_PROFILE="$PGSQL_HOME/.profile"
# Don't use /tmp as DEFAULT_DUMPDIR because problems with remote NFS dump
# servers can cause swap depletion on dumped servers. Use a local dump dir
# here, or an absent dir to abort.
DEFAULT_DUMPDIR="/var/tmp/DUMP"
DUMPDIR=`pwd`
if [ x"$DUMPDIR" = x./ -o x"$DUMPDIR" = x. ]; then
	DUMPDIR="$DEFAULT_DUMPDIR"
fi

TARPREFIX="`hostname`.`domainname`_pgsql"

# Archive file rights and owner, try to set...
# chowner may fail so we try him after rights
[ x"$CHMOD_OWNER" = x ]   && CHMOD_OWNER="$PGSQL_USER:postgres"
[ x"$CHMOD_RIGHTS" = x ] && CHMOD_RIGHTS="640"

# May take as environment variables for security, or on command-line:
# PGSQL_EXP_USER PGSQL_EXP_PASS PGSQL_EXP_DBNAME

# Don't let maintenance script break server's real works
[ x"$COMPRESS_NICE" = x ] && COMPRESS_NICE=17

do_help() {
	echo "Utility:	$AGENTNAME"
	echo "	$AGENTDESC"

	echo "Usage: $0 [-c pgsqlprofile] [-d dumpdir] [-n prefix] [-N nice] [-alldb] [-ou pgsqluser] [-op pgsqlpass] [-od pgsqldbname]"
	echo "Connection can be passed via env vars PGSQL_EXP_USER PGSQL_EXP_PASS PGSQL_EXP_DBNAME"
        echo "	nice		renice to priority nice before compression ($COMPRESS_NICE)"
        echo "  -alldb		use pg_dumpall to make a big single dump"
	echo "	pgsqlprofile	config file for env vars, set to '' to use exported vars"
	echo "	dumpdir		place temporary and resulting files to dumpdir, otherwise"
	echo "			uses current dir or $DEFAULT_DUMPDIR"
	echo "	prefix		tar file base name (suffix is _user-sid-date.tar.gz)"
	echo "		may contain a dir to place tars to a different place relative to dumpdir"
	echo "		default is $TARPREFIX"
}

# Params for lockfile
BUGMAIL="postmaster"
HOSTNAME=`hostname`

# TODO Lockfile name should depend on params (dir)
LOCK_BASE="/tmp/$AGENTNAME.lock"
# Set WAIT_C=0 to skip waits
WAIT_C=5
WAIT_S=15

VERBOSE=no

ALLDB=no

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
        COSAS_BINDIR=`pwd`
fi

# Set a default compressor (GNU zip from PATH)
# and try to source the extended list of compressors
COMPRESSOR_BINARY="gzip"
COMPRESSOR_SUFFIX=".gz"
COMPRESSOR_OPTIONS="-c"
[ x"$COMPRESSOR_PREFERENCE" = x ] && \
    COMPRESSOR_PREFERENCE="pigz gzip pbzip2 bzip2 cat"
[ -s "$COSAS_BINDIR/compressor_list.include" -a \
  -s "$COSAS_BINDIR/compressor_choice.include" ] && \
    . "$COSAS_BINDIR/compressor_list.include"

# Source optional config files
[ x"$COSAS_CFGDIR" = x ] && COSAS_CFGDIR="$COSAS_BINDIR/../etc"
if [ -d "$COSAS_CFGDIR" ]; then
    [  -f "$COSAS_CFGDIR/COSas.conf" ] && \
        . "$COSAS_CFGDIR/COSas.conf"
    [  -f "$COSAS_CFGDIR/`basename "$0"`.conf" ] && \
        . "$COSAS_CFGDIR/`basename "$0"`.conf"
fi

### Include this after config files, in case of RUNLEVEL_NOKICK mask override
RUN_CHECKLEVEL=""
[ -s "$COSAS_BINDIR/runlevel_check.include" ] &&
    . "$COSAS_BINDIR/runlevel_check.include" &&
    block_runlevel

GOTWORK=0
while [ $# -gt 0 ]; do
	case "$1" in
		-h) do_help; exit 0;;
		-v) VERBOSE=-v;;
		-alldb) ALLDB=yes ;;
		-ou) PGSQL_EXP_USER="$2"; shift;;
		-op) PGSQL_EXP_PASS="$2"; shift;;
		-od) PGSQL_EXP_DBNAME="$2"; shift;;
		-c) PGSQL_PROFILE="$2"; shift;;
		-d) DUMPDIR="$2"; shift;;
		-n) TARPREFIX="$2"; shift;;
                -N) COMPRESS_NICE="$2"; shift;;
		*) echo "Unknown param:	$1" >&2;;
	esac
	shift
done

# Checkers
if [ "$VERBOSE" != no ]; then
	echo "My params: ou=$PGSQL_EXP_USER op=$PGSQL_EXP_PASS os=$PGSQL_EXP_DBNAME c=$PGSQL_PROFILE d=$DUMPDIR n=$TARPREFIX"
fi

if [ x"$ALLDB" = xyes ]; then
	PGSQL_DUMPOPTIONS="$PGSQL_DUMPOPTIONS_ALLDB"
	PGSQL_DUMPBIN="$PGSQL_DUMPBIN"all
	PGSQL_EXP_DBNAME=""
fi

if [ x"$PGSQL_PROFILE" != x ]; then
	# May be unset to use caller's settings
	if [ -s "$PGSQL_PROFILE" ]; then
		. "$PGSQL_PROFILE"
	fi
fi

if [ x"$PGSQL_HOME" = x ]; then
	echo "PGSQL_HOME not configured! Aborting..." >&2
	exit 1
fi

if [ ! -x "$PGSQL_DUMPBIN" ]; then
	echo "PGSQL_DUMPBIN '$PGSQL_DUMPBIN' not executable! Aborting..." >&2
	exit 1
fi

if [ x"$PGSQL_EXP_USER" = x ]; then
	#PGSQL_EXP_USER="$PGSQL_USER"
	#PGSQL_EXP_USER=`id | sed 's/uid=[^(]*(\([^)]*\).*$/\1/'`
	echo "PGSQL_EXP_USER not configured! Hoping for OS auth..." >&2
	#exit 1
fi

if [ x"$PGSQL_EXP_PASS" = x ]; then
	### Can it be just empty?
	echo "PGSQL_EXP_PASS not configured! Hoping for OS auth..." >&2
	#exit 1
fi

if [ x"$PGSQL_EXP_DBNAME" = x -a x"$ALLDB" != xyes ]; then
	PGSQL_EXP_DBNAME="$PGSQL_DBNAME"
	if [ x"$PGSQL_EXP_DBNAME" = x ]; then
		echo "PGSQL_DBNAME undefined! Aborting..." >&2
		exit 1
	else
		echo "Using default PGSQL_DBNAME '$PGSQL_DBNAME'" >&2
	fi
fi

if [ x"$ALLDB" != xyes ]; then
	LOCK="$LOCK_BASE.$PGSQL_EXP_DBNAME.$PGSQL_EXP_USER"
else
        LOCK="$LOCK_BASE.alldb"
fi

if [ "$VERBOSE" != no ]; then
	echo "My params: lock=$LOCK"
fi

# Check LOCKfile
if [ -f "$LOCK" ]; then
    OLDPID=`head -n 1 "$LOCK"`
    TRYOLDPID=$(ps -ef | grep `basename $0` | grep -v grep | awk '{ print $2 }' | grep "$OLDPID")
    if [ x"$TRYOLDPID" != x ]; then

        LF=`cat "$LOCK"`

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
    fi
fi

echo "$$" > "$LOCK"

if [ x"$COMPRESS_NICE" != x ]; then
        echo "Setting process priority for compressing: '$COMPRESS_NICE'"
        renice "$COMPRESS_NICE" $$
fi

# More checkers, may hang if dirs are remote
# TODO: employ timerun.sh
if [ ! -d "$DUMPDIR" -o ! -w "$DUMPDIR" ]; then
	echo "'$DUMPDIR' inaccessible as dump dir, trying to use $DEFAULT_DUMPDIR" >&2
	DUMPDIR="$DEFAULT_DUMPDIR"
fi

if [ ! -d "$DUMPDIR" -o ! -w "$DUMPDIR" ]; then
	echo "'$DUMPDIR' inaccessible as dump dir, aborting..." >&2
	rm -f "$LOCK"
	exit 1
fi

if [ ! -d "$PGSQL_HOME" -o ! -x ""$PGSQL_DUMPBIN"" ]; then
	echo "PGSQL_HOME not useful or not a directory ($PGSQL_HOME)! Aborting..." >&2
	rm -f "$LOCK"
	exit 1
fi

# Try to source and select the actual compressor and its options
[ -s "$COSAS_BINDIR/compressor_list.include" -a \
  -s "$COSAS_BINDIR/compressor_choice.include" ] && \
    . "$COSAS_BINDIR/compressor_choice.include"

### Do some work now...
if ! cd "$DUMPDIR" ; then
	echo "'$DUMPDIR' inaccessible as dump dir, aborting..." >&2
	rm -f "$LOCK"
	exit 1
fi

# Create the export file

if [ x"$ALLDB" != xyes ]; then
	PGSQLEXPFILE="pgdump_${PGSQL_EXP_USER}-${PGSQL_EXP_DBNAME}.sql"
	PGSQLLOGFILE="pgdump_${PGSQL_EXP_USER}-${PGSQL_EXP_DBNAME}.log"
	TIMESTAMP="`TZ=UTC /bin/date +%Y%m%dT%H%M%SZ`"
	TARGZFILENAME="${TARPREFIX}_${PGSQL_EXP_USER}-${PGSQL_EXP_DBNAME}-${TIMESTAMP}.tar$COMPRESSOR_SUFFIX"
else
        PGSQLEXPFILE="pgdump-alldb.sql"
        PGSQLLOGFILE="pgdump-alldb.log"
        TIMESTAMP="`TZ=UTC /bin/date +%Y%m%dT%H%M%SZ`"
        TARGZFILENAME="${TARPREFIX}-alldb-${TIMESTAMP}.tar$COMPRESSOR_SUFFIX"
fi

# Prepare the export dump file
# It can pre-exist, it can even be a pipe (for transparent gzip, netcat, etc)
if touch "$PGSQLEXPFILE"; then
    chmod "$CHMOD_RIGHTS" "$PGSQLEXPFILE"
    chown "$CHMOD_OWNER" "$PGSQLEXPFILE"

    chmod +w "$PGSQLEXPFILE"

    # Ignore interaction if i.e. password is bad
    # info about dumped tables goes to stderr so we have to quench it completely

###    echo "dump: `pwd`"
    su - "$PGSQL_USER" -c "$PGSQL_DUMPBIN $PGSQL_DUMPOPTIONS \
	    ${PGSQL_EXP_USER:+--username="$PGSQL_EXP_USER"}\
	    ${PGSQL_EXP_PASS:+--password="$PGSQL_EXP_PASS"} \
	    $PGSQL_EXP_DBNAME" \
	    > "$PGSQLEXPFILE" 2>"$PGSQLLOGFILE"
    RESULT_1=$?

    chmod "$CHMOD_RIGHTS" "$PGSQLEXPFILE"
else
    echo "`date`: $0: Can't create dump file "$TARGZFILENAME".__WRITING__" >&2
    RESULT_1=1
fi

if [ x"$VERBOSE" != x-v ]; then
	VERBOSE=""
else
	VERBOSE=v
fi

# Prepare the archive file
if touch "$TARGZFILENAME".__WRITING__; then
    chmod "$CHMOD_RIGHTS" "$TARGZFILENAME".__WRITING__
    chown "$CHMOD_OWNER" "$TARGZFILENAME".__WRITING__

###    echo "tar: `pwd`"
    # Compress it and remove source dump files
    # In this simple task we can rely on standard solaris tar, using relative dirs
    tar ${VERBOSE}cf - "$PGSQLEXPFILE" "$PGSQLLOGFILE" \
	| $COMPRESSOR_BINARY $COMPRESSOR_OPTIONS > "$TARGZFILENAME".__WRITING__ \
	&& mv "$TARGZFILENAME".__WRITING__ "$TARGZFILENAME"
    RESULT_2=$?
else
    echo "`date`: $0: Can't create dump file "$TARGZFILENAME".__WRITING__" >&2
    RESULT_2=1
fi

RESULT_3=-1
# Clean up if tar is ok; leave files if it failed 
if [ $RESULT_2 = 0 ]; then
	echo "$TARGZFILENAME" 2>/dev/null >&3
	### This might fail if no reader opened FD3

	rm -f "$PGSQLEXPFILE" "$PGSQLLOGFILE"
	RESULT_3=$?
fi

RESULT=$(($RESULT_1+$RESULT_2))
if [ "$RESULT_3" -ge 0 ]; then
	RESULT=$(($RESULT+$RESULT_3))
fi

if [ "$RESULT" != 0 ]; then
	echo "ERROR occured (exit status: exp=$RESULT_1, targz=$RESULT_2, rm=$RESULT_3)" >&2
fi

# Be nice, clean up
rm -f "$LOCK"

exit $RESULT
