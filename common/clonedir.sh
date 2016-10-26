#!/bin/bash

### Uses hardlinks to clone a directory tree (i.e. a distro image)
### Requires: rsync (i.e. COSrsync package), find
### $Id: clonedir.sh,v 1.5 2015/08/05 10:55:09 jim Exp $
### (C) 2010-2015 by Jim Klimov, JSC COS&HT

SRC="$1"
DST="$2"
PWD="`pwd`"

case "$1" in
    -h|--help) 	echo "Usage:	$0 SRC DST"
		echo "Clone a directory tree or a single file using hardlinks if possible"
		exit 0
		;;
esac

if [ -f "$SRC" ]; then
	ln "$SRC" "$DST"
	exit
fi

if [ -d "$SRC" ]; then
	case "$SRC" in
	    /*) ;;
	    *) SRC="$PWD/$SRC";;
	esac

	case "$DST" in
	    /*) ;;
	    *) DST="$PWD/$DST";;
	esac

	if [ ! -d "$DST" ]; then
		mkdir -p "$DST" || exit 1
	fi

	if [ ! -d "$DST" -o ! -w "$DST" ]; then
		echo "Can't use dest dir '$DST'" >&2
		exit 1
	fi

	cd "$SRC" || exit 1

	echo "INFO: Will clone '$SRC' as '$DST' using hardlinks as much as possible"

	# Make dir structure
	echo "INFO: `date`: remaking dir structure..."
	find . -type d | while read D; do [ ! -d "$DST/$D" ] && mkdir "$DST/$D"; done

	# hardlink files
	echo "INFO: `date`: linking files..."
	find . -type f | while read F; do [ ! -f "$DST/$F" ] && ln "$F" "$DST/$F"; done

	# remake symlinks
	echo "INFO: `date`: symlinking files..."
	find . -type l | while read L; do 
	    if [ ! -L "$DST/$L" -a ! -h "$DST/$L" ] && [ ! -f "$DST/$L" ] ; then
		_LS="`ls -land "$L" | (read _P _L _U _G _T1 _T2 _T3 _TAIL; echo "$TAIL" | grep ' -> ')`" && \
		[ -n "${_LS}" ] && \
		_LNK="`echo -e "${_LS}" | sed 's, -> .*$,,'`" && \
		_TGT="`echo -e "${_LS}" | sed 's,^.* -> $,,'`" && \
		ln -s "${_TGT}" "$DST/${_LNK}"
	    fi
	done

	# Transfer non-files/non-dirs and attributes
	echo "INFO: `date`: rsyncing attributes..."
	rsync -avPH --link-dest=. . "$DST"
fi

