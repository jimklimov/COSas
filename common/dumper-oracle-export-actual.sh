#!/bin/sh

# dumper-oracle-export-actual.sh
# (C) Dec 2005-Dec 2008 by Jim Klimov, COS&HT
# $Id: dumper-oracle-export-actual.sh,v 1.9 2011/09/13 21:26:06 jim Exp $
# Sample of script to call oracle dumper
# See dumper-oracle-export-multiple.sh for a more configurable use-case

# For use from cron
# CONTAINS PASSWORDS, thus chmod 750
# 0 7,13,19,1 * * * [ -x /opt/COSas/bin/dumper-oracle-export-actual.sh ] && /opt/COSas/bin/dumper-oracle-export-actual.sh

DUMPDIR=/mnt/nfs/DUMP

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
	COSAS_BINDIR=`pwd`
fi

SCRIPT="$COSAS_BINDIR/dumper-oracle-export.sh"

ORACLE_EXP_USER=dbuser
ORACLE_EXP_PASS=password
ORACLE_EXP_SID=oradbsid

# Don't let maintenance script break server's real works
[ x"$COMPRESS_NICE" = x ] && COMPRESS_NICE=17

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

export ORACLE_EXP_USER ORACLE_EXP_PASS ORACLE_EXP_SID
[ -x "$SCRIPT" ] && "$SCRIPT" -d "$DUMPDIR"
