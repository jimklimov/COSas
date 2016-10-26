#!/bin/bash

# dumper-mysql-export.sh
# (C) Mar 2009-Jan 2014 by Jim Klimov, COS&HT
# $Id: dumper-mysql-export.sh,v 1.18 2014/01/25 11:57:16 jim Exp $
# Creates a dump of specified mysql database schema
# Used from command-line or other scripts

AGENTNAME="`basename "$0"`"
AGENTDESC="Mysql exporter: creates a compressed tar archive, prints name to >&3"

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
        COSAS_BINDIR=`pwd`
fi

# MYSQL_HOME is the directory which contains .my.cnf with passwords, etc.
#   NB: ~/.my.cnf file refers to [cron] run owner, i.e. root homedir
# MYSQL_PROG is the directory which contains bin/ and lib/
#   NB: they may be the same strings (i.e. MYSQL_HOME contains symlinks to 
#   subdirs of program directory) and are usually the same in our setups
[ x"$MYSQL_USER" = x ] && MYSQL_USER="mysql"
[ x"$MYSQL_GROUP" = x ] && MYSQL_GROUP="mysql"
[ x"$MYSQL_HOME" = x ] && MYSQL_HOME=`getent passwd $MYSQL_USER | awk -F: '{print $6}'`
[ x"$MYSQL_HOME" = x ] && MYSQL_HOME="/opt/mysql"

if [ x"$MYSQL_PROG" = x ]; then
    for D in "$MYSQL_HOME" /usr/local /usr /opt/mysql/mysql /opt/mysql; do
	[ x"$MYSQL_PROG" = x -a -x "$D/bin/mysqldump" ] && MYSQL_PROG="$D"
    done
fi

# TODO: predefine option sets for popular MySQL versions
# Versions below denote *tested* versions for this set of options
MYSQL_DUMPOPTIONS_3_23_58="--force --add-locks --complete-insert"
MYSQL_DUMPOPTIONS_5_0_41="--force --add-locks --complete-insert 
    --add-drop-database --add-drop-table --routines --triggers  --tz-utc"

# coolstack 1.3.1 = mysql 5.1.25, webstack 1.4 = mysql 5.0.67
# also works for mysql 5.1.30
MYSQL_DUMPOPTIONS_5_1_25_extended_insert="--force --add-drop-database 
    --add-drop-table --add-locks --complete-insert --routines 
    --dump-date  --triggers  --tz-utc"
# NB: Disable --extended-insert included in --opt (use many
# inserts instead of very long lines exceeding packet size)
MYSQL_DUMPOPTIONS_5_1_25="--force --add-locks --complete-insert 
    --add-drop-database --routines --dump-date  --triggers  --tz-utc
    --skip-opt --add-drop-table --quick --create-options --lock-tables 
    --set-charset --disable-keys"
[ x"$MYSQL_DUMPOPTIONS" = x ] && \
    MYSQL_DUMPOPTIONS="$MYSQL_DUMPOPTIONS_5_1_25"

# Configuration file for mysql environment variables
# Overrides env var defaults exported by caller, may be turned off
MYSQL_PROFILE="$MYSQL_HOME/.profile"
# Don't use /tmp as DEFAULT_DUMPDIR because problems with remote NFS dump
# servers can cause swap depletion on dumped servers. Use a local dump dir
# here, or an absent dir to abort.
DEFAULT_DUMPDIR="/var/tmp/DUMP"
DUMPDIR=`pwd`
if [ x"$DUMPDIR" = x./ -o x"$DUMPDIR" = x. ]; then
	DUMPDIR="$DEFAULT_DUMPDIR"
fi

TARPREFIX="`hostname`.`domainname`-mysql"

# Archive file rights and owner, try to set...
# chowner may fail so we try him after rights
[ x"$CHMOD_OWNER" = x ]  &&  CHMOD_OWNER="$MYSQL_USER:$MYSQL_GROUP"
[ x"$CHMOD_RIGHTS" = x ] && CHMOD_RIGHTS="640"

# May take as environment variables for security, or on command-line:
# MYSQL_EXP_USER MYSQL_EXP_PASS MYSQL_EXP_DBNAME

# Don't let maintenance script break server's real works
[ x"$COMPRESS_NICE" = x ] && COMPRESS_NICE=17

do_help() {
	echo "Utility:	$AGENTNAME"
	echo "	$AGENTDESC"

	echo "Usage:	$0 [-c mysqlprofile] [-d dumpdir] [-n prefix] [-N nice] [-alldb] [-ou mysqluser] [-op mysqlpass] [-od mysqldbname]"
	echo "	$0 [-l|--list] | [-L|--list-cfg]"
	echo "Connection can be passed via env vars MYSQL_EXP_USER MYSQL_EXP_PASS MYSQL_EXP_DBNAME"
        echo "	nice		renice to priority nice before compression ($COMPRESS_NICE)"
	echo "	-alldb		pass --all-databases to mysqldump to make a big single dump"
	echo "	mysqlprofile	config file for env vars, set to '' to use exported vars"
	echo "	dumpdir		place temporary and resulting files to dumpdir, otherwise"
	echo "			uses current dir or $DEFAULT_DUMPDIR"
	echo "	prefix		tar file base name (suffix is _user-sid-date.tar.gz)"
	echo "		may contain a dir to place tars to a different place relative to dumpdir"
	echo "		default is $TARPREFIX"
	echo "	-l|--list	List all databases defined for MySQL instance and exit"
	echo "	-L|--list-cfg	List all databases defined for MySQL instance in cfg-file format and exit"
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
SHOWLIST=no

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
		-h|help|--help) do_help; exit 0;;
		-l|--list) SHOWLIST=yes ;;
		-L|--list-cfg) SHOWLIST=cfg ;;
		-v) VERBOSE=-v;;
		-ou) MYSQL_EXP_USER="$2"; shift;;
		-op) MYSQL_EXP_PASS="$2"; shift;;
		-od) MYSQL_EXP_DBNAME="$2"; shift;;
		-c) MYSQL_PROFILE="$2"; shift;;
		-d) DUMPDIR="$2"; shift;;
		-n) TARPREFIX="$2"; shift;;
                -N) COMPRESS_NICE="$2"; shift;;
		-alldb) ALLDB=yes;;
		*) echo "Unknown param:	$1" >&2;;
	esac
	shift
done

# Checkers
if [ "$VERBOSE" != no ]; then
	echo "My params: ou=$MYSQL_EXP_USER op=$MYSQL_EXP_PASS os=$MYSQL_EXP_DBNAME c=$MYSQL_PROFILE d=$DUMPDIR n=$TARPREFIX"
fi

if [ x"$MYSQL_PROFILE" != x ]; then
	# May be unset to use caller's settings
	if [ -s "$MYSQL_PROFILE" ]; then
		. "$MYSQL_PROFILE"
	fi
fi

if [ x"$MYSQL_HOME" = x ]; then
	echo "MYSQL_HOME not configured! Aborting..." >&2
	exit 1
fi

if [ x"$MYSQL_PROG" = x ]; then
	echo "MYSQL_PROG not configured! Aborting..." >&2
	exit 1
fi

if [ x"$MYSQL_EXP_USER" = x ]; then
	MYSQL_EXP_USER=`id | sed 's/uid=[^(]*(\([^)]*\).*$/\1/'`
	#echo "MYSQL_EXP_USER not configured! Hoping for ~/.my.cnf or alike..." >&2
	#exit 1
fi

if [ x"$MYSQL_EXP_PASS" = x ]; then
	### Can it be just empty?
	echo "MYSQL_EXP_PASS not configured explicitly! Hoping for ~/.my.cnf or alike..." >&2
	#exit 1
fi

if [ x"$SHOWLIST" = xyes ]; then
	$MYSQL_PROG/bin/mysql \
            ${MYSQL_EXP_USER:+--user="$MYSQL_EXP_USER"}\
            ${MYSQL_EXP_PASS:+--password="$MYSQL_EXP_PASS"} \
	    -e 'show databases;' \
	| awk '{print $1}' | fgrep -v Database
	exit $?
fi

if [ x"$SHOWLIST" = xcfg ]; then
	$MYSQL_PROG/bin/mysql \
            ${MYSQL_EXP_USER:+--user="$MYSQL_EXP_USER"}\
            ${MYSQL_EXP_PASS:+--password="$MYSQL_EXP_PASS"} \
	    -e 'show databases;' \
	| awk '{print "::"$1}' | fgrep -v "::Database"
	exit $?
fi

if [ x"$MYSQL_EXP_DBNAME" = x -a x"$ALLDB" != xyes ]; then
	MYSQL_EXP_DBNAME="$MYSQL_DBNAME"
	if [ x"$MYSQL_EXP_DBNAME" = x ]; then
		echo "MYSQL_DBNAME undefined! Aborting..." >&2
		exit 1
	else
		echo "Using default MYSQL_DBNAME '$MYSQL_DBNAME'" >&2
	fi
fi

if [ x"$ALLDB" != xyes ]; then
	LOCK="$LOCK_BASE.$MYSQL_EXP_DBNAME.$MYSQL_EXP_USER"
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

if [ ! -d "$MYSQL_PROG" -o ! -x "$MYSQL_PROG/bin/mysqldump" ]; then
	echo "MYSQL_PROG not useful or not a directory ($MYSQL_PROG)! Aborting..." >&2
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
	MYSQLEXPFILE="mydump_${MYSQL_EXP_USER}-${MYSQL_EXP_DBNAME}.sql"
	MYSQLLOGFILE="mydump_${MYSQL_EXP_USER}-${MYSQL_EXP_DBNAME}.log"
	TIMESTAMP="`TZ=UTC /bin/date +%Y%m%dT%H%M%SZ`"
	TARGZFILENAME="${TARPREFIX}_${MYSQL_EXP_USER}-${MYSQL_EXP_DBNAME}-${TIMESTAMP}.tar$COMPRESSOR_SUFFIX"
else
	MYSQLEXPFILE="mydump-alldb.sql"
	MYSQLLOGFILE="mydump-alldb.log"
	TIMESTAMP="`TZ=UTC /bin/date +%Y%m%dT%H%M%SZ`"
	TARGZFILENAME="${TARPREFIX}-alldb-${TIMESTAMP}.tar$COMPRESSOR_SUFFIX"
fi

# Prepare the export dump file
# It can pre-exist, it can even be a pipe (for transparent gzip, netcat, etc)
if touch "$MYSQLEXPFILE"; then
    chmod "$CHMOD_RIGHTS" "$MYSQLEXPFILE"
    chown "$CHMOD_OWNER" "$MYSQLEXPFILE"

    chmod +w "$MYSQLEXPFILE"

    # Ignore interaction if i.e. password is bad
    # info about dumped tables goes to stderr so we have to quench it completely

###    echo "dump: `pwd`"
    if [ x"$ALLDB" != xyes ]; then
        $MYSQL_PROG/bin/mysqldump $MYSQL_DUMPOPTIONS \
	    ${MYSQL_EXP_USER:+--user="$MYSQL_EXP_USER"}\
	    ${MYSQL_EXP_PASS:+--password="$MYSQL_EXP_PASS"} \
	    --databases $MYSQL_EXP_DBNAME \
	    > "$MYSQLEXPFILE" 2>"$MYSQLLOGFILE"
	RESULT_1=$?
    else
	$MYSQL_PROG/bin/mysqldump $MYSQL_DUMPOPTIONS \
	    ${MYSQL_EXP_USER:+--user="$MYSQL_EXP_USER"}\
	    ${MYSQL_EXP_PASS:+--password="$MYSQL_EXP_PASS"} \
	    --all-databases \
	    > "$MYSQLEXPFILE" 2>"$MYSQLLOGFILE"
	RESULT_1=$?
    fi

    chmod "$CHMOD_RIGHTS" "$MYSQLEXPFILE"
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
    tar ${VERBOSE}cf - "$MYSQLEXPFILE" "$MYSQLLOGFILE" \
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

	rm -f "$MYSQLEXPFILE" "$MYSQLLOGFILE"
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
