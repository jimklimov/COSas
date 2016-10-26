#!/bin/sh

### $Id: dumper-sundsee6.sh,v 1.39 2013/12/04 14:53:28 jim Exp $
### Two scripts for backup of DSEE merged Nov 2013 by Jim Klimov, COS&HT
### Functionality differs based on filename (presence of "-ldif"), config
### files are also quite possible.
###
### dumper-sundsee6.sh and dumper-sundsee7.sh
### (C) Nov 2007-Nov 2013 by Jim Klimov, COS&HT
### Creates a binary dump of Sun Directory Server 6.x or 7.0 LDAP database
### Default Sun DSEE online dump method is a clone of several database files;
### this script creates a single archive and can copy it to (remote) DUMPDIR
### Also saves config/ and alias/ directories if available, for complete backup
###
### dumper-sundsee6-ldif.sh and dumper-sundsee7-ldif.sh
### (C) Jan 2009-Nov 2013 by Jim Klimov, COS&HT
### Creates a dump of Sun Directory Server 6.x and 7.0 data as an LDIF file
### This script further creates a single compressed archive of this LDIF and
### DSINSTANCE config/ and alias/ dirs, and can copy it to (remote) DUMPDIR

### For use from cron like this:
### 5 * * * *  [ -x /opt/COSas/bin/dumper-sundsee6.sh ] && /opt/COSas/bin/dumper-sundsee6.sh
### 15 * * * * [ -x /opt/COSas/bin/dumper-sundsee6-ldif.sh ] && /opt/COSas/bin/dumper-sundsee6-ldif.sh
### 7 * * * *  [ -x /opt/COSas/bin/dumper-sundsee6-ads.sh ] && /opt/COSas/bin/dumper-sundsee6-ads.sh
### 17 * * * * [ -x /opt/COSas/bin/dumper-sundsee6-ads-ldif.sh ] && /opt/COSas/bin/dumper-sundsee6-ads-ldif.sh
### 3 * * * *  [ -x /opt/COSas/bin/dumper-sundsee6-dps1.sh ] && /opt/COSas/bin/dumper-sundsee6-dps1.sh
### 4 * * * *  [ -x /opt/COSas/bin/dumper-sundsee7-agent.sh ] && /opt/COSas/bin/dumper-sundsee7-agent.sh

###########################################################################
### Many symlinks can point to this one script with application logic in
### order to pull different configurations and backup different services.
### For DS instances, it is possible to use same carefully written config
### files for both backup and export methods.
### Probable overridables: REMOVEORIG REMOVELOCAL DSINSTANCE
###	DUMPDIR_BASE WORKDIR_BASE
### Possible overrides (esp. legacy configs): DUMPDIR WORKDIR (ex BASEDIR)
###	DSINSTHOST DUMPFILEBASE ARCHFILE
### Less probable: LOCK DSCOMPTYPE DSBACKUPMODE DSINSTBASE DSINSTBASESUB
### For LDIF exports: LDAP_SUFFIXES or legacy LDAPROOT LDAPSTD LDAPORGS_DN

### Each invokation is "locked" to only run once at a time.
[ x"$LOCK" = x ] && LOCK="/tmp/`basename "$0"`.`dirname "$0" | sed 's/\//_/g'`.lock"

### Timestamp, if available
TS="`TZ=UTC /bin/date -u +%Y%m%dT%H%M%SZ`" || TS="last"
[ x"$extTS" != x ] && TS="$extTS"

### Name of a DSEE component instance, such as "dsins1", "dps1", "ads", "agent"
#[ x"$DSINSTANCE" = x ] && DSINSTANCE="dsins1"
### Guess from script (symlink) filename
case "`basename $0`" in
	*[Aa][Dd][Ss]*)
		[ x"$DSINSTANCE" = x ] && DSINSTANCE="ads"
		[ x"$DSCONF_PARAMS" = x ] && DSCONF_PARAMS="-p 3998 -e -i"
		[ x"$CHMOD_OWNER_TEMPDIR" = x ] && CHMOD_OWNER_TEMPDIR=noaccess:noaccess
		;;
	*[Dd][Ss][Cc][Cc]*|*[Aa][Gg][Ee][Nn][Tt]*)
		[ x"$DSINSTANCE" = x ] && DSINSTANCE="agent"
		;;
	*[Dd][Pp][Ss]*)
		if [ x"$DSINSTANCE" = x ]; then
			DSINSTANCE="`basename "$0" | sed 's/^.*[Dd][Pp][Ss]\([^\.\-]*\)[\.\-].*$/dps\1/'`" || \
			    DSINSTANCE=""
			[ x"$DSINSTANCE" = x"`basename "$0"`" ] && \
			    DSINSTANCE=""
		fi
		[ x"$DSINSTANCE" = x ] && DSINSTANCE="dps1"
		;;
	*)
		if [ x"$DSINSTANCE" = x ]; then
			DSINSTANCE="`basename "$0" | sed 's/^.*[Dd][Ss][Ii][Nn][Ss]\([^\.\-]*\)[\.\-].*$/dsins\1/'`" || \
			    DSINSTANCE=""
			[ x"$DSINSTANCE" = x"`basename "$0"`" ] && \
			    DSINSTANCE=""
		fi
		[ x"$DSINSTANCE" = x ] && DSINSTANCE="dsins1"
		;;
esac

### Flag to remove the temporary directory with dumped data
[ x"$REMOVEORIG" = x ] && REMOVEORIG=Y

### Flag to remove the local archive (after moving to final storage)
[ x"$REMOVELOCAL" = x ] && REMOVELOCAL=N

### Where the final backups reside (may be external NFS share)
[ x"$DUMPDIR_BASE" = x ] && DUMPDIR_BASE="/DUMP/backups/ldap"

### Where local (working) copies of the dumps are stored, optionally
### these are removed after relocation to final storage
[ x"$WORKDIR_BASE" = x ] && WORKDIR_BASE="/var/opt/backups/ldap"

### Name of the DSEE instance host
[ x"$DSINSTHOST" = x ] && DSINSTHOST="`hostname`.`domainname`"

### Local filesystem path which contains DSEE component instances
[ x"$DSINSTBASE" = x ] && for D in \
	/var/opt/SUNWdsee7 \
	/var/opt/SUNWdsee \
	/var/SUNWdsee \
	/opt/SUNWdsee/var \
; do
	[ x"$DSINSTBASE" = x -a -d "$D" ] && DSINSTBASE="$D"
done
### See below
#DSINSTBASESUB="dcc"

get_DSCOMPTYPE() {
	_D=""
	case "$1" in
		*[Dd][Ss]*|*[Ii][Nn][Ss]*|*[Aa][Dd][Ss]*)
			_D="ds" ;;
		*[Dd][Pp][Ss]*|*[Pp][Rr][Oo][Xx][Yy]*)
			_D="dps" ;;
		*[Aa][Gg][Ee][Nn][Tt]*|*[Dd][Ss][Cc][Cc]*)
			_D="dsccagent" ;;
		*)	if [ x"$1" != x ]; then
				echo "=== WARNING: Overriding invalid value of DSCOMPTYPE='$1''..." >&2
				_D=""
			fi ;;
	esac
	echo "$_D"
	[ x"$_D" != x ]
}

get_DSBACKUPMODE() {
	_D=""
	case "$1" in
		*[Ll][Dd][Ii][Ff]*|*[Ee][Xx][Pp][Oo][Rr][Tt]*)
			_D="export" ;;
		*[Bb][Aa][Cc][Kk][Uu][Pp]*)
			_D="backup" ;;
		*)	if [ x"$1" != x ]; then
				echo "=== WARNING: Overriding invalid value of DSBACKUPMODE='$1''..." >&2
				_D=""
			fi ;;
	esac
	echo "$_D"
	[ x"$_D" != x ]
}

initializeInstNames() {
	### This routine initializes variables based on $DSINSTANCE
	### This is called after inclusion of config files (if any), but also can
	### be called from included config files to reset the paths from defaults

	### Type of a DSEE component program: "DS", "DPS" or "AGENT"
	DSCOMPTYPE="`get_DSCOMPTYPE "$DSCOMPTYPE"`" || \
	DSCOMPTYPE="`get_DSCOMPTYPE "$DSINSTANCE"`" || \
	DSCOMPTYPE="`get_DSCOMPTYPE "$0" 2>/dev/null`" || \
	DSCOMPTYPE="ds"
	
	### Type of DSEE DS instance backup: "export" to LDIF or "backup" of DB files
	DSBACKUPMODE="`get_DSBACKUPMODE "$DSBACKUPMODE"`" || \
	DSBACKUPMODE="`get_DSBACKUPMODE "$0" 2>/dev/null`" || \
	DSBACKUPMODE="backup"

	[ x"$DSINSTBASESUB" = x ] && case "$DSINSTANCE" in
		*[Aa][Dd][Ss]*|*[Dd][Ss][Cc][Cc]*|*[Aa][Gg][Ee][Nn][Tt]*)
			for D in dcc/ dscc6/dcc; do
				[ -d "$DSINSTBASE/$D" ] && DSINSTBASESUB="$D"
			done ;;
		*dsins*|*dps*)	;;
	esac

	### Where the instance files are located
	[ x"$1" = x-f -o x"$DSINSTDIR" = x ] && \
		DSINSTDIR=`echo "$DSINSTBASE/$DSINSTBASESUB/$DSINSTANCE" | sed 's,//,/,g'`

	### Where the final backups reside (may be external NFS share)
	[ x"$1" = x-f -o x"$DUMPDIR" = x ] && \
		DUMPDIR="$DUMPDIR_BASE/$DSINSTANCE"
	### Where local (working) copies of the dumps are stored, optionally
	### these are removed after relocation to final storage.
	### Legacy variable: "BASEDIR" (overrides auto if defined), now "WORKDIR"
	if [ x"$BASEDIR" != x -a -d "$BASEDIR" ]; then
		WORKDIR="$BASEDIR"
	else
		[ x"$1" = x-f -o x"$BASEDIR" = x ] && \
			WORKDIR="$WORKDIR_BASE/$DSINSTANCE"
	fi
	### How the archive file (before compression) would be called
	[ x"$1" = x-f -o x"$DUMPFILEBASE" = x ] && \
		DUMPFILEBASE="${DSINSTHOST}_${DSCOMPTYPE}${DSBACKUPMODE}-$DSINSTANCE-$TS"
}

### Don't let maintenance script break server's real works
[ x"$COMPRESS_NICE" = x ] && COMPRESS_NICE=17

### These may be used to set the server instance port and other options
[ x"$DSCONF_PARAMS" = x ] && DSCONF_PARAMS="-e -i"
### To export as long-line LDIF set
#DSCONF_PARAMS="-f output-not-folded"
### To export different suffixes to individual files
#DSCONF_PARAMS="-f multiple-output-file"

### Path to Sun DSEE 6.x or 7.x dsconf utility
DSCONF_LIST="/opt/SUNWdsee/ds6/bin/dsconf /opt/SUNWdsee7/bin/dsconf /opt/SUNWdsee/bin/dsconf"
for F in $DSCONF_LIST ; do
    [ x"$DSCONF" = x -o ! -x "$DSCONF" ] && [ -x "$F" ] && DSCONF="$F"
done
DSADM_LIST="/opt/SUNWdsee/ds6/bin/dsadm /opt/SUNWdsee7/bin/dsadm /opt/SUNWdsee/bin/dsadm"
for F in $DSADM_LIST ; do
    [ x"$DSADM" = x -o ! -x "$DSADM" ] && [ -x "$F" ] && DSADM="$F"
done

### Path to Sun DSEE 6.x or 7.x DPS dpconf and dpadm utilities
DPCONF_LIST="/opt/SUNWdsee/ds6/bin/dpconf /opt/SUNWdsee7/bin/dpconf /opt/SUNWdsee/bin/dpconf"
for F in $DPCONF_LIST ; do
    [ x"$DPCONF" = x -o ! -x "$DPCONF" ] && [ -x "$F" ] && DPCONF="$F"
done
DPADM_LIST="/opt/SUNWdsee/ds6/bin/dpadm /opt/SUNWdsee7/bin/dpadm /opt/SUNWdsee/bin/dpadm"
for F in $DPADM_LIST ; do
    [ x"$DPADM" = x -o ! -x "$DPADM" ] && [ -x "$F" ] && DPADM="$F"
done

### Password files
[ x"$DSPASSFILE" = x -a -f "/.ds6pass" ] && DSPASSFILE="/.ds6pass"
[ x"$DSPASSFILE" = x -a -f "/.ds7pass" ] && DSPASSFILE="/.ds7pass"
[ x"$DSPASSFILE" = x -a -f "/.ps7pass" ] && DSPASSFILE="/.ps7pass"

### Archive file rights and owner, try to set...
### chowner may fail so we try him after rights
[ x"$CHMOD_OWNER" = x ] && CHMOD_OWNER=0:0
[ x"$CHMOD_RIGHTS" = x ] && CHMOD_RIGHTS=600

### Temporary directory should be accessible by the server user
### For a default ADS installation this may be noaccess:noaccess
[ x"$CHMOD_OWNER_TEMPDIR" = x ] && CHMOD_OWNER_TEMPDIR="$CHMOD_OWNER"
[ x"$CHMOD_RIGHTS_TEMPDIR" = x ] && CHMOD_RIGHTS_TEMPDIR="700"

### Program to measure time consumed by operation. Okay to be absent.
TIME=
[ -x /bin/time ] && TIME=/bin/time

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
        COSAS_BINDIR="`pwd`"
fi
TIMERUN="$COSAS_BINDIR/timerun.sh"
DUMPDIR_CHECK_TIMEOUT=15

### Set a default compressor (bzip2 from PATH)
### and try to source the extended list of compressors
COMPRESSOR_BINARY="bzip2"
COMPRESSOR_SUFFIX=".bz2"
COMPRESSOR_OPTIONS="-c"
[ x"$COMPRESSOR_PREFERENCE" = x ] && \
    COMPRESSOR_PREFERENCE="pbzip2 bzip2 pigz gzip cat"
[ -s "$COSAS_BINDIR/compressor_list.include" -a \
  -s "$COSAS_BINDIR/compressor_choice.include" ] && \
    . "$COSAS_BINDIR/compressor_list.include"

### Source optional config files
[ x"$COSAS_CFGDIR" = x ] && COSAS_CFGDIR="$COSAS_BINDIR/../etc"
if [ -d "$COSAS_CFGDIR" ]; then
    [  -f "$COSAS_CFGDIR/COSas.conf" ] && \
        . "$COSAS_CFGDIR/COSas.conf"
    [  -f "$COSAS_CFGDIR/`basename "$0"`.conf" ] && \
        . "$COSAS_CFGDIR/`basename "$0"`.conf"
fi

### Try to source and select the actual compressor and its options
[ -s "$COSAS_BINDIR/compressor_list.include" -a \
  -s "$COSAS_BINDIR/compressor_choice.include" ] && \
    . "$COSAS_BINDIR/compressor_choice.include"

### Include this after config files, in case of RUNLEVEL_NOKICK mask override
RUN_CHECKLEVEL=""
[ -s "$COSAS_BINDIR/runlevel_check.include" ] && \
    . "$COSAS_BINDIR/runlevel_check.include" && \
    block_runlevel

### Prepare the variables above
initializeInstNames

### Generate typical paths and some other stuff
_INFOSTRING="$DSCOMPTYPE $DSBACKUPMODE"

DSCONF_PORT="`echo "$DSCONF_PARAMS" | sed 's/^.*\(-p [0123456789]*\) *.*$/\1/' | grep -- '-p '`" || DSCONF_PORT=""
#DPCONF_PORT="`echo "$DPCONF_PARAMS" | sed 's/^.*\(-p [0123456789]*\) *.*$/\1/' | grep -- '-p '`" || DPCONF_PORT=""

if [ x"$DSCOMPTYPE" = xds -a x"$DSCONF_PORT" = x -a \
     x"$DSINSTDIR" != x -a x"$DSINSTDIR" != x/ -a -d "$DSINSTDIR" ]; then
	DSCONF_PORT="-p `LANG=C LC_ALL=C $DSADM info $DSINSTDIR | grep 'Non-secure port:' | awk '{print $NF}'`" || DSCONF_PORT=""
	[ x"$DSCONF_PORT" != x ] && echo "=== Detected LDAP port parameter: $DSCONF_PORT" && \
		DSCONF_PARAMS="$DSCONF_PARAMS $DSCONF_PORT"
fi

if [ x"$DSCOMPTYPE" = xds -a x"$DSBACKUPMODE" = xexport ]; then
	_INFOSTRING="LDIF export"

	if [ x"$LDAP_SUFFIXES" = x ]; then
		if [ x"$LDAPROOT" != x ]; then
			### Legacy setup
			LDAPORGS_DN=""
			[ -n "$LDAPORGS" ] && LDAPORGS_DN=`for F in $LDAPORGS; do echo "    o=$F,$LDAPROOT"; done`
			LDAP_SUFFIXES="$LDAPROOT $LDAPSTD $LDAPORGS_DN"
		else
			LDAP_SUFFIXES="`$DSCONF list-suffixes $DSCONF_PORT`"
		fi
	fi

	DUMPFILE="$WORKDIR/$TS/$DUMPFILEBASE.ldif"
fi

if [ x"$DSCOMPTYPE" = xds -a x"$DSBACKUPMODE" = xbackup ]; then
	_INFOSTRING="binary dump"
fi

### Working location of the archive file (before compression):
[ x"$ARCHFILE" = x ] && \
	ARCHFILE="$WORKDIR/$DUMPFILEBASE.tar"

### Some sanity checks
if [ ! -d "$WORKDIR" ]; then
    echo "FATAL ERROR: (working) WORKDIR='$WORKDIR' is not a directory" >&2
    exit 1
fi

if [ ! -d "$DSINSTDIR" ]; then
    echo "WARN: (dsee) DSINSTDIR='$DSINSTDIR' is not a directory" >&2
fi

if [ ! -x "$DSCONF" -o x"$DSPASSFILE" = x -o ! -s "$DSPASSFILE" ]; then
    echo "FATAL ERROR: Misconfigured environment." >&2
    echo "   Check availability of DSCONF program and DSPASSFILE" >&2
    exit 1
fi
cd "$WORKDIR" || exit 1

# Check LOCKfile
if [ -f "$LOCK" ]; then
    OLDPID=`head -n 1 "$LOCK"`
    BN="`basename $0`"
    TRYOLDPID=`ps -ef | grep "$BN" | grep -v grep | awk '{ print $2 }' | grep "$OLDPID"`
    if [ x"$TRYOLDPID" != x ]; then

        LF=`cat "$LOCK"`
        echo "= SUNWdsee $_INFOSTRING aborted because another copy is running - lockfile found:
$LF
Aborting..." | wall
        exit 1
    fi
fi
echo "$$" > "$LOCK"

if [ -x "$TIMERUN" ]; then
    "$TIMERUN" "$DUMPDIR_CHECK_TIMEOUT" ls -la "$DUMPDIR/" >/dev/null
    if [ $? != 0 ]; then
        echo "WARN: (archival) DUMPDIR='$DUMPDIR' is unreachable" >&2
    fi
else
    if [ ! -d "$DUMPDIR" ]; then
        echo "WARN: (archival) DUMPDIR='$DUMPDIR' is not a directory" >&2
    fi
fi

if [ ! -d "$DSINSTDIR" ]; then
	echo "=== WARNING: instance directory not found (misconfiguration?), thus I"
	echo "===   will not back up config/ and alias/ subdirs for disaster recovery:"
	echo "===   $DSINSTDIR"
fi

echo "= Starting SunDSEE $_INFOSTRING routine: `date` (`date -u`)"
if [ x"$DEBUG" != x ]; then
	set
fi

if [ x"$COMPRESS_NICE" != x ]; then
        echo "Setting process priority for dumping and compressing: '$COMPRESS_NICE'"
        renice "$COMPRESS_NICE" $$
fi

### Prepare this dump's individual working directory
mkdir "$WORKDIR/$TS" || exit 1
chmod "$CHMOD_RIGHTS_TEMPDIR" "$WORKDIR/$TS"
chown "$CHMOD_OWNER_TEMPDIR" "$WORKDIR/$TS"
if [ ! -d "$WORKDIR/$TS" -o ! -w "$WORKDIR/$TS" ]; then
	echo "=== ERROR: Can't write to dir '$WORKDIR/$TS'" >&2
	rm -rf "$WORKDIR/$TS"
	exit 1
fi

### Prepare the archive file
if touch "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__; then
	chmod "$CHMOD_RIGHTS" "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__
	chown "$CHMOD_OWNER" "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__

	echo "=== Archive file stub prepared: $ARCHFILE$COMPRESSOR_SUFFIX.__WRITING__"

	ARCHOK=-1

	### Create new dumps unless "extTS" was defined to point to an earlier one
	RESULT=0
	[ x"$extTS" = x ] && \
	case "$DSCOMPTYPE" in
		ds) case "$DSBACKUPMODE" in
			backup)
				$TIME "$DSCONF" backup -w "$DSPASSFILE" $DSCONF_PARAMS \
					-c "$WORKDIR/$TS/db"
				RESULT=$?
				;;
			export)
				if [ x"$LDAPROOT" != x ]; then
					echo "=== `date`: Saving '$LDAPROOT\n    $LDAPSTD\n$LDAPORGS_DN'\n  to $DUMPFILE ..."
				else
					echo "=== `date`: Saving '$LDAP_SUFFIXES'\n  to $DUMPFILE ..."
				fi
				$TIME "$DSCONF" export -w "$DSPASSFILE" $DSCONF_PARAMS \
					$LDAP_SUFFIXES "$DUMPFILE"
				RESULT=$?
				;;
			esac ;;
		dps)
			### TODO: Remember if DPS was running, use this to restart below
			### But basically as of ODSEE 11.1.1.7, dpadm backup just copies
			### files - like we do
			# $TIME $DPADM stop "$DSINSTDIR" "$WORKDIR/$TS/dps"
			# $TIME $DPADM stop --exec "$DSINSTDIR" "$WORKDIR/$TS/dps"
			# $TIME $DPADM backup "$DSINSTDIR" "$WORKDIR/$TS/dps"
			# RESULT=$?
			# $TIME $DPADM start "$DSINSTDIR" "$WORKDIR/$TS/dps"
			;;
		*agent*)
			;;
	esac

	### If either extTS is provided or backup was created OK now, continue...
	if [ $RESULT = 0 -a -d "$TS" ]; then
		if [ ! -d "$TS/config" -a -d "$DSINSTDIR/config" ]; then
		    echo "=== Copying $DSINSTDIR/config ..."
		    cp -pr "$DSINSTDIR/config" "$TS" || RESULT=$?
		fi
	
		if [ ! -d "$TS/alias" -a -d "$DSINSTDIR/alias" ]; then
		    echo "=== Copying $DSINSTDIR/alias ..."
		    cp -pr "$DSINSTDIR/alias" "$TS" || RESULT=$?
		fi
	fi

	if [ $RESULT = 0 -a -d "$TS" ]; then
		echo "=== Making and compressing archive ..."
		$TIME tar cf - "$TS" | \
		    $TIME $COMPRESSOR_BINARY $COMPRESSOR_OPTIONS > \
		    "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__
		ARCHOK=$?
	fi
	
	if [ $ARCHOK = 0 ]; then
		mv -f "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__ "$ARCHFILE$COMPRESSOR_SUFFIX"
		RESULT=$?
		
		echo "=== Archive complete."
	
		if [ x"$REMOVEORIG" = xY \
			-a x"$TS" != x/ -a x"$TS" != x. \
		    ]; then
			echo "=== Removing dump directory $TS ..."
			rm -rf "$TS"
		fi
	else
		echo "`date`: $0: Can't complete dump file "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__" >&2
		rm -f "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__
		RESULT=1
	fi
else
    echo "`date`: $0: Can't create dump file "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__" >&2
    rm -f "$ARCHFILE$COMPRESSOR_SUFFIX".__WRITING__
    RESULT=2
fi

if [ -d "$DUMPDIR" -a -w "$DUMPDIR" -a -f "$ARCHFILE$COMPRESSOR_SUFFIX" -a "$RESULT" = 0 ]; then
    if [ x"$REMOVELOCAL" = xY ]; then
	echo "=== Moving archive to $DUMPDIR ..."
	mv -f "$ARCHFILE$COMPRESSOR_SUFFIX" "$DUMPDIR"
        RESULT=$?
    else
	echo "=== Copying archive to $DUMPDIR ..."
	cp -p "$ARCHFILE$COMPRESSOR_SUFFIX" "$DUMPDIR"
        RESULT=$?
    fi
fi

echo "= Finished [$RESULT]: `date`"

### Be nice, clean up
rm -f "$LOCK"

exit $RESULT
