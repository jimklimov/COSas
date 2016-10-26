#!/bin/sh

# dumper-mysql-export-multiple.sh
# (C) late 2007-Dec 2008 by Jim Klimov, COS&HT
# $Id: dumper-mysql-export-multiple.sh,v 1.16 2011/10/01 14:49:41 jim Exp $
# Script to call mysql dumper for multiple schemas listed in a separate file
# MAY CONTAIN DEFAULT PASSWORD (see below), thus "chown 0:0; chmod 750"
# Preferably set all data in that file and/or use environment variables,
# but don't change the script body.

# For use from cron
# 0 7,13,19,1 * * * [ -x /opt/COSas/bin/dumper-mysql-export-multiple.sh ] && /opt/COSas/bin/dumper-mysql-export-multiple.sh

DUMPDIR=/DUMP
[ x"$LOCK" = x ] && LOCK="/tmp/`basename "$0"`.`dirname "$0" | sed 's/\//_/g'`.lock"

# A colon-separated list of user:pass:SID
# Lines starting with '#' are comments
# If any field is empty, takes a default set below
# CONTAINS PASSWORDS, thus "chown 0:0; chmod 640"
[ x"$MYSQL_SCHEMA_LIST" = x -a -s "/opt/COSas/etc/mysql_schemas.txt" ] && \
    MYSQL_SCHEMA_LIST="/opt/COSas/etc/mysql_schemas.txt"
[ x"$MYSQL_SCHEMA_LIST" = x -a -s "/etc/COSas/mysql_schemas.txt" ] && \
    MYSQL_SCHEMA_LIST="/etc/COSas/mysql_schemas.txt"

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
	COSAS_BINDIR=`pwd`
fi
SCRIPT="$COSAS_BINDIR/dumper-mysql-export.sh"

# May take as environment variables for security, or on command-line:
# MYSQL_DEF_USER MYSQL_DEF_PASS MYSQL_DEF_DBNAME
#[ x"$MYSQL_DEF_USER" = x ] && MYSQL_DEF_USER=dbuser
#[ x"$MYSQL_DEF_PASS" = x ] && MYSQL_DEF_PASS=password
#[ x"$MYSQL_DEF_DBNAME" = x ] && MYSQL_DEF_DBNAME=mydbname

# Enables more verbose/debugging output, including passwords(!)
# Not for automated use!
VERBOSE=""

# Configuration file for mysql environment variables; passed to dumper
# Overrides env var defaults exported by caller, may be turned off
#MYSQL_PROFILE_PARAM="-o /opt/mysql/.profile"
MYSQL_PROFILE_PARAM=""

# TAR-file prefix; passed to dumper
#TARPREFIX_PARAM="-n `hostname`.`domainname`_mysql"
TARPREFIX_PARAM=""

# Don't let maintenance script break server's real works
[ x"$COMPRESS_NICE" = x ] && COMPRESS_NICE=17

do_help() {
        echo "Utility:  $AGENTNAME"
        echo "  $AGENTDESC"

        echo "Usage:	$0 [-c mysqlprofile] [-d dumpdir] [-n prefix] [-N nice] [-alldb] [-ou mysqluser] [-op mysqlpass] [-od mysqldbname] [-f schemalist]"
	echo "	$0 [-l|--list] | [-L|--list-cfg]"
        echo "Connection can be passed via env vars MYSQL_EXP_USER MYSQL_EXP_PASS MYSQL_EXP_DBNAME"
        echo "	nice		renice to priority nice before compression ($COMPRESS_NICE)"
	echo "	-alldb		dump all databases to one large file as well as individually"
        echo "  mysqlprofile	config file for env vars, set to '' to use exported vars"
        echo "  dumpdir         place temporary and resulting files to dumpdir, otherwise"
        echo "                  uses current dir or /tmp; default $DUMPDIR"
        echo "  prefix          tar file base name (suffix is _user-dbname-date.tar.gz)"
        echo "          may contain a dir to place tars to a different place relative to dumpdir"
        echo "          default is in $SCRIPT"
	echo "  schemalist	text file with a colon-separated triplet of schemas to dump"
	echo "		format 'user:pass:dbname'"
	echo "		default is $MYSQL_SCHEMA_LIST"
	echo "	-l|--list	List all databases defined for MySQL instance and exit"
	echo "	-L|--list-cfg	List all databases defined for MySQL instance in cfg-file format and exit"
}

ALLDB=no
SHOWLIST=no

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

while [ $# -gt 0 ]; do
        case "$1" in
                -h|help|--help) do_help; exit 0;;
		-l|--list) SHOWLIST=yes ;;
		-L|--list-cfg) SHOWLIST=cfg ;;
                -v) VERBOSE="-v";;
                -ou) MYSQL_DEF_USER="$2"; shift;;
                -op) MYSQL_DEF_PASS="$2"; shift;;
                -od) MYSQL_DEF_DBNAME="$2"; shift;;
                -f) MYSQL_SCHEMA_LIST="$2"; shift;;
                -c) MYSQL_PROFILE_PARAM="$1 $2"; shift;;
                -d) DUMPDIR="$2"; shift;;
                -n) TARPREFIX_PARAM="$1 $2"; shift;;
                -N) COMPRESS_NICE="$2"; shift;;
		-alldb) ALLDB=yes;;
                *) echo "Unknown param: $1" >&2;;
        esac
        shift
done

[ -x "$SCRIPT" ] || { echo "Script $SCRIPT not found" >&2; exit 1; }

if [ x"$SHOWLIST" = xyes ]; then
    echo "=== Listing all mysql databases and exiting..." >&2
    [ x"$MYSQL_EXP_PASS" = x ] && MYSQL_EXP_PASS="$MYSQL_DEF_PASS" && export MYSQL_EXP_PASS
    [ x"$MYSQL_EXP_USER" = x ] && MYSQL_EXP_USER="$MYSQL_DEF_USER" && export MYSQL_EXP_USER
    "$SCRIPT" $VERBOSE $MYSQL_PROFILE_PARAM --list
    exit $?
fi

if [ x"$SHOWLIST" = xcfg ]; then
    echo "=== Listing all mysql databases and exiting..." >&2
    [ x"$MYSQL_EXP_PASS" = x ] && MYSQL_EXP_PASS="$MYSQL_DEF_PASS" && export MYSQL_EXP_PASS
    [ x"$MYSQL_EXP_USER" = x ] && MYSQL_EXP_USER="$MYSQL_DEF_USER" && export MYSQL_EXP_USER
    "$SCRIPT" $VERBOSE $MYSQL_PROFILE_PARAM --list-cfg
    exit $?
fi

if [ x"$ALLDB" = xyes ]; then
    echo "=== Dumping all mysql databases into one large dump..."
    [ x"$MYSQL_EXP_PASS" = x ] && MYSQL_EXP_PASS="$MYSQL_DEF_PASS" && export MYSQL_EXP_PASS
    [ x"$MYSQL_EXP_USER" = x ] && MYSQL_EXP_USER="$MYSQL_DEF_USER" && export MYSQL_EXP_USER
    "$SCRIPT" $VERBOSE $MYSQL_PROFILE_PARAM $TARPREFIX_PARAM -d "$DUMPDIR" -alldb
fi

[ -s "$MYSQL_SCHEMA_LIST" ] || { echo "Schema list file $MYSQL_SCHEMA_LIST not found or empty" >&2; exit 1; }

# Check LOCKfile
if [ -f "$LOCK" ]; then
    OLDPID=`head -n 1 "$LOCK"`
    BN="`basename $0`"
    TRYOLDPID=`ps -ef | grep "$BN" | grep -v grep | awk '{ print $2 }' | grep "$OLDPID"`
    if [ x"$TRYOLDPID" != x ]; then

        LF=`cat "$LOCK"`

        echo "= MySQL multiple dump aborted because another copy is running - lockfile found:
$LF
Aborting..." | wall
        exit 1
    fi
fi
echo "$$" > "$LOCK"

if [ x"$COMPRESS_NICE" != x ]; then
        echo "Setting process priority for compressing: '$COMPRESS_NICE'"
        renice "$COMPRESS_NICE" $$
fi

grep ':' "$MYSQL_SCHEMA_LIST" | egrep -v '^#' | while read LINE; do
    MYSQL_EXP_USER="`echo "$LINE" | awk -F: '{print $1}'`"
    MYSQL_EXP_PASS="`echo "$LINE" | awk -F: '{print $2}'`"
    MYSQL_EXP_DBNAME="`echo "$LINE" | awk -F: '{print $3}'`"

    case x"$MYSQL_EXP_DBNAME" in
	x|x#*)
	    # Malformed entry or comment, skip
	    ;;
	x*)
    	    #[ x"$MYSQL_EXP_PASS" = x ] && MYSQL_EXP_PASS="$MYSQL_DEF_PASS" && export MYSQL_EXP_PASS
	    #[ x"$MYSQL_EXP_USER" = x ] && MYSQL_EXP_USER="$MYSQL_DEF_USER" && export MYSQL_EXP_USER

	    if [ x"$VERBOSE" = x ]; then
	        echo "=== Dumping ${MYSQL_EXP_USER:-'default username'}/'hidden password'@$MYSQL_EXP_DBNAME ..."
	    else
		echo "=== Dumping ${MYSQL_EXP_USER:-'default username'}/${MYSQL_EXP_PASS:-'default password'}@$MYSQL_EXP_DBNAME ..."
	    fi

    	    export MYSQL_EXP_USER MYSQL_EXP_PASS MYSQL_EXP_DBNAME
	    "$SCRIPT" $VERBOSE $MYSQL_PROFILE_PARAM $TARPREFIX_PARAM -d "$DUMPDIR"
	    ;;
    esac
done

# Be nice, clean up
rm -f "$LOCK"
