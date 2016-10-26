#!/bin/sh

# dumper-oracle-export-multiple.sh
# (C) late 2007-Dec 2008 by Jim Klimov, COS&HT
# $Id: dumper-oracle-export-multiple.sh,v 1.14 2011/12/30 16:50:18 jim Exp $
# Script to call oracle dumper for multiple schemas listed in a separate file
# MAY CONTAIN DEFAULT PASSWORD (see below), thus "chown 0:0; chmod 750"
# Preferably set all data in that file and/or use environment variables,
# but don't change the script body.

# For use from cron
# 0 7,13,19,1 * * * [ -x /opt/COSas/bin/dumper-oracle-export-multiple.sh ] && /opt/COSas/bin/dumper-oracle-export-multiple.sh

DUMPDIR=/DUMP
[ x"$LOCK" = x ] && LOCK="/tmp/`basename "$0"`.`dirname "$0" | sed 's/\//_/g'`.lock"

# A colon-separated list of user:pass:SID
# Lines starting with '#' are comments
# If any field is empty, takes a default set below
# CONTAINS PASSWORDS, thus "chown 0:0; chmod 640"
# Note: version in etc/ is preferred; version in /opt/COSas is deprecated
[ x"$ORACLE_SCHEMA_LIST" = x -a -s "/opt/COSas/etc/oracle_schemas.txt" ] && \
    ORACLE_SCHEMA_LIST="/opt/COSas/etc/oracle_schemas.txt"
[ x"$ORACLE_SCHEMA_LIST" = x -a -s "/opt/COSas/oracle_schemas.txt" ] && \
    ORACLE_SCHEMA_LIST="/opt/COSas/oracle_schemas.txt"
[ x"$ORACLE_SCHEMA_LIST" = x -a -s "/etc/COSas/oracle_schemas.txt" ] && \
    ORACLE_SCHEMA_LIST="/etc/COSas/oracle_schemas.txt"

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
	COSAS_BINDIR=`pwd`
fi
SCRIPT="$COSAS_BINDIR/dumper-oracle-export.sh"

# May take as environment variables for security, or on command-line:
# ORACLE_DEF_USER ORACLE_DEF_PASS ORACLE_DEF_SID
#[ x"$ORACLE_DEF_USER" = x ] && ORACLE_DEF_USER=dbuser
#[ x"$ORACLE_DEF_PASS" = x ] && ORACLE_DEF_PASS=password
#[ x"$ORACLE_DEF_SID" = x ]  && ORACLE_DEF_SID=oradbsid

# Enables more verbose/debugging output, including passwords(!)
# Not for automated use!
VERBOSE=""

# Configuration file for oracle environment variables; passed to dumper
# Overrides env var defaults exported by caller, may be turned off
#ORACLE_PROFILE_PARAM="-o /opt/oracle/.profile"
ORACLE_PROFILE_PARAM=""

# TAR-file prefix; passed to dumper
#TARPREFIX_PARAM="-n `hostname`.`domainname`_oracle"
TARPREFIX_PARAM=""

# Don't let maintenance script break server's real works
[ x"$COMPRESS_NICE" = x ] && COMPRESS_NICE=17
NICE_PARAM=""

do_help() {
        echo "Utility:  $AGENTNAME"
        echo "  $AGENTDESC"

        echo "Usage: $0 [-c oracleprofile] [-d dumpdir] [-n prefix] [-N nice] [-ou oracleuser] [-op oraclepass] [-os oraclesid] [-f schemalist]"
        echo "Connection can be passed via env vars ORACLE_EXP_USER ORACLE_EXP_PASS ORACLE_EXP_SID"
        echo "  oracleprofile   config file for env vars, set to '' to use exported vars"
        echo "  dumpdir         place temporary and resulting files to dumpdir, otherwise"
        echo "                  uses current dir or /tmp; default $DUMPDIR"
        echo "  prefix          tar file base name (suffix is _user-sid-date.tar.gz)"
        echo "          may contain a dir to place tars to a different place relative to dumpdir"
        echo "          default is in $SCRIPT"
	echo "  schemalist	text file with a colon-separated triplet of schemas to dump"
	echo "		format 'user:pass:sid'"
	echo "		default is $ORACLE_SCHEMA_LIST"
        echo "	nice		renice to priority nice before compression ($COMPRESS_NICE)"
}

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
                -ou) ORACLE_DEF_USER="$2"; shift;;
                -op) ORACLE_DEF_PASS="$2"; shift;;
                -os) ORACLE_DEF_SID="$2"; shift;;
                -f) ORACLE_SCHEMA_LIST="$2"; shift;;
                -c) ORACLE_PROFILE_PARAM="$1 $2"; shift;;
                -d) DUMPDIR="$2"; shift;;
                -n) TARPREFIX_PARAM="$1 $2"; shift;;
                -N) COMPRESS_NICE="$2"; NICE_PARAM="-N $2"; shift;;
                *) echo "Unknown param: $1" >&2;;
        esac
        shift
done

[ -s "$ORACLE_SCHEMA_LIST" ] || { echo "Schema list file $ORACLE_SCHEMA_LIST not found or empty" >&2; exit 1; }
[ -x "$SCRIPT" ] || { echo "Script $SCRIPT not found" >&2; exit 1; }

# Check LOCKfile
if [ -f "$LOCK" ]; then
    OLDPID=`head -n 1 "$LOCK"`
    BN="`basename $0`"
    TRYOLDPID=`ps -ef | grep "$BN" | grep -v grep | awk '{ print $2 }' | grep "$OLDPID"`
    if [ x"$TRYOLDPID" != x ]; then

        LF=`cat "$LOCK"`

        echo "= Oracle multiple dump aborted because another copy is running - lockfile found:
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

while IFS=":" read ORACLE_EXP_USER ORACLE_EXP_PASS ORACLE_EXP_SID; do
    case x"$ORACLE_EXP_USER" in
	x|x#*)
	    # Malformed entry or comment, skip
	    ;;
	x*)
    	    [ x"$ORACLE_EXP_PASS" = x ] && ORACLE_EXP_PASS="$ORACLE_DEF_PASS"
	    [ x"$ORACLE_EXP_SID" = x ] && ORACLE_EXP_SID="$ORACLE_DEF_SID"

	    if [ x"$VERBOSE" = x ]; then
	        echo "Dumping $ORACLE_EXP_USER/...@$ORACLE_EXP_SID ..."
	    else
		echo "Dumping $ORACLE_EXP_USER/$ORACLE_EXP_PASS@$ORACLE_EXP_SID ..."
	    fi

    	    export ORACLE_EXP_USER ORACLE_EXP_PASS ORACLE_EXP_SID
	    eval "$SCRIPT" $VERBOSE $ORACLE_PROFILE_PARAM $NICE_PARAM $TARPREFIX_PARAM -d "$DUMPDIR"
	    ;;
    esac
done < "$ORACLE_SCHEMA_LIST"

# Be nice, clean up
rm -f "$LOCK"
