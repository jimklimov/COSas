#!/bin/bash

### $Id: diag-runtime.sh,v 1.20 2014/03/04 20:53:11 jim Exp $
### This script wraps verification of the system working status
### If run with parameter "regular" it only produces output if any
### errors are detected (for crontab use); may take a while to run.
### Relies on COSas package components and Solaris 10+ (zlogin, SMF).
### Can work in Linux as well.
### (C) 2013 by Jim Klimov, COS&HT

### Some settings...
FSAGENT_TIMEOUT=20
FSAGENT_FREEKB=100000
FSAGENT_FREEPCT=2
[ x"$EXCLUDEFS_RE" = x ] && EXCLUDEFS_RE="(DUMP|backup|var/cores)"
export EXCLUDEFS_RE

RUNTESTSUITE_LOCAL_DEFINED=no

### Regular tests can send email to admins...
### May be comma-separated; by default only report to crontab owner via stdout
#[ x"$BUGMAIL_RCPT" != x ] && BUGMAIL_RCPT="root"
### For internet delivery, use an existing address like "postmaster@domain.ru"
BUGMAIL_FROM="`id | sed 's/^[^(]*(\([^)]*\)).*$/\1/'`@`hostname`.`domainname`"

### Source optional config files
### In particular, a local config can define a procedure
###   runtestsuite_local()
### similar to generic tests below; should set RUNTESTSUITE_LOCAL_DEFINED=yes

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
        COSAS_BINDIR=`pwd`
fi

[ x"$COSAS_CFGDIR" = x ] && COSAS_CFGDIR="$COSAS_BINDIR/../etc"
if [ -d "$COSAS_CFGDIR" ]; then
    [  -f "$COSAS_CFGDIR/COSas.conf" ] && \
        . "$COSAS_CFGDIR/COSas.conf"
    [  -f "$COSAS_CFGDIR/`basename "$0"`.conf" ] && \
        . "$COSAS_CFGDIR/`basename "$0"`.conf"
fi

OUT_ALL=""
OUT_ERR=""
RES_ALL=0
ZONES=no
[ -x /bin/zonename -a -x /usr/sbin/zoneadm ] && ZONES=yes

[ x"$ZONES" = xyes ] && \
	ZONENAME="`zonename`" 2>/dev/null || \
	ZONENAME="global"
runtest() {
	### External variables:
	###	Z	zone name
	###	C	command+params to run for test
	###	INV	if not empty - invert the test results (0=fail)
	###		if INV=verbose - report status string
	[ x"$Z" = x ] && Z="$ZONENAME"
	if [ x"$Z" = xglobal -o x"$Z" = x"$ZONENAME" -o x"$ZONES" = xno ]; then
		echo "=== $Z: $C"
		if [ x"$REGULAR_MODE" != x1 ]; then
			eval $C
			RES=$?
		else
			OUT="`eval $C 2>&1`"
			RES=$?
		fi
	else
		if [ x"$REGULAR_MODE" != x1 ]; then
			zlogin "$Z" "echo '=== $Z: $C'; $C"
			RES=$?
		else
			OUT="`zlogin "$Z" "echo '=== $Z: $C'; $C" 2>&1`"
			RES=$?
		fi
	fi

	[ x"$REGULAR_MODE" != x1 ] || echo "$OUT"

	if [ x"$INV" != x ]; then
	    [ "$RES" = 0 ] && RES=1 || RES=0
	    if [ x"$INV" = xverbose ]; then
		[ "$RES" = 0 ] && \
		    echo "Status: OK" || \
		    echo "Status: FAIL"
	    fi
	fi

	if [ "$RES" = 0 ]; then
		RESSTR="[--OK--]"
	else
		RESSTR="[-FAIL-]"
		RES_ALL="$RES"
		[ x"$REGULAR_MODE" != x1 ] || OUT_ERR="$OUT_ERR
=== $Z: $C
$OUT
"
	fi
	OUT_ALL="$OUT_ALL
$RESSTR ($RES)	$Z	$C"
	return $RES
}

runtestsuite_generic() {
	for Z in ""; do
	for C in "[ x$ZONES = xno ] || zoneadm list -cv" \
	  "[ x$ZONES = xno ] || df -k `zpool list -H -o name`" \
	  "df -k /tmp; $COSAS_BINDIR/agent-freespace.sh /tmp" \
	; do
		runtest
	done
	done

	if [ x"$ZONES" = xyes ]; then
	for Z in `zoneadm list`; do
	for C in "$COSAS_BINDIR/agent-freespace-lfs.sh -v -k $FSAGENT_FREEKB -p $FSAGENT_FREEPCT -t $FSAGENT_TIMEOUT" \
	; do
		runtest
	done
	for C in 'svcs -H | egrep -v "online|disabled|legacy"' \
	; do
		INV=verbose runtest
	done
	done
	else
	for Z in ""; do
	for C in "$COSAS_BINDIR/agent-freespace-lfs.sh -v -k $FSAGENT_FREEKB -p $FSAGENT_FREEPCT -t $FSAGENT_TIMEOUT" \
	; do
		runtest
	done
	done
	fi
}

runtestsuite() {
	TS_START="`date`"
	echo "========= Running generic tests, started at `date`"
	runtestsuite_generic
	echo "========= Generic tests finished at `date`"

	if [ x"$RUNTESTSUITE_LOCAL_DEFINED" = xyes ]; then
		echo "========= Running locally defined tests"
		[ x"$RUNTESTSUITE_LOCAL_NAME" != x ] && \
			echo "$RUNTESTSUITE_LOCAL_NAME"
		runtestsuite_local
		echo "========= System-local tests finished at `date`"
	else
		echo "=== No local tests were defined in '$COSAS_CFGDIR/`basename "$0"`.conf'"
	fi
	TS_END="`date`"

	echo ""
	echo "========= OVERALL RESULTS =========="
	echo "$OUT_ALL"
	echo "=== `date`: Ran `echo "$OUT_ALL" | egrep -c '^\['` tests, of which `echo "$OUT_ALL" | egrep -c '\[\-FAIL\-\]'` failed"
	echo "=== START:	$TS_START"
	echo "=== FINISH:	$TS_END"

	[ "$RES_ALL" != 0 ] && echo "$OUT_ERR" > "$TMPF"
	return $RES_ALL
}

TMPF="/tmp/.diag-runtime.$$"
trap "echo '=== Abort requested: Killing child processes of $$...'; $COSAS_BINDIR/proctree.sh -P -kd 1 -kn KILL $$; rm -f $TMPF; echo '=== Exiting'; exit 0" 0 1 2 3 15

REGULAR_MODE=0
case "$1" in
    regular|regular-verbose)
	REGULAR_MODE=1
	OUTPUT="`runtestsuite 2>&1`"
	RES_ALL=$?
	if [ "$RES_ALL" != 0 -o x"$1" = xregular-verbose ]; then
		echo "$OUTPUT"

		if [ x"$BUGMAIL_RCPT" != x ]; then
			echo "Posting email to: $BUGMAIL_RCPT"
		        HOSTNAME=`hostname`
			[ "$RES_ALL" = 0 ] && \
				RES_STR="COMPLETED" || \
				RES_STR="FAILED for `echo "$OUTPUT" | egrep -c '\[\-FAIL\-\]'` tests"
		        TITLE="Check runtime services $RES_STR on $HOSTNAME at `date`"

			SUMMARY="========= SHORT SUMMARY =========
RESULT   	ZONE		TEST COMMANDS
`echo "$OUTPUT" | tail | grep 'tests, of which'`
`echo "$OUTPUT" | egrep '\[\-FAIL\-\]'`
`echo "$OUTPUT" | egrep '^=== (START|FINISH)'`
"

			[ "$RES_ALL" != 0 ] && \
				SUMMARY="$SUMMARY
======= ERRORS RECEIVED: =======`cat "$TMPF"`
=======
"
			rm -f "$TMPF"

			### This relies on running as root or another sendmail
			### TrustedUser who may impersonate senders.
		        ( echo "Subject: $TITLE"; echo "Date: `date`";
			  echo "To: $BUGMAIL_RCPT"; echo ""; echo "$TITLE"; 
			  echo "See end of detailed output for long summary";
			  echo "$SUMMARY"; echo "$OUTPUT" ) | \
			/usr/lib/sendmail -f "$BUGMAIL_FROM" "$BUGMAIL_RCPT" || \
			( echo "$TITLE"; 
			  echo "See end of detailed output for long summary";
			  echo "$SUMMARY"; echo "$OUTPUT" ) | \
			mailx -r "$BUGMAIL_FROM" -s "$TITLE" "$BUGMAIL_RCPT" && \
			echo "=== Successfully posted email report to: $BUGMAIL_RCPT"
		fi
	fi
	;;
    -h) echo "Runs automated test suite on runtime state of the OS" ;;
    *)
	runtestsuite
	RES_ALL=$?
	;;
esac

trap "" 0 1 2 3 15

exit $RES_ALL
