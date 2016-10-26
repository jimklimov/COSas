#!/bin/sh

# dumper-pgsql-export-multiple.sh
# (C) late 2007-Dec 2008 by Jim Klimov, COS&HT
# $Id: dumper-pgsql-export-multiple.sh,v 1.10 2011/09/13 21:50:42 jim Exp $
# Script to call pgsql dumper for multiple schemas listed in a separate file
# MAY CONTAIN DEFAULT PASSWORD (see below), thus "chown 0:0; chmod 750"
# Preferably set all data in that file and/or use environment variables,
# but don't change the script body.

# For use from cron
# 0 7,13,19,1 * * * [ -x /opt/COSas/bin/dumper-pgsql-export-multiple.sh ] && /opt/COSas/bin/dumper-pgsql-export-multiple.sh

DUMPDIR=/DUMP
[ x"$LOCK" = x ] && LOCK="/tmp/`basename "$0"`.`dirname "$0" | sed 's/\//_/g'`.lock"

# A colon-separated list of user:pass:SID
# Lines starting with '#' are comments
# If any field is empty, takes a default set below
# CONTAINS PASSWORDS, thus "chown 0:0; chmod 640"
[ x"$PGSQL_SCHEMA_LIST" = x -a -s "/opt/COSas/etc/pgsql_schemas.txt" ] && \
    PGSQL_SCHEMA_LIST="/opt/COSas/etc/pgsql_schemas.txt"
[ x"$PGSQL_SCHEMA_LIST" = x -a -s "/etc/COSas/pgsql_schemas.txt" ] && \
    PGSQL_SCHEMA_LIST="/etc/COSas/pgsql_schemas.txt"

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
	COSAS_BINDIR=`pwd`
fi
SCRIPT="$COSAS_BINDIR/dumper-pgsql-export.sh"

# May take as environment variables for security, or on command-line:
# PGSQL_DEF_USER PGSQL_DEF_PASS PGSQL_DEF_DBNAME
#[ x"$PGSQL_DEF_USER" = x ] && PGSQL_DEF_USER=dbuser
#[ x"$PGSQL_DEF_PASS" = x ] && PGSQL_DEF_PASS=password
#[ x"$PGSQL_DEF_DBNAME" = x ]  && PGSQL_DEF_DBNAME=mydbname

# Enables more verbose/debugging output, including passwords(!)
# Not for automated use!
VERBOSE=""

# Configuration file for pgsql environment variables; passed to dumper
# Overrides env var defaults exported by caller, may be turned off
#PGSQL_PROFILE_PARAM="-o /opt/pgsql/.profile"
PGSQL_PROFILE_PARAM=""

# TAR-file prefix; passed to dumper
#TARPREFIX_PARAM="-n `hostname`.`domainname`_pgsql"
TARPREFIX_PARAM=""

# Don't let maintenance script break server's real works
[ x"$COMPRESS_NICE" = x ] && COMPRESS_NICE=17

do_help() {
        echo "Utility:  $AGENTNAME"
        echo "  $AGENTDESC"

        echo "Usage: $0 [-c pgsqlprofile] [-d dumpdir] [-n prefix] [-N nice] [-alldb] [-ou pgsqluser] [-op pgsqlpass] [-od pgsqldbname] [-f schemalist]"
        echo "Connection can be passed via env vars PGSQL_EXP_USER PGSQL_EXP_PASS PGSQL_EXP_DBNAME"
        echo "	nice		renice to priority nice before compression ($COMPRESS_NICE)"
	echo "  -alldb		dump all databases to one large file as well as individually"
        echo "  pgsqlprofile	config file for env vars, set to '' to use exported vars"
        echo "  dumpdir         place temporary and resulting files to dumpdir, otherwise"
        echo "                  uses current dir or /tmp; default $DUMPDIR"
        echo "  prefix          tar file base name (suffix is _user-dbname-date.tar.gz)"
        echo "          may contain a dir to place tars to a different place relative to dumpdir"
        echo "          default is in $SCRIPT"
	echo "  schemalist	text file with a colon-separated triplet of schemas to dump"
	echo "		format 'user:pass:dbname'"
	echo "		default is $PGSQL_SCHEMA_LIST"
}

ALLDB=no

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
                -h) do_help; exit 0;;
                -v) VERBOSE="-v";;
                -ou) PGSQL_DEF_USER="$2"; shift;;
                -op) PGSQL_DEF_PASS="$2"; shift;;
                -od) PGSQL_DEF_DBNAME="$2"; shift;;
                -f) PGSQL_SCHEMA_LIST="$2"; shift;;
                -c) PGSQL_PROFILE_PARAM="$1 $2"; shift;;
                -d) DUMPDIR="$2"; shift;;
                -n) TARPREFIX_PARAM="$1 $2"; shift;;
                -N) COMPRESS_NICE="$2"; shift;;
		-alldb) ALLDB=yes;;
                *) echo "Unknown param: $1" >&2;;
        esac
        shift
done

[ -x "$SCRIPT" ] || { echo "Script $SCRIPT not found" >&2; exit 1; }

if [ x"$ALLDB" = xyes ]; then
    echo "=== Dumping all pgsql databases into one large dump..."
    [ x"$PGSQL_EXP_PASS" = x ] && PGSQL_EXP_PASS="$PGSQL_DEF_PASS" && export PGSQL_DEF_PASS
    [ x"$PGSQL_EXP_USER" = x ] && PGSQL_EXP_USER="$PGSQL_DEF_USER" && export PGSQL_DEF_USER
    "$SCRIPT" $VERBOSE $PGSQL_PROFILE_PARAM $TARPREFIX_PARAM -d "$DUMPDIR" -alldb
fi

[ -s "$PGSQL_SCHEMA_LIST" ] || { echo "Schema list file $PGSQL_SCHEMA_LIST not found or empty" >&2; exit 1; }

# Check LOCKfile
if [ -f "$LOCK" ]; then
    OLDPID=`head -n 1 "$LOCK"`
    BN="`basename $0`"
    TRYOLDPID=`ps -ef | grep "$BN" | grep -v grep | awk '{ print $2 }' | grep "$OLDPID"`
    if [ x"$TRYOLDPID" != x ]; then

        LF=`cat "$LOCK"`

        echo "= PgSQL multiple dump aborted because another copy is running - lockfile found:
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

grep ':' "$PGSQL_SCHEMA_LIST" | egrep -v '^#' | while read LINE; do
    PGSQL_EXP_USER="`echo "$LINE" | awk -F: '{print $1}'`"
    PGSQL_EXP_PASS="`echo "$LINE" | awk -F: '{print $2}'`"
    PGSQL_EXP_DBNAME="`echo "$LINE" | awk -F: '{print $3}'`"

    case x"$PGSQL_EXP_DBNAME" in
	x|x#*)
	    # Malformed entry or comment, skip
	    ;;
	x*)
    	    #[ x"$PGSQL_EXP_PASS" = x ] && PGSQL_EXP_PASS="$PGSQL_DEF_PASS" && export PGSQL_DEF_PASS
	    #[ x"$PGSQL_EXP_USER" = x ] && PGSQL_EXP_USER="$PGSQL_DEF_USER" && export PGSQL_DEF_USER

	    if [ x"$VERBOSE" = x ]; then
	        echo "=== Dumping ${PGSQL_EXP_USER:-'default username'}/'hidden password'@$PGSQL_EXP_DBNAME ..."
	    else
		echo "=== Dumping ${PGSQL_EXP_USER:-'default username'}/${PGSQL_EXP_PASS:-'default password'}@$PGSQL_EXP_DBNAME ..."
	    fi

    	    export PGSQL_EXP_USER PGSQL_EXP_PASS PGSQL_EXP_DBNAME
	    "$SCRIPT" $VERBOSE $PGSQL_PROFILE_PARAM $TARPREFIX_PARAM -d "$DUMPDIR"
	    ;;
    esac
done

# Be nice, clean up
rm -f "$LOCK"
