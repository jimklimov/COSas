#!/bin/bash

### $Id: sjsms-sunnumusers.sh,v 1.6 2010/11/17 12:01:32 jim Exp $
### This script helps keep track of organizations' sunnumusers attribute
### and update it automatically (via cron) or manually from command-line.
### Part of COSas (COS admin scripts) package
### (C) Jan 2009, Jim Klimov, COS&HT
### based on helpful info from a forum post by Shane Hjorth, SUN

### Usage to sync these values from cron every midnight:
###   0 0 * * *  [ -x /opt/COSas/bin/sjsms-sunnumusers.sh ] && /opt/COSas/bin/sjsms-sunnumusers.sh kick

### Based on http://forums.sun.com/thread.jspa?threadID=5360964 :
### Sun Java System Messaging Services include an organization's attribute
### "sunnumusers" to track the number of email users in the org (Delegated
### Admin web-GUI). If some accounts are created with other means (direct
### ldapmodify, etc.), this value becomes outdated.

########## Some config parameters follow
### You should set the following variables (details below)
### I try to source as many defaults as possible from common Sun LDAP
### client/server-config tools' command line environment variables:
###   LDAPROOTDN (a must for searches!)
### Optional if the defaults don't fit:
###   LDAPPARAMS or ( DIR_PROXY_HOST and/or DIR_PROXY_PORT )
###   LDAP_ADMIN_PWF
###   LDAP_ADMIN_USER
###   PATH and/or ( LDAPSEARCH_CMD and/or LDAPMODIFY_CMD )
###   LD_LIBRARY_PATH (and/or system/zone-wide crle config)
### Override these defaults in the script (but it will be overwritten by
### package updates) or in the config file (preferred way)

COSAS_BINDIR=`dirname "$0"`
if [ x"$COSAS_BINDIR" = x./ -o x"$COSAS_BINDIR" = x. ]; then
        COSAS_BINDIR=`pwd`
fi

### Source the optional config files if any
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

### Root DN which contains the organizations in LDAP, used for search queries
###   MUST set to a real-life value
LDAPROOTDN="${LDAPROOTDN:-dc=company,dc=com}"

### LDAP Server and port, perhaps other params
LDAPPARAMS="${LDAPPARAMS:--h ${DIR_PROXY_HOST:-localhost} -p ${DIR_PROXY_PORT:-389} }"

### File with LDAP password (plaintext one-liner, secure by chmod 600)
if [ -n "$LDAP_ADMIN_PWF" -a -f "$LDAP_ADMIN_PWF" -a -r "$LDAP_ADMIN_PWF" ]; then
    :
else
    if [ -n "$LDAP_ADMIN_PWF" ]; then
	if [ ! -f "$LDAP_ADMIN_PWF" -o ! -r "$LDAP_ADMIN_PWF" ]; then
	    echo "DEBUG: Password file specified as '$LDAP_ADMIN_PWF' but not found; trying alternatives" >&2
	    unset LDAP_ADMIN_PWF
	fi
    fi

    ### Try default COSps71 passfiles
    for F in /.ds6pass /.ds7pass /.ps7pass; do
	if [ -f "$F" -a -r "$F" -a -z "$LDAP_ADMIN_PWF" ]; then
	    LDAP_ADMIN_PWF="$F"
	fi
    done
fi
if [ -z "$LDAP_ADMIN_PWF" ]; then
    echo "DEBUG: No password file (not specified and/or not found); you may be asked" >&2
    echo "    for a pass interactively - but you're in trouble tunning from crontab" >&2
fi

### Separate parameter to go around spaces in bindDN names
LDAP_ADMIN_USER=${LDAP_ADMIN_USER:-"cn=Directory Manager"}
if [ -z "$LDAP_ADMIN_USER" ]; then
    echo "DEBUG: No bind DN string (not specified and/or not found)" >&2
fi

### Command names; perhaps you should also set a PATH if not using
### system default LDAP client, and possibly configure "crle" or set
### and export a valid LD_LIBRARY_PATH...
LDAPSEARCH_CMD=${LDAPSEARCH_CMD:-ldapsearch}
LDAPMODIFY_CMD=${LDAPMODIFY_CMD:-ldapmodify}

################
### These are used below
LDAPSEARCH="$LDAPSEARCH_CMD $LDAPPARAMS -b $LDAPROOTDN "
LDAPMODIFY="$LDAPMODIFY_CMD $LDAPPARAMS ${LDAP_ADMIN_PWF:+-j $LDAP_ADMIN_PWF} "

get() {
	$LDAPSEARCH 'sunnumusers=*' sunnumusers

}

gettrim() {
	echo "=== Number recorded in LDAP:">&2
	( get; echo "" ) | while read LINE; do
	    case "$LINE" in
		dn*) DN=`echo "$LINE" | awk '{ print $2 }' | sed 's/ *, */,/g'` ;;
		sunnumusers*) SN=`echo "$LINE" | awk '{ print $2 }'` ;;
		"") echo "$SN	$DN";;
	    esac
	done | sort -k 2
}

count() {
	echo "=== Actual user count in LDAP:">&2
	### expected names like 
	###   dn: uid=admin, ou=People, o=corp.com,dc=corp,dc=com
	### individual organization DNs should be the tail of the string
	### starting with "o=*"; spaces around commas are stripped

	### This ldapsearch finds all users, the following filters count
	### them and name all unique organizations
	$LDAPSEARCH '(&(uid=*)(&(objectClass=inetuser)(|(inetUserStatus=active)(inetUserStatus=inactive))))' dn 2>&1 | \
	    sed 's/^.*, *\(o=.*\)$/\1/g' | \
	    sed 's/ *, */,/g' | \
	    sort | uniq -c | grep o= | while read SN DN; do
		echo "$SN	$DN"
	    done | sort -k 2
}

setprepare() {
	### This doesn't take into account CREATION of sunnumusers
	### We expect organizations to be created by Delegated Admin

	count 2>/dev/null | while read N ORG; do
		echo "dn: $ORG"
		echo "changetype: modify"
		echo "replace: SunNumUsers"
		echo "SunNumUsers: $N"
		echo ""
	done
}

set() {
	echo "==== '$LDAPMODIFY "${LDAP_ADMIN_USER:+-D "$LDAP_ADMIN_USER"}"'" >&2
	case "$1" in
		-w) setprepare | $LDAPMODIFY ${LDAP_ADMIN_USER:+-D "$LDAP_ADMIN_USER"} ;;
		-n) echo "=== read-only mode, skips LDAP-bind attempts" >&2
		   setprepare | $LDAPMODIFY ${LDAP_ADMIN_USER:+-D "$LDAP_ADMIN_USER"} -n;;
		*) setprepare;;
	esac
}

check() {
	BUGS=`( gettrim; count ) 2>/dev/null | sort | uniq -c | egrep -v '^ *2' | awk '{ print $2"\t"$3}'`
	if [ -n "$BUGS" ]; then
	    echo "!!! Mismatches:">&2
	    echo "$BUGS"
	    return 1
	fi
    return 0
}

case "$1" in
	get)	get;;
	gettrim)gettrim;;
	count)	count;;
	set)	set "$2";;
	check)	check ;;
	status)	gettrim
		count
		check
		;;
	kick)	check || set -w;;
	*) echo "
$0 help:
Action:		check and fix orgs' SunNumUsers attribute (manually or crontab)
Version:	"'$Id: sjsms-sunnumusers.sh,v 1.6 2010/11/17 12:01:32 jim Exp $'"
Usage:
    get		Get the value recorded in organizations' attributes (as LDIF)
    gettrim	Get the value recorded in orgs' attributes (single-line output)
    count	Count user accounts in all organizations (single-line output)
    set	[-n|-w]	Do 'count' and generate the LDIF for ldapmodify to update orgs
      set -n	  test run, read-only
      set -w	  actually write to LDAP
    check	Report if 'gettrim' and 'count' outputs differ, exit 1 if so
    status	Do 'gettrim', 'count' and 'check'
    kick	Do 'check || set -w' to remove any differences (if any) - use
		  this mode in crontab after setting up and checking manually
" ;;
esac

