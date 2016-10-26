#!/bin/sh

# $Id: findcores.sh,v 1.6 2010/11/18 13:56:17 jim Exp $
# (C) May 2009 by Jim Klimov, COS&HT
# Simply finds all core files and outputs their names to stdout
# ready for removal. Outputs more formatted text to stderr.

FINDBASE="/"

if [ $# != 0 ]; then
	FINDBASE="$@"
fi

findnames_javaHProf() {
	for D in $FINDBASE; do
		find "$D" -type f -name 'java_pid*.hprof'
		find "$D" -type f -name 'hs_err_pid*.log'
		# ! -local -prune
	done 2>/dev/null
}

findnames() {
	for D in $FINDBASE; do
		find "$D" -type f -name core
		find "$D" -type f -name 'core.*'
		# ! -local -prune
	done 2>/dev/null
}

#findnames | egrep '/core$' | while read F; do

echo "=== Search for usual core files"
findnames | while read F; do
	echo "= $F" >&2
	if file "$F" | grep 'core file' >&2 ; then
		ls -la "$F" >&2
		echo "$F"
	else
		echo "     OK" >&2
	fi
	echo "" >&2
done

echo "=== Search for JVM hprof (profiler and GC dumps) and their log files"
findnames_javaHProf | while read F; do
	echo "= $F" >&2
	if file "$F" | egrep 'core file|data|ascii text' >&2 ; then
		ls -la "$F" >&2
		echo "$F"
	else
		echo "     OK" >&2
	fi
	echo "" >&2
done

