#!/bin/bash
#
# $Id: pkgdep.sh,v 1.2 2010/11/16 11:38:41 jim Exp $
# Script to display Solaris package's dependencies
#
# TODO: make recursive and sort deps uniquely in order of
# installation or deinstallation
#
###########################################################
# Originally (C) 2008-03-31 by Lorenzo Micheli:
# http://zorzorz.net/?p=10
###########################################################
# pkgdep.sh 0.1
#
# Utility script to fetch package dependencies on Solaris 
#
# Lorenzo Micheli <lorenzo.micheli@gmail.com>
#
###########################################################

BASEDIR=/var/sadm/pkg

pkgdetails() {
	for p in $*
	do
		details=`pkgparam -d ${BASEDIR} $p PKG $PARAM 2>/dev/null | tr '\n' ' '`
		echo "$details"
	done
}

pkgdep() {
	for p in $*
	do
		depfile="$BASEDIR/$p/install/depend"

		if [ -f "$depfile" ]
		then
			depname=`awk '/^P/ { print $2 }' $depfile | tr '\n' ' '`

			if [ "x$PARAM" != "x" ]
			then
				pkgdetails "$depname"
			else
				if [ "$#" -gt 1 ]
				then
					echo "$p: $depname"
				else
					echo "$depname"
				fi
			fi
		fi
	done
}

helpMessage="pkgdep.sh - display package dependencies

Usage
	$0 [-d repos ] [-nv] package...

Options:
	-d repos	Specify where find packages (by default /var/sadm/pkg)
	-n		Show package description
	-v		Show package version
	-h		Show this help message

"

usage() {
	printf "$helpMessage"
}

while getopts "nvhd:" flag
do
	case $flag in 
	d) 
		BASEDIR="$OPTARG"
		shift
		;;
	n)
		PARAM="$PARAM NAME"
		;;
	v) 
		PARAM="$PARAM VERSION"
		;;
	h)	
		usage
		exit 1
		;;
	*)
		usage
		exit 1
		;;
	esac
done

PKGPARAM_PATH_CHECK="`which pkgparam 2>/dev/null`"
if [ $? != 0 -o x"$PKGPARAM_PATH_CHECK" = x -o ! -d "$BASEDIR" ]; then
	echo "ERROR: Solaris package subsystem seems unavailable!" >&2
	usage
	exit 1
fi

pkgdep $*
