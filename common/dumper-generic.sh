#!/bin/bash

# For use from cron (example using a symlink "dumper-named.sh"):
# 15 1 1,15 * * [ -x /opt/COSas/bin/dumper-named.sh ] && /opt/COSas/bin/dumper-named.sh -d /DUMP/regular 2>&1 | egrep -v 'Removing leading '

# dumper-generic.sh
# (C) Feb 2007-Mar 2015 by Jim Klimov, COS&HT
# $Id: dumper-generic.sh,v 1.47 2016/09/18 07:54:39 jim Exp $

# Creates a dump (compressed full archive file) of backed-up
# files, such as server configs and data files as configured
# by default patterns suggested in COS installation procedures.
# Archives may include log files as well, and thus become large.

# NOTE: For specific applications use symlinks to this script -
# based on script name it will pick default or custom configs.
# In previous versions of COSas package there were many smaller
# scripts with similar logic. To simplify maintenance they are
# now united into one script with different name-based presets.

# Since version 1.40 the script includes several methods for
# incremental dumps. For example, to archive only files changed
# in the last 3 months, run:
#   dumper-syscfg.sh -Its "`gdate -d "now -3 months" "+%Y-%m-%d %H:%M:%S"`"

AGENTNAME="`basename "$0"`"

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
        COSAS_BINDIR=`pwd`
fi

### Default values (suggestions in help-text, unused by script itself)
AGENTCRON_TIMING="15 1 1,15 * *"
AGENTCRON_PATH="/DUMP/regular"
AGENTCRON_OPTIONS=""
TESTDIRMNT=""

### Incremental archive support
INCR_MODE=off
### Previous archive or touch-file, increment is after its creation/mod date
INCR_BASEFILE=""
INCR_TOUCHFILE=""
### Explicit timestamp (see gtar manpage for --newer)
INCR_BASETIME=""

### Default value for undefined scripts
TARPREFIX="`hostname`.`domainname`_`basename "$0" .sh`"
TARNAMETAG=""

### Used for mail and filename patterns
[ x"$HOSTNAME" = x ] && HOSTNAME="`hostname`"
[ x"$DOMAINNAME" = x ] && DOMAINNAME="`domainname`" || DOMAINNAME=""
[ x"$DOMAINNAME" = x"(none)" ] && DOMAINNAME=""

case "$AGENTNAME" in
    *dumper-syscfg-sol*)
	### (C) Sep 2011 by Jim Klimov, COS&HT
	AGENTDESC="Solaris System Configs exporter: creates a compressed tar archive of main system config paths"
	AGENTCRON_TIMING="15 1 1,15 * *"
	AGENTCRON_PATH="/DUMP/regular"
        TARNAMETAG="syscfg"
	DUMPFILE_LIST_SOL="\
/etc \
/.*pass* /.*cert* \
/.ssh /root \
/var/ldap \
/var/spool/cron \
/var/svc/manifest \
/var/svc/profile \
/lib/svc/method \
/usr/local/etc \
/opt/*/etc \
/opt/*/conf* \
/opt/*/*/conf* \
/var/opt/*/conf* \
/var/opt/*/*/conf* \
/var/opt/*/*/*/conf*"
	DUMPFILE_LIST="$DUMPFILE_LIST_SOL"

	### Additions for Solaris 10+ global zone (back up local zone cfgs)
	[ -d /etc/zones -a -x /bin/zonename ] && \
	if [ x"`/bin/zonename`" = xglobal ]; then
	    if [ -x /usr/sbin/zoneadm ]; then
		for ZP in `/usr/sbin/zoneadm list -cv | awk '{print $4}' | egrep '/.+'`; do
		    for D in $DUMPFILE_LIST_SOL; do
		        DUMPFILE_LIST="$DUMPFILE_LIST $ZP/root$D"
		    done
		done
	    else
	        for D in $DUMPFILE_LIST_SOL; do
		    DUMPFILE_LIST="$DUMPFILE_LIST /zones/*/root$D /zones/*/*/root$D /zones/*/*/*/root$D"
		done
	    fi
	fi
	unset DUMPFILE_LIST_SOL

	TESTDIRMNT="/etc"
	;;
    *dumper-syscfg-lin*)
	### (C) Sep 2011 by Jim Klimov, COS&HT
	AGENTDESC="Linux System Configs exporter: creates a compressed tar archive of main system config paths"
	AGENTCRON_TIMING="15 1 1,15 * *"
	AGENTCRON_PATH="/DUMP/regular"
        TARNAMETAG="syscfg"
	DUMPFILE_LIST="\
/etc \
/.*pass* /.*cert* \
/.ssh /root \
/var/spool/cron \
/usr/local/etc \
/opt/*/etc \
/opt/*/*/conf* \
/opt/*/conf* "
	TESTDIRMNT="/etc"
	;;
    *dumper-syscfg-freebsd*)
	### (C) Feb 2013 by Jim Klimov, COS&HT
	AGENTDESC="FreeBSD System Configs exporter: creates a compressed tar archive of main system config paths"
	AGENTCRON_TIMING="15 1 1,15 * *"
	AGENTCRON_PATH="/DUMP/regular"
        TARNAMETAG="syscfg"
	DUMPFILE_LIST="\
/etc \
/.*pass* /.*cert* \
/.ssh /root \
/var/cron \
/usr/local/etc \
/opt/*/etc \
/root "
	TESTDIRMNT="/etc"
	;;
    *dumper-syscfg*)
	case "`uname -s`" in
	    FreeBSD)	"$COSAS_BINDIR/dumper-syscfg-freebsd.sh" "$@"; exit ;;
	    SunOS)	"$COSAS_BINDIR/dumper-syscfg-sol.sh" "$@"; exit ;;
	    Linux)	"$COSAS_BINDIR/dumper-syscfg-lin.sh" "$@"; exit ;;
	    *)		echo "Unknown OS; script $0 using default minimal config" ;;
	esac
	### (C) Sep 2011 by Jim Klimov, COS&HT
	AGENTDESC="Generic System Configs exporter: creates a compressed tar archive of main system config paths"
	AGENTCRON_TIMING="15 1 1,15 * *"
	AGENTCRON_PATH="/DUMP/regular"
        TARNAMETAG="syscfg"
	DUMPFILE_LIST="\
/etc \
/.*pass* /.*cert* \
/.ssh /root \
/var/spool/cron \
/usr/local/etc \
/opt/*/etc \
/opt/*/*/conf* \
/opt/*/conf* "
	TESTDIRMNT="/etc"
	;;
    *dumper-named*)
	### (C) Feb 2007-Sep 2011 by Jim Klimov, COS&HT
	AGENTDESC="named exporter: creates a compressed tar archive of NameD (BIND) DNS server config and zone files, as configured by default patterns suggested in COSbindr package"
	AGENTCRON_TIMING="15 1 1,15 * *"
	AGENTCRON_PATH="/DUMP/regular"
	TARNAMETAG="named"
	DUMPFILE_LIST="\
/etc/named.conf \
/etc/*.d/*newbind* \
/var/named \
/var/log/named"
	TESTDIRMNT="/var/named"
	;;
    *dumper-portal-all-7*)
	### (C) Mar 2007-Dec 2008 by Jim Klimov, COS&HT
	AGENTDESC="Portal7-all exporter: creates a dump of Sun Portal 7 files, mostly configs, content and soft. May include logfiles as well, and thus become large!"
	AGENTCRON_TIMING="15 1 1,15 * *"
	AGENTCRON_PATH="/mnt/nfs/DUMP"
	TARNAMETAG="portal-all"
	DUMPFILE_LIST="\
/etc/opt/SUNW* \
/var/opt/SUNW* \
/var/opt/mps \
/var/opt/oracle \
/opt/SUNW* \
/usr/ds \
/opt/fatwire \
/etc"
	TESTDIRMNT=""
	;;
    *dumper-portal-all*)
	### (C) Nov 2005-Dec 2008 by Jim Klimov, COS&HT
	AGENTDESC="Portal6-all exporter: creates a dump of Sun Portal 6 files, mostly configs, content and soft. May include logfiles as well, and thus become large!"
	AGENTCRON_TIMING="15 1 1,15 * *"
	AGENTCRON_PATH="/mnt/nfs/DUMP"
	TARNAMETAG="portal-all"
	DUMPFILE_LIST="\
/etc/opt/SUNW* \
/var/opt/SUNW* \
/var/opt/mps \
/var/opt/oracle \
/opt/SUNW* \
/usr/ds \
/opt/fatwire \
/etc"
	TESTDIRMNT="/etc/opt/SUNWps/desktop/classes"
	;;
    *dumper-portal-config*)
	### (C) Nov 2005-Dec 2008 by Jim Klimov, COS&HT
	AGENTDESC="Portal6-config exporter: creates a dump of Sun Portal 6 config files"
	AGENTCRON_TIMING="55 23 * * 1,3,5"
	AGENTCRON_PATH="/mnt/nfs/DUMP"
	TARNAMETAG="portal-config"
	DUMPFILE_LIST="\
/etc/opt/SUNW* \
/var/opt/SUNWappserver7 \
/var/opt/SUNWps/https*/portal/db \
/var/opt/SUNWps/https*/portal/web-apps \
/var/opt/SUNWps/https*/portal/robot \
/var/opt/SUNWps/https*/portal/config \
/opt/SUNWam \
/opt/SUNWps \
/opt/SUNWits \
/opt/SUNWwbsvr/docs \
/opt/SUNWwbsvr/https-*/conf* \
/opt/SUNWwbsvr/https-*/webapps \
/opt/fatwire/WEB-INF \
/etc/init.d \
/etc/rc*.d \
/etc/ds"
	TESTDIRMNT="/etc/opt/SUNWps/desktop/classes"
	;;
    *dumper-portal-content*)
	### (C) Nov 2005-Dec 2008 by Jim Klimov, COS&HT
	AGENTDESC="Portal 6 content exporter: creates a dump of frequently changed Sun Portal 6 files, mostly fatwire content and LDAP/SearchDB dirs"
	AGENTCRON_TIMING="5 7,13,19,1 * * *"
	AGENTCRON_PATH="/mnt/nfs/DUMP"
	TARNAMETAG="portal-content"
	DUMPFILE_LIST="\
/etc/opt/SUNWps/desktop \
/etc/opt/SUNWps/templates \
/var/opt/SUNWps/https-*/portal/web-apps \
/var/opt/SUNWps/https-*/portal/db \
/var/opt/SUNWps/https-*/portal/robot \
/var/opt/mps \
/opt/fatwire/SparkData"
	TESTDIRMNT="/etc/opt/SUNWps/desktop/classes"
	;;
    *dumper-portal-mps*)
	### (C) Mar 2007-Dec 2008 by Jim Klimov, COS&HT
	AGENTDESC="Portal-mps exporter: creates a compressed tar archive of MPS (Sun Portal 6 LDAP) files, mostly database content. May include logfiles as well, and thus become large!"
	AGENTCRON_TIMING="15 1 1,15 * *"
	AGENTCRON_PATH="/mnt/nfs/DUMP"
	TARNAMETAG="portal-mps"
	DUMPFILE_LIST="/var/opt/mps"
	TESTDIRMNT="/var/opt/mps"
	;;
    *dumper-sunmsg-cfg*|*dumper-sunmsg-config*)
	### (C) Oct 2011 by Jim Klimov, COS&HT
	AGENTDESC="Sun CommSuite config exporter: creates a compressed tar archive of JCS configuration and related subsystems"
	AGENTCRON_TIMING="30 3 * * *"
	AGENTCRON_PATH="/mnt/nfs/DUMP"
	TARNAMETAG="SunMsgConfig"
	DUMPFILE_LIST="\
/var/opt/SUNWwbsvr7/*/config* \
/var/opt/SUNWwbsvr7/*/docs* \
/var/opt/SUNWwbsvr7/*/data* \
/etc \
/opt/COSas \
/opt/COSmail* \
/var/spool/cron \
/var/opt/SUNWmsgsr/messaging*/config \
/var/opt/SUNWuwc/uwc \
/var/opt/SUNWuwc/webmail \
/var/opt/SUNWuwc/WEB-INF \
/var/opt/configs-messaging \
/var/opt/logs-messaging \
/opt/SUNWam/lib \
/opt/*/config \
/opt/*/*/config \
/opt/*/etc \
/opt/*/*/etc \
/opt/*.sh \
/opt/web_agents/sjsws_agent \
/root 
/.*pass \
/mail-diag.sh /mboxutil /.wadmtruststore /.profile /.bash_history"
	TESTDIRMNT="/var/opt/SUNWmsgsr"
	;;
    *dumper-oucs-cfg*|*dumper-oucs-config*)
	### (C) Apr 2013 by Jim Klimov, COS&HT
	AGENTDESC="Oracle CommSuite config exporter: creates a compressed tar archive of JCS configuration and related subsystems"
	AGENTCRON_TIMING="30 3 * * *"
	AGENTCRON_PATH="/mnt/nfs/DUMP"
	TARNAMETAG="SunMsgConfig"
	DUMPFILE_LIST="\
/var/opt/*/config* \
/var/opt/*/*/config* \
/etc \
/opt/COSas \
/opt/COSmail* \
/var/spool/cron \
/var/opt/sun/comms/*/config \
/var/opt/sun/comms/*/etc \
/etc/opt/sun/comms \
/var/opt/configs-messaging \
/var/opt/logs-messaging \
/opt/SUNWam/lib \
/opt/*/config \
/opt/*/*/config \
/opt/*/*/*/config \
/opt/*/*/*/*/config \
/opt/sun/comms/*/etc \
/opt/sun/comms/*/*/etc \
/opt/*/etc \
/opt/*/*/etc \
/opt/*.sh \
/opt/web_agents/sjsws_agent \
/root \
/.*pass \
/mail-diag.sh /mboxutil /.wadmtruststore /.profile /.bash_history"
	TESTDIRMNT="/var/opt/sun/comms"
	;;
    *dumper-sunisw*)
	AGENTDESC="Sun IdSyncWin config exporter"
	AGENTCRON_TIMING="15 1 * * *"
	AGENTCRON_PATH="/mnt/nfs/DUMP"
	TARNAMETAG="IdSyncWinConfig"
	TESTDIRMNT="/var/opt/SUNWisw"
	DUMPFILE_LIST="\
/var/opt/SUNWisw \
/opt/SUNWisw \
/var/imq \
/etc/imq \
/etc/*.d/*imq \
/etc/*.d/*isw "
	;;
    *dumper-sws7*)
	### (C) Oct 2011 by Jim Klimov, COS&HT
	AGENTDESC="Sun Web Server 7 exporter: creates a compressed tar archive of SWS configuration and plugins"
	AGENTCRON_TIMING="15 1 * * *"
	AGENTCRON_PATH="/mnt/nfs/DUMP"
	TARNAMETAG="sws7-cfg"
	DUMPFILE_LIST="/var/opt/SUNWwbsvr*/*/config* \
/var/opt/SUNWwbsvr*/*/bin \
/var/opt/SUNWwbsvr*/*/docs* \
/var/opt/SUNWwbsvr*/plugins \
/opt/SUNWwbsvr*/*/config* \
/opt/SUNWwbsvr*/*/bin \
/opt/SUNWwbsvr*/*/docs* \
/opt/SUNWwbsvr*/plugins"
	TESTDIRMNT="/opt/SUNWwbsvr7"
	;;
    *dumper-clamav*)
	AGENTDESC="COSclamav exporter: creates a full archive of clamav config and log data"
	AGENTCRON_TIMING="45 23 * * *"
	AGENTCRON_PATH="/mnt/nfs/DUMP"
	TARNAMETAG="clamav"
	TESTDIRMNT="/var/clamav"
	DUMPFILE_LIST="\
/etc/*.d/*clam* \
/opt/COSas/etc \
/usr/local/etc \
/usr/local/share/clamav \
/var/clamav \
/var/log/*clam* \
/var/spool/cron/crontabs "
	;;
    *dumper-sendmail*)
	AGENTDESC="Sendmail config exporter"
	TARNAMETAG="sendmailcfg"
	TESTDIRMNT="/etc/mail/cf"
	AGENTCRON_TIMING="46 23 * * *"
	AGENTCRON_PATH="/mnt/nfs/DUMP"
	DUMPFILE_LIST="\
/etc/*.d/*endmail* \
/etc/mail \
/etc/default/sendmail \
/var/spool/cron/crontabs \
/var/milter-greylist/greylist.db \
/opt/COSas/etc \
/opt/COSmqueue \
/opt/COSmail \
/opt/mailgroomer \
/etc/*.d/*milter*"
	;;
    *dumper-alfresco*)
	AGENTDESC="Alfresco exporter: creates a full archive of file and program data. May include logfiles as well, and thus become large!"
	TARNAMETAG="alfresco"
	TESTDIRMNT="/opt/alfresco"
	DUMPFILE_LIST="\
/etc/*.d/*alfresco* \
/etc/*.d/*cataliner* \
/etc/default/*cataliner* \
/etc/default/*tomcat* \
/etc/default/*alfresco* \
/etc/sysconfig/*cataliner* \
/etc/sysconfig/*tomcat* \
/etc/sysconfig/*alfresco* \
/export/home/alfresco \
/export/home/oouser \
/home/alfresco \
/home/oouser \
/opt/*tomcat* \
/opt/Alfresco* \
/opt/alfresco* "
	;;
    *dumper-magnolia*)
	AGENTDESC="Magnolia exporter: creates a full archive of file and program data. May include logfiles as well, and thus become large!"
	TARNAMETAG="magnolia"
	TESTDIRMNT="/opt/magnolia"
        DUMPFILE_LIST="\
/etc/*.d/*magnolia* \
/etc/*.d/*cataliner* \
/etc/default/*cataliner* \
/etc/default/*tomcat* \
/etc/default/*magnolia* \
/etc/sysconfig/*cataliner* \
/etc/sysconfig/*tomcat* \
/etc/sysconfig/*magnolia* \
/opt/*tomcat* \
/opt/magnolia*"
	;;
    *)
	AGENTDESC="WARNING: Custom configuration, no predefined information!"
	;;
esac

if [ x"$TARNAMETAG" != x ]; then
    TARPREFIX="$HOSTNAME"
    [ x"$DOMAINNAME" != x ] && TARPREFIX="$TARPREFIX.$DOMAINNAME"
    TARPREFIX="${TARPREFIX}_${TARNAMETAG}"
fi

AGENTCRON="${AGENTCRON_TIMING}	[ -x $0 ] && $0 -d ${AGENTCRON_PATH} ${AGENTCRON_OPTIONS} 2>&1 | egrep -v 'Removing leading|door ignored|Cannot stat|exit delayed|priority'"

# Don't use /tmp as DEFAULT_DUMPDIR because problems with remote NFS dump
# servers can cause swap depletion on dumped servers. Use a local dump dir
# here, or an absent dir to abort.
if [ x"$AGENTCRON_PATH" = x ]; then
    DEFAULT_DUMPDIR="/var/tmp/DUMP"
else
    DEFAULT_DUMPDIR="$AGENTCRON_PATH"
fi
DUMPDIR=`pwd`
if [ x"$DUMPDIR" = x./ -o x"$DUMPDIR" = x. ]; then
	DUMPDIR="$DEFAULT_DUMPDIR"
fi

# Archive file rights and owner, try to set...
# chowner may fail so we try him after rights
[ x"$CHMOD_OWNER" = x ] && CHMOD_OWNER=0:0
[ x"$CHMOD_RIGHTS" = x ] && CHMOD_RIGHTS=600

# Don't let maintenance script break server's real works
[ x"$COMPRESS_NICE" = x ] && COMPRESS_NICE=17

do_help() {
	echo "Utility:	$AGENTNAME"
	echo "	$AGENTDESC"
	echo '	Prints resulting archive file name to >&3'
	echo "Suggested crontab usage:"
	echo "$AGENTCRON"
	echo ""
	echo "Generic command-line usage:"
	echo "$0 [-d dumpdir] [-n prefix] [-N nice] [-qg] [-Its ts] [-Ibfa|-Ibf file] [-Itfa|-Itf file] [-Ioff]"
	echo "	dumpdir		place temporary and resulting files to dumpdir, otherwise"
	echo "			uses current dir or $DEFAULT_DUMPDIR"
	echo "	prefix		tar file base name (suffix is -date.tar.gz)"
	echo "		may contain a dir to place tars to a different place relative to dumpdir"
	echo "		default is $TARPREFIX"
        echo "	nice		renice to priority nice before compression ($COMPRESS_NICE)"
	echo "	-qg	Quiet-grep mode (grep away typical noise to reduce email from crontabs)"
	echo "Incremental mode parameters specify the oldest files to archive:"
	echo "	-Its timestamp	Provide the timestamp value (as used by gtar)"
	echo "	-Ibf filename	Base on specified file name (its mod date)"
	echo "	-Ibfa		Automatically try to find the latest dump file by its pattern"
	echo "	-Itf		Touch this file when starting the backup; use its"
	echo "			timestamp as the base for incremental backup"
	echo "	-Itfa		Automatically create the timestamp file in DUMPDIR"
	echo "			with pattern .lastbackup.\$TARPREFIX (expected unique)"
	echo "	-Ioff|--full	Create a full dump despite the -I\* settings (i.e. do touch"
	echo "			the touch-file while regularly creating a full dump as the"
	echo "			base timestamp for later incremental dumps)"
}

# Params for lockfile
[ x"$BUGMAIL" = x ] && BUGMAIL="postmaster"

[ x"$QUIETGREP" = x ] && QUIETGREP=no

# TODO Lockfile name should depend on params (dir)
LOCK_BASE="/tmp/$AGENTNAME.lock"
# Set WAIT_C=0 to skip waits
WAIT_C=5
WAIT_S=15

VERBOSE=no

# We require a GNU tar
GTAR_LIST="/opt/COSac/bin/gtar /bin/gtar /opt/sfw/bin/gtar /opt/sfw/bin/tar /usr/sfw/bin/gtar /usr/sfw/bin/tar /usr/local/bin/gtar /usr/local/bin/tar /usr/gnu/bin/tar /usr/gnu/bin/gtar"
case "`uname -s`" in
    FreeBSD)	GTAR_LIST="$GTAR_LIST /usr/bin/tar" ;;
    Linux)	GTAR_LIST="$GTAR_LIST /bin/tar" ;;
esac
GTAR=""

# We require a GNU date
GDATE_LIST="/opt/COSac/bin/gdate /usr/gnu/bin/gdate /usr/gnu/bin/date /opt/sfw/bin/gdate /usr/local/bin/date /usr/local/bin/gdate /usr/sfw/bin/gdate /usr/sfw/bin/date"
case "`uname -s`" in
    Linux)	GDATE_LIST="$GDATE_LIST /bin/date" ;;
esac
GDATE=""

TIMERUN="$COSAS_BINDIR/timerun.sh"
DUMPDIR_CHECK_TIMEOUT=15

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
		-h|--help|-help) do_help; exit 0;;
		-v) VERBOSE=-v;;
		-qg) QUIETGREP=yes ;;
		-d) DUMPDIR="$2"; shift;;
		-n) TARPREFIX="$2"; shift;;
                -N) COMPRESS_NICE="$2"; shift;;
		-I|-Ion|--incr) INCR_MODE=enabled;;
		    ### Other params may be in config file
		    ### and then this toggle enables them
		-Ioff|-full|--full)	INCR_MODE=disabled;;
		-Its) INCR_BASETIME="$2"; shift;;
		-Ibf) INCR_BASEFILE="$2"; shift;;
		-Ibfa) ### Sanity check later - find older dump
		    INCR_BASEFILE="AUTO" ;;
		-Itf) INCR_TOUCHFILE="$2"; shift;;
		-Itfa) INCR_TOUCHFILE="AUTO";;
		*) echo "Unknown param:	$1" >&2;;
	esac
	shift
done

# Checkers
if [ "$VERBOSE" != no ]; then
	echo "My params: d=$DUMPDIR n=$TARPREFIX list="
	echo "$DUMPFILE_LIST"
fi

[ x"$GTAR" = x ] && for F in $GTAR_LIST; do
	if [ -x "$F" ]; then
		GTAR="$F"
		break
	fi
done

if [ x"$GTAR" = x ]; then
	echo "Requires: GNU tar, not found among '$GTAR_LIST'" >&2
	exit 1
fi

if [ ! -x "$GTAR" ]; then
	echo "Requires: GNU tar ('$GTAR' not executable)" >&2
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

# Try to source and select the actual compressor and its options
[ -s "$COSAS_BINDIR/compressor_list.include" -a \
  -s "$COSAS_BINDIR/compressor_choice.include" ] && \
    . "$COSAS_BINDIR/compressor_choice.include"

LOCK="$LOCK_BASE.`echo "$DUMPDIR" | sed 's/\//_/g'`"

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

do_work() {
echo "$$" > "$LOCK"
trap 'rm -f "$LOCK"' 0

if [ x"$COMPRESS_NICE" != x ]; then
        echo "Setting process priority for compressing: '$COMPRESS_NICE'"
        renice "$COMPRESS_NICE" $$
fi

# More checkers, may hang if dirs are remote
if [ -x "$TIMERUN" ]; then
    "$TIMERUN" "$DUMPDIR_CHECK_TIMEOUT" ls -la "$DUMPDIR/" >/dev/null
    if [ $? != 0 ]; then
	echo "'$DUMPDIR' inaccessible as dump dir or unreachable, trying to use $DEFAULT_DUMPDIR" >&2
	DUMPDIR="$DEFAULT_DUMPDIR"
    fi
else
    if [ ! -d "$DUMPDIR" -o ! -w "$DUMPDIR" ]; then
	echo "'$DUMPDIR' inaccessible as dump dir, trying to use $DEFAULT_DUMPDIR" >&2
	DUMPDIR="$DEFAULT_DUMPDIR"
    fi
fi

if [ ! -d "$DUMPDIR" -o ! -w "$DUMPDIR" ]; then
	echo "'$DUMPDIR' inaccessible as dump dir, aborting..." >&2
	exit 1
fi

# One of the useful named dirs, if it's missing, consider the backed-up subsystem unmounted
[ x"$TESTDIRMNT" != x ] && if [ ! -d "$TESTDIRMNT" -o ! -x "$TESTDIRMNT" ]; then
	echo "$TESTDIRMNT not useful or not a directory! Aborting..." >&2
	exit 1
fi

### Do some work now...
if ! cd "$DUMPDIR" ; then
	echo "'$DUMPDIR' inaccessible as dump dir, aborting..." >&2
	exit 1
fi

### Prepare optional incremental backup variables
TIMESTAMP_PREV=""
if [ x"$INCR_MODE" != xon -a x"$INCR_MODE" != xdisabled -a \
     x"$INCR_BASETIME" != x ]; then
	INCR_PARAM="--newer=`$GDATE -u -d "$INCR_BASETIME" "+%Y-%m-%d %H:%M:%S"`"
	INCR_MODE=on
	TIMESTAMP_PREV="`TZ=UTC LANG=C $GDATE -u -d "$INCR_BASETIME" +%Y%m%dT%H%M%SZ`" || \
	    TIMESTAMP_PREV="`echo "$INCR_BASETIME" | sed 's, ,_,g'`"
fi

if [ x"$INCR_MODE" != xon -a x"$INCR_MODE" != xdisabled -a \
     x"$INCR_BASEFILE" != x ]; then
	[ x"$INCR_BASEFILE" = xAUTO ] &&
	    INCR_BASEFILE="`ls -1d "${TARPREFIX}"*".tar${COMPRESSOR_SUFFIX}" | tail -1`" || \
	    INCR_BASEFILE=""

	if [ x"$INCR_BASEFILE" != x ] && \
	   [ -f "$INCR_BASEFILE" -o -d "$INCR_BASEFILE" ]; then
	    INCR_MODE=on
	    TIMESTAMP_PREV="`TZ=UTC LANG=C $GDATE -u -r "$INCR_BASEFILE" +%Y%m%dT%H%M%SZ`" || \
		TIMESTAMP_PREV="`LANG=C ls -lad "$INCR_BASEFILE" | awk '{print $6"_"$7"_"$8}'`"
	    INCR_PARAM="--newer=`$GDATE -u -r "$INCR_BASEFILE" "+%Y-%m-%d %H:%M:%S"`"
	else
	    INCR_BASEFILE="x"
	    INCR_PARAM=""
	    INCR_MODE=off
	fi
fi

if [ x"$INCR_TOUCHFILE" != x ]; then
	[ x"$INCR_TOUCHFILE" = xAUTO ] && \
	    INCR_TOUCHFILE="$DUMPDIR/.lastbackup.${TARPREFIX}"

	if [ -f "$INCR_TOUCHFILE" -o -d "$INCR_TOUCHFILE" ]; then
	    if [ x"$INCR_MODE" != xon -a x"$INCR_MODE" != xdisabled ]; then
		### If the explicit base-time or base-file were not specified
		### (successfully), base increment is the touch-file's last
		### update (touched temp file before calling gtar, touch main
		### file after successful finish)
		INCR_MODE=on
		TIMESTAMP_PREV="`TZ=UTC LANG=C $GDATE -u -r "$INCR_TOUCHFILE" +%Y%m%dT%H%M%SZ`" || \
		    TIMESTAMP_PREV="`LANG=C ls -lad "$INCR_TOUCHFILE" | awk '{print $6"_"$7"_"$8}'`"
		INCR_PARAM="--newer=`$GDATE -u -r "$INCR_TOUCHFILE" "+%Y-%m-%d %H:%M:%S"`"
	    fi
	else
	    echo "WARN: Missing incremental touch-file '$INCR_TOUCHFILE', will try to create it" >&2
	fi

	### Try to touch the touch-file in any case
	touch "$INCR_TOUCHFILE.$$.__WRITING__" || \
	    echo "WARN: Can't touch the file '$INCR_TOUCHFILE.$$.__WRITING__'" >&2
	trap "rm -f '$INCR_TOUCHFILE.$$.__WRITING__' '$LOCK'" 0 1 2 3 15
fi

if [ x"$INCR_MODE" = xdisabled ]; then
    INCR_PARAM=""
    INCR_BASEFILE=""
    [ -f "$INCR_TOUCHFILE.$$.__WRITING__" ] && \
	echo "INFO: Requested to make a full dump and touch the touch-file '$INCR_TOUCHFILE' upon success" >&2
else
    [ x"$INCR_BASEFILE" = xx -a x"$INCR_TOUCHFILE" = x ] && INCR_BASEFILE="" && \
	echo "WARN: Missing incremental base file '$INCR_BASEFILE', making full dump!" >&2

    [ x"$INCR_TOUCHFILE" != x -a ! -f "$INCR_TOUCHFILE" ] && \
    [ x"$INCR_BASEFILE" = xx -o "$INCR_BASEFILE" = x ] && \
	echo "WARN: Missing incremental base file AND touch-file, making full dump!" >&2
fi

# Create the export file
TIMESTAMP="`TZ=UTC LANG=C $GDATE +%Y%m%dT%H%M%SZ`"
TARGZFILENAME="${TARPREFIX}-${TIMESTAMP}"
[ x"$INCR_MODE" = xon ] && \
    TARGZFILENAME="${TARGZFILENAME}.incr-since-$TIMESTAMP_PREV"
TARGZFILENAME="${TARGZFILENAME}.tar$COMPRESSOR_SUFFIX"

if [ x"$VERBOSE" != x-v ]; then
	VERBOSE=""
else
	VERBOSE=v
fi

# Prepare the archive file
if touch "$TARGZFILENAME".__WRITING__; then
    chmod "$CHMOD_RIGHTS" "$TARGZFILENAME".__WRITING__
    chown "$CHMOD_OWNER" "$TARGZFILENAME".__WRITING__

    # Compress it and remove source dump files
    # Do not let gtar return errors on failed reads (i.e. missing files)
    RESG=-1
    { $GTAR ${VERBOSE}cf - ${INCR_PARAM:+"$INCR_PARAM"} --ignore-failed-read \
	$DUMPFILE_LIST
      RESG=$?
      if [ x"$RESG" != x0 ]; then
        echo "===" >&2; echo "ERROR: gtar failed with code $RESG" >&2;
	rm -f "$TARGZFILENAME.__WRITING__"; sync; sleep 3
      fi; return $RESG; } | \
	$COMPRESSOR_BINARY $COMPRESSOR_OPTIONS > "$TARGZFILENAME".__WRITING__
    RESULT=$?
#    ls -la "$TARGZFILENAME.__WRITING__" >&2
    [ ! -s "$TARGZFILENAME.__WRITING__" ] && RESULT=$RESG

    if [ x"$RESULT" = x0 -a -s "$TARGZFILENAME.__WRITING__" ]; then
	mv "$TARGZFILENAME".__WRITING__ "$TARGZFILENAME"
	RESULT=$?
    else
	echo "`date`: $0: Failed to create dump file "$TARGZFILENAME".__WRITING__" >&2
    fi
else
    echo "ERROR: `date`: $0: Can't create dump file "$TARGZFILENAME".__WRITING__" >&2
    RESULT=-1
fi

if [ $RESULT = 0 ]; then
	echo "$TARGZFILENAME" 2>/dev/null >&3
	### This might fail if no reader opened FD3
	if [ x"$INCR_TOUCHFILE" != x ] && [ -f "$INCR_TOUCHFILE.$$.__WRITING__" ]; then
	    touch -r "$INCR_TOUCHFILE.$$.__WRITING__" "$INCR_TOUCHFILE" || \
		echo "WARN: Can't touch the file '$INCR_TOUCHFILE'" >&2
	    rm -f "$INCR_TOUCHFILE.$$.__WRITING__"
	fi
else
	echo "ERROR occured (exit status: targz=$RESULT)" >&2
	if [ x"$INCR_TOUCHFILE" != x ] && [ -f "$INCR_TOUCHFILE.$$.__WRITING__" ]; then
	    rm -f "$INCR_TOUCHFILE.$$.__WRITING__"
	fi
fi

# Be nice, clean up
rm -f "$LOCK"

trap "" 0 1 2 3 15

exit $RESULT
}

if [ x"$QUIETGREP" = xyes ]; then
    set -o pipefail 2</dev/null || true
    do_work 2>&1 | ( egrep -v 'Removing leading |socket ignored|door ignored|prio|No such |delayed|file is unchanged; not dumped' || true )
else
    do_work
fi
