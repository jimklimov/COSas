#!/bin/sh

### Inspired by http://www.mail-archive.com/zfs-discuss@opensolaris.org/msg35329.html
### (C) 2010 by Jim Klimov, JSC COS&HT
### $Id: zfsacl-copy.sh,v 1.9 2010/12/20 12:45:42 jim Exp $

### This is supposed to copy ZFS ACLs from object $1 to object $2...$N
### Or from $2 to $3 if recursive flag is used: zfsacl-copy.sh -R src dest1 dest2 ...
### Requires Solaris 10 or OpenSolaris "chmod" and ZFS filesystem as src/target
### Note: copying ACLs between dirs and files (including recursive copies)
### is valid but probably useless due to exec bits, etc.

[ -x "/sbin/zfs" ] || exit 1

getACL() {
    ### Get an FS object's ACL printout and merge many lines with commas
    ls -Vd "$1" | tail +2 | sed -e 's/^ *//' | tr '\n' ,
}

setACL() {
	if [ -d "$1" -a x"$ACL_DIR" != x ]; then
	    [ "$VERBOSE" -gt 1 ] && echo "===== Fix DIR : '$1'"
	    chmod "$ACL_DIR" "$1"
	fi
	if [ -f "$1" -a x"$_ACL_ALLFILES" != x ]; then
	    case "`file "$1"`" in
		*:*executable*)
		    if [ x"$ACL_EXEC" != x ]; then
			[ "$VERBOSE" -gt 1 ] && echo "===== Fix EXEC: '$1'"
			chmod "$ACL_EXEC" "$1"
		    fi ;;
		*)  if [ x"$ACL_FILE" != x ]; then 
                        [ "$VERBOSE" -gt 1 ] && echo "===== Fix FILE: '$1'"
			chmod "$ACL_FILE" "$1"
		    fi ;;
	    esac
	fi
}

### Working variables
RECURSE=""
VERBOSE=0

### Clone ACLs from these objects: dirs, data files, executables
SRC_ALL=""
SRC_DIR=""
SRC_FILE=""
SRC_EXEC=""
EXCLUDE_REGEX='^$'

ACL_DIR=""
ACL_FILE=""
ACL_EXEC=""

COUNT=$#
while [ $COUNT -ge 1 ]; do
    case "$1" in
	-h|--help)
	    echo "$0: Copy ZFS ACLs from 'template' FS objects to a list of other objects"
	    echo "# $0 [-v] [-R] [-d template_dir] [-f template_file] [-x template_execfile] [--exclude|-X regexp] {file|dir}..."
	    echo "# $0 [-v] [-R] [--exclude|-X regexp] --default-distribs {file|dir}..."
	    echo "# $0 [-v] [-R] [--exclude|-X regexp] --default-homedir {file|dir}..."
	    echo "# $0 [-v] [-R] [--exclude|-X regexp] --default-posix-UG {file|dir}..."
	    echo "# $0 [-v] [-R] [--exclude|-X regexp] --default-posix-UGO {file|dir}..."
	    echo "# $0 [-v] [-R] template_all {file|dir}..."
	    echo "	template_XXX	Copy ZFS ACLs from these typical FS objects to specified"
	    echo "		directories, executable and data files, or from one to all"
	    echo "	--default-*	Use a preset ACL without 'template' files"
	    echo "	 home =	posix-UG	dir=711, file=640, execfile=750"
	    echo "		posix-UGO	dir=755, file=644, execfile=755"
	    echo "	exclude regexp	Skip any objects which match this REGEXP"
	    echo "	-R	Recurse into any provided subdirs (otherwise only act on them)"
	    echo "	-v	Verbosely report selected settings"
	    exit 0
	    ;;
	--default-distribs|--default-distrib|--default-distro)
### Sample ACLs from our practice for distribs: let sysadmin group and
### uploaders (owner users) do anything to the files. Others should
### have read/exec access.
	    ACL_DIR='A=group:sysadmin:rwxpdDaARWcCos:-d-----:allow,group:sysadmin:rw-pdDaARWcCos:f------:allow,owner@:rwxpdDaARWcCos:-d-----:allow,owner@:rw-pdDaARWcCos:f------:allow,everyone@:r-x---a-R-c--s:-d-----:allow,everyone@:r-----a-R-c--s:f------:allow,everyone@:-w-pdD-A-W-Co-:fd-----:deny,'
	    ACL_FILE='A=group:sysadmin:rw-pdDaARWcCos:f------:allow,owner@:rw-pdDaARWcCos:f------:allow,everyone@:r-----a-R-c--s:f------:allow,everyone@:-wxpdD-A-W-Co-:f------:deny,'
	    ACL_EXEC='A=group:sysadmin:rwxpdDaARWcCos:f------:allow,owner@:rwxpdDaARWcCos:f------:allow,everyone@:r-x---a-R-c--s:f------:allow,everyone@:-w-pdD-A-W-Co-:f------:deny,'
	    ;;
	--default-homedir|--default-home|--default-posix-UG)
### Sample ACLs from our practice for user homes. Just POSIX 711/640/750.
	    ACL_DIR='A=owner@:--------------:-------:deny,owner@:rwxp---A-W-Co-:-------:allow,group@:rw-p----------:-------:deny,group@:--x-----------:-------:allow,everyone@:rw-p---A-W-Co-:-------:deny,everyone@:--x---a-R-c--s:-------:allow,'
	    ACL_FILE='A=owner@:--x-----------:-------:deny,owner@:rw-p---A-W-Co-:-------:allow,group@:-wxp----------:-------:deny,group@:r-------------:-------:allow,everyone@:rwxp---A-W-Co-:-------:deny,everyone@:------a-R-c--s:-------:allow,'
	    ACL_EXEC='A=owner@:--------------:-------:deny,owner@:rwxp---A-W-Co-:-------:allow,group@:-w-p----------:-------:deny,group@:r-x-----------:-------:allow,everyone@:rwxp---A-W-Co-:-------:deny,everyone@:------a-R-c--s:-------:allow,'
	    ;;
	--default-posix-UGO)
### Just POSIX 755/644/755.
	    ACL_DIR='A=owner@:--------------:-------:deny,owner@:rwxp---A-W-Co-:-------:allow,group@:-w-p----------:-------:deny,group@:r-x-----------:-------:allow,everyone@:-w-p---A-W-Co-:-------:deny,everyone@:r-x---a-R-c--s:-------:allow,'
	    ACL_FILE='A=owner@:--x-----------:-------:deny,owner@:rw-p---A-W-Co-:-------:allow,group@:-wxp----------:-------:deny,group@:r-------------:-------:allow,everyone@:-wxp---A-W-Co-:-------:deny,everyone@:r-----a-R-c--s:-------:allow,'
	    ACL_EXEC='A=owner@:--------------:-------:deny,owner@:rwxp---A-W-Co-:-------:allow,group@:-w-p----------:-------:deny,group@:r-x-----------:-------:allow,everyone@:-w-p---A-W-Co-:-------:deny,everyone@:r-x---a-R-c--s:-------:allow,'
	    ;;
	-R) RECURSE="-R" ;;
	-d) SRC_DIR="$2"; shift
	    [ x"$SRC_DIR" != x -a -d "$SRC_DIR" ]  &&  ACL_DIR="A=`getACL "$SRC_DIR"`"
	    ;;
	-f) SRC_FILE="$2"; shift
	    [ x"$SRC_FILE" != x -a -f "$SRC_FILE" ] && ACL_FILE="A=`getACL "$SRC_FILE"`"
	    ;;
	-x) SRC_EXEC="$2"; shift
	    [ x"$SRC_EXEC" != x -a -f "$SRC_EXEC" ] && ACL_EXEC="A=`getACL "$SRC_EXEC"`"
	    ;;
	-v) VERBOSE=`echo $VERBOSE + 1 | bc` ;;
	-X|--exclude) EXCLUDE_REGEX="$2"; shift ;;
	*) ### Abort parsing, the rest are files/dirs to act upon
	     COUNT=-1 ;;
    esac
    [ $COUNT -gt 0 ] && shift
done

if [ x"$ACL_DIR" = x -a x"$ACL_FILE" = x -a x"$ACL_EXEC" = x ]; then
    SRC_ALL="$1"
    shift
    [ x"$SRC_ALL" != x ] && ACL_ALL="A=`getACL "$SRC_ALL"`"

    if [ "$VERBOSE" -gt 0 ]; then
	echo "=== Setting all ACLs to one template:"
	echo "=== chmod $RECURSE '$ACL_ALL' $@"
    fi

    [ $# -lt 1 ] && exit 1

    chmod $RECURSE "$ACL_ALL" "$@"
    exit
fi

### At least one FS object type template was provided

if [ "$VERBOSE" -gt 0 ]; then
    [ x"$RECURSE" = x ] && echo "=== Setting ACLs to templates:" || echo "=== Recursively setting ACLs to templates:"
    [ x"$ACL_DIR" = x ] &&  echo "=== DIR : SKIP" || echo "=== DIR : '$ACL_DIR'"
    [ x"$ACL_FILE" = x ] && echo "=== FILE: SKIP" || echo "=== FILE: '$ACL_FILE'"
    [ x"$ACL_EXEC" = x ] && echo "=== EXEC: SKIP" || echo "=== EXEC: '$ACL_EXEC'"
    echo "=== FS Objects:"
    ls -lad "$@"
fi

[ $# -lt 1 ] && exit 1

### Pseudo-ACL to check if any files are of interest
_ACL_ALLFILES="$ACL_FILE$ACL_EXEC"

if [ x"$RECURSE" = x ]; then
    ### Act on specified objects themselves. Use ls...
    ls -1 "$@" | \
      egrep -v "$EXCLUDE_REGEX" | while read FILE; do
	    setACL "$FILE"
      done
else
    ### If any dirs are provided, act on them and objects inside recursively
    ### Use find...
    for F in "$@"; do find "$F" | \
      egrep -v "$EXCLUDE_REGEX" | while read FILE; do
	    setACL "$FILE"
      done
    done
fi
