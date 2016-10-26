#!/bin/bash

### $Id: test-archive.sh,v 1.35 2016/06/22 09:58:12 jim Exp $
### (C) 2010-2016 by Jim Klimov, JSC COS&HT
### This script tests provided archived files for their correctness
### Can recurse into subdirectories if their names are provided
### Can "fix" broken archive visibility by renaming such files
### NOTE: experimental, since many reasons can lead to check failure
### Can also test archves according to MD5SUM and SHA1, SHA256 files and lists
### Verbosity levels described in command-line help
### If several archives error out in different ways, only the last non-zero
### error code is returned as the overall result.

match_prog() {
	### Returns the first of provided parameters which is an executable
	### program's file name
	PROG=""
	while [ $# -gt 0 ]; do
	if [ x"$1" != x ]; then
		if [ -x "$1" ]; then
			echo "$1"
			return 0
		fi
		W="`which "$1" 2>/dev/null`"
		if [ $? = 0 -a x"$W" != x ]; then
		echo "$W" | ( while read F; do
			if [ x"$F" != x -a -x "$F" ]; then
				echo "$F"
				exit 0
			fi
		done
		exit 1 )
		[ $? = 0 ] && return 0
		fi
	fi
	shift
	done

	return 1
}

rename_bad_file() {
	if [ x"$LS_BADFILES" != x0 ]; then
		echo "  `ls -ladi "$1"`" >&2
	fi

	if [ x"$ACTIVE_RENAME" != x0 ]; then
	case "$1" in
		*.__BROKEN__) ;;
		*)	### This may overwrite a previously existing __BROKEN__ file
			### Not a problem - it is deemed broken anyway...
			echo "	Renaming '$1' to '$1.__BROKEN__'..." >&2
			mv -f "$1" "$1.__BROKEN__"
		;;
	esac
	fi
}

##############################################################
### Routines for testing specific archive types

test_p7zip_work() {
	### In essence this is the failback tester for all methods -
	### if it is called, then no better tester was found in PATH.
	### If it fails due to no "7z" in path, than no suitable tester exists.
	### NOTE: This call specifies an empty password; tests would fail
	### for encrypted archives without asking for input.
	### TODO: Allow passing (lists/files of) passwords and try to use them.
	_isFallback="$2"

	if [ x"$_P7ZIP" != x -a -x "$_P7ZIP" ]; then
		### Sometimes archivers like UNZIP are too picky about format,
		### while p7 can read the file
		[ x"$_isFallback" = "x-1" -o x"$_isFallback" = "x255" ] && \
			[ "$VERBOSE" -ge 2 ] && \
			echo "FALLBACK: P7ZIP: Main archiver not available"
		[ x"$_isFallback" != "x0" -a x"$_isFallback" != x \
		  -a "$VERBOSE" -ge 2 ] && \
			echo "RETRY_TEST: P7ZIP: Main archiver failed the test, confirm or overrule it"

		__OUT="`eval "LANG=C $_P7ZIP t -p'' '$1' $HIDE_ERR2"`"
		__RES=$?

		__ERR=$(echo "$__OUT" | grep 'Error: ')
		if [ "$__RES" != 0 ]; then
			echo "$__ERR" | grep "Error: Can not open file as archive" >/dev/null
			[ $? = 0 -a x"$NOT_ARCHIVE" = xOK ] && __RES=0
		fi

		if [ "$VERBOSE" -le 2 ]; then
			[ x"$__ERR" != x ] && echo "$__ERR"
		else
			[ x"$__OUT" != x ] && echo "$__OUT"
		fi

		[ "$__RES" = 0 -a "$VERBOSE" -ge 1 \
		  -a x"$_isFallback" != "x0" -a x"$_isFallback" != x ] && \
			echo "RETRY_TEST: Main archiver failed, but P7ZIP can read the file OK"

		return $__RES
	fi
	echo "ERROR: Archiver not found, skipping" >&2
	return 255
}

test_tar() {
	NOTQUIET="v"
	[ "$VERBOSE" -le 2 ] && NOTQUIET=""
	echo "TEST: TAR: '$1'"
	RES=255
	if [ x"$_GTAR" != x -a -x "$_GTAR" ]; then
		eval "$_GTAR -t${NOTQUIET}f '$1' $HIDE_ERR"
		RES=$?
	fi
	[ $RES = 0 ] && return $RES
	test_p7zip_work "$1" $RES
}

test_tgz() {
	NOTQUIET="v"
	[ "$VERBOSE" -le 2 ] && NOTQUIET=""
	echo "TEST: TAR.GZIP: '$1'"
	RES=255
	if [ x"$_GTAR" != x -a -x "$_GTAR" ]; then
		eval "$_GTAR -t${NOTQUIET}zf '$1' $HIDE_ERR"
		RES=$?
	fi
	[ $RES = 0 ] && return $RES
	test_p7zip_work "$1" $RES
}

test_tbz() {
	NOTQUIET="v"
	[ "$VERBOSE" -le 2 ] && NOTQUIET=""
	echo "TEST: TAR.BZIP2: '$1'"
	RES=255
	if [ x"$_GTAR" != x -a -x "$_GTAR" ]; then
		eval "$_GTAR -t${NOTQUIET}jf '$1' $HIDE_ERR"
		RES=$?
	fi
	[ $RES = 0 ] && return $RES
	test_p7zip_work "$1" $RES
}

test_tZ() {
	NOTQUIET="v"
	[ "$VERBOSE" -le 2 ] && NOTQUIET=""
	echo "TEST: TAR.Z (compress): '$1'"
	RES=255
	if [ x"$_GTAR" != x -a -x "$_GTAR" ]; then
		eval "$_GTAR -t${NOTQUIET}Zf '$1' $HIDE_ERR"
		RES=$?
		[ $RES = 0 ] && return $RES
		eval "$_GTAR -t${NOTQUIET}zf '$1' $HIDE_ERR"
		RES=$?
	fi
	[ $RES = 0 ] && return $RES
	test_p7zip_work "$1" $RES
}

test_gzip() {
	echo "TEST: GZIP: '$1'"
	RES=255
	if [ x"$_GZIP" != x -a -x "$_GZIP" ]; then
	case "$1" in
		*.[Gg][Zz]|*.[Zz]|*.[Tt][Gg][Zz])
			eval "$_GZIP -t '$1' $HIDE_ERR"
			RES=$?
			;;
		*)
			eval "($_GZIP -cd < '$1' > /dev/null) $HIDE_ERR"
			RES=$?
			;;
	esac
	fi
	[ $RES = 0 ] && return $RES
	test_p7zip_work "$1" $RES
}

test_bzip2() {
	echo "TEST: BZIP2: '$1'"
	RES=255
	if [ x"$_BZIP" != x -a -x "$_BZIP" ]; then
		eval "$_BZIP -t '$1' $HIDE_ERR"
		RES=$?
	fi
	[ $RES = 0 ] && return $RES
	test_p7zip_work "$1" $RES
}

test_compress() {
	echo "TEST: Z (compress): '$1'"
	RES=255
	if [ x"$_UNCOMPRESS" != x -a -x "$_UNCOMPRESS" ]; then
		eval "($_UNCOMPRESS -c < '$1' >/dev/null) $HIDE_ERR"
		RES=$?
	fi
	[ $RES = 0 ] && return $RES
	if [ x"$_GZIP" != x -a -x "$_GZIP" ]; then
		eval "$_GZIP -t '$1' $HIDE_ERR"
		RES=$?
	fi
	[ $RES = 0 ] && return $RES
	test_p7zip_work "$1" $RES
}

test_unzip () {
	QUIET=""
	[ "$VERBOSE" -le 2 ] && QUIET="q"
	echo "TEST: ZIP: '$1'"
	RES=255
	if [ x"$_UNZIP" != x -a -x "$_UNZIP" ]; then
		eval "$_UNZIP -${QUIET}t '$1' $HIDE_ERR"
		RES=$?
	fi
	[ $RES = 0 ] && return $RES
	test_p7zip_work "$1" $RES
}

test_cpio () {
	echo "TEST: CPIO: '$1'"
	RES=255
	if [ x"$_CPIO" != x -a -x "$_CPIO" ]; then
		eval "$_CPIO -idt < '$1' $HIDE_ERR"
		RES=$?
	fi
	[ $RES = 0 ] && return $RES
	test_p7zip_work "$1" $RES
}

test_cpio_gz () {
	echo "TEST: CPIO.GZ: '$1'"
	RES=255
	if [ x"$_GZIP" != x -a -x "$_GZIP" ]; then
		if [ x"$_CPIO" != x -a -x "$_CPIO" -a x"$_GZIP" != x -a -x "$_GZIP" ]; then
			eval "( $_GZIP -cd '$1' | $_CPIO -idt ) $HIDE_ERR"
			RES=$?
		else
			test_gzip "$1"
			RES=$?
		fi
	fi
	[ $RES = 0 ] && return $RES
	test_p7zip_work "$1" $RES
}

test_cpio_Z () {
	echo "TEST: CPIO.Z: '$1'"
	RES=255
	if [ x"$_GZIP" != x -a -x "$_GZIP" ]; then
		if [ x"$_CPIO" != x -a -x "$_CPIO" -a x"$_GZIP" != x -a -x "$_GZIP" ]; then
			eval "( $_GZIP -cd '$1' | $_CPIO -idt ) $HIDE_ERR"
			RES=$?
		else
			test_gzip "$1"
			RES=$?
		fi
	fi
	[ $RES = 0 ] && return $RES
	test_p7zip_work "$1" $RES
}

test_cpio_bz2 () {
	echo "TEST: CPIO.BZ2: '$1'"
	RES=255
	if [ x"$_BZIP2" != x -a -x "$_BZIP2" ]; then
		if [ x"$_CPIO" != x -a -x "$_CPIO" -a x"$_GZIP" != x -a -x "$_GZIP" ]; then
			eval "( $_BZIP2 -cd '$1' | $_CPIO -idt ) $HIDE_ERR"
			RES=$?
		else
			test_gzip "$1"
			RES=$?
		fi
	fi
	[ $RES = 0 ] && return $RES
	test_p7zip_work "$1" $RES
}

test_p7zip () {
	echo "TEST: P7ZIP: '$1'"
	test_p7zip_work "$1"
}

test_msi () {
	echo "TEST: MSI: '$1'"
	test_p7zip_work "$1"
}

test_cab () {
	echo "TEST: CAB: '$1'"
	test_p7zip_work "$1"
}

test_iso () {
	echo "TEST: ISO: '$1'"
	test_p7zip_work "$1"
}

test_rar () {
	echo "TEST: RAR: '$1'"
	test_p7zip_work "$1"
}

test_rpm () {
	echo "TEST: RPM: '$1'"
	test_p7zip_work "$1"
}

test_deb () {
	echo "TEST: DEB: '$1'"
	test_p7zip_work "$1"
}

test_sfx_bin () {
	echo "TEST: Self-extractor (maybe): Shell-script: '$1'"
	if [ ! -x "$1" ]; then
		echo "WARN: File is not currently executable. To fix run:" >&1
		echo "  # chmod +x '$1'" >&1
	fi
	NOT_ARCHIVE=OK test_p7zip_work "$1"
}

test_sfx_exe () {
	echo "TEST: Self-extractor (maybe): DOS/Windows EXE: '$1'"
	NOT_ARCHIVE=OK test_p7zip_work "$1"
	RES=$?

	if [ "$RES" != 0 ]; then
	case "`basename "$1"`" in
		VirtualBox*)
			[ "$VERBOSE" -ge 2 ] && echo "INFO: Some EXEs are known to be incompatible with test methods. Not failing on '$1' (test returned error $RES)."
			RES=0 ;;
		esac
	fi

	return $RES
}

#####################   Checksum file tests
### OpenSSL methods are quite universal but slower;
### native or PERL may be preferred
algo_md5sum_openssl() {
	eval "$_OPENSSL dgst -md5 '$1'"
}

algo_sha256sum_openssl() {
	eval "$_OPENSSL dgst -sha256 '$1'"
}

algo_sha512sum_openssl() {
	eval "$_OPENSSL dgst -sha512 '$1'"
}

algo_sha1sum_openssl() {
	eval "$_OPENSSL dgst -sha1 '$1'"
}

algo_md5sum_native() {
	__OUT="`eval "$_MD5SUM '$1'"`"
	__RES=$?

	[ "$__RES" = 0 ] && __OUT="`echo "$__OUT" | awk '{print $1}'`"

	echo "$__OUT"
	return $__RES
}

algo_sha256sum_native() {
	__OUT="`eval "$_SHA256SUM '$1'"`"
	__RES=$?

	[ "$__RES" = 0 ] && __OUT="`echo "$__OUT" | awk '{print $1}'`"

	echo "$__OUT"
	return $__RES
}

algo_sha512sum_native() {
	__OUT="`eval "$_SHA512SUM '$1'"`"
	__RES=$?

	[ "$__RES" = 0 ] && __OUT="`echo "$__OUT" | awk '{print $1}'`"

	echo "$__OUT"
	return $__RES
}

algo_sha1sum_native() {
	__OUT="`eval "$_SHA1SUM '$1'"`"
	__RES=$?

	[ "$__RES" = 0 ] && __OUT="`echo "$__OUT" | awk '{print $1}'`"

	echo "$__OUT"
	return $__RES
}

check_checksum () {
	### Assumes that needed checksum program exists (checked outside)
	### "$1" = tested file
	### "$2" = expected checksum
	### "$3" = algorithm (algo_* procedure name)
	### Returns:
	###	0	All ok
	###	126	File is not found or readable, and this is requested fatal
	###	127 	Checksum mismatch
	###	others	'md5sum'/'sha256sum'/'openssl' native errorcodes

	DO_PRINT_ERROR=0
	[ "$VERBOSE" -ge 3 ] && DO_PRINT_ERROR=1
	[ "$CKSUM_NOFILE_REACTION" = ERROR ] && DO_PRINT_ERROR=1
	[ "$CKSUM_NOFILE_REACTION" = QUIETERROR ] && \
		DO_PRINT_ERROR=0 && CKSUM_NOFILE_REACTION=ERROR

	__ALGO="$3"
	### Chomp Win/DOS newlines '^M', no effect on Unix/Win/DOS single '\n's
	__OTF="`echo "$1" | tr -d '\r'`"

	### Select only the first token in line, and
	### chomp \r\n which may be present in DOS/Win files
	__OCS="`echo "$2" | sed 's/^[^a-fA-F0-9]*\([a-fA-F0-9]*\)[^a-fA-F0-9]*.*$/\1/' | tr '[A-Z]' '[a-z]'`"

	if [ ! -f "$__OTF" ]; then
		[ "$DO_PRINT_ERROR" = 1 ] && echo "$CKSUM_NOFILE_REACTION: CHECKSUM: File '$__OTF' does not exist" >&2
		[ "$CKSUM_NOFILE_REACTION" = ERROR ] && return 126
		return 0
	fi

	if [ ! -r "$__OTF" ]; then
		[ "$DO_PRINT_ERROR" = 1 ] && echo "$CKSUM_NOFILE_REACTION: CHECKSUM: File '$__OTF' is not readable" >&2
		[ "$CKSUM_NOFILE_REACTION" = ERROR ] && return 126
		return 0
	fi

	### The errors above are fatal for md5sum; we opt to ignore them
	### TODO: make an OPTION to opt to ignore or report errorcodes?

	__CS="`eval "$__ALGO '$__OTF'" | tr '[A-Z]' '[a-z]'`"
	__RES=$?

	if [ "$__RES" = 0 ]; then
		if [ x"$__CS" != x"$__OCS" ]; then
			if [ "$VERBOSE" -ge 2 ]; then
				echo "ERROR: CHECKSUM: File '$__OTF' checksum mismatch. Calculated/Original:" >&2
				echo "  '$__CS'" >&2
				echo "  '$__OCS'" >&2
			else
				echo "ERROR: CHECKSUM: File '$__OTF' checksum mismatch." >&2
			fi
			rename_bad_file "$__OTF"
			__RES=127
		else
			if [ "$VERBOSE" -ge 2 ]; then
				echo "INFO: CHECKSUM: File '$__OTF':	OK"
			fi
		fi
	fi

	return "$__RES"
}

test_checksumfile() {
# A gem of functional programming =)
# CALLER:  test_checksumfile "$1" "MD5" "$_ALGO_MD5SUM" ".md5 .MD5 .md5.txt .MD5.TXT"
	__CSFILE="$1"	### "md5sums.txt", "file.zip.md5" etc
	__CSTYPE="$2"	### "MD5" - for info texts
	__CSALGO="$3"	### value of "$_ALGO_MD5SUM"
	__EXTLIST="$4"	### ".md5 .MD5 .md5.txt .MD5.TXT" to chop off tails

#	__EXTREGEX="*`echo "$__EXTLIST" | sed 's/^ *//' | sed 's/ *$//' | sed 's/  */\\\|\*/g'`"
	__DIR="`dirname "${__CSFILE}"`"

	echo "TEST: ${__CSTYPE} Checksums: '${__CSFILE}'"
	[ "$VERBOSE" -ge 3 ] && \
		echo "INFO: __CSALGO='$__CSALGO' __EXTLIST='$__EXTLIST'"

	__FAIL_CS=0
	__FAIL_EX=0
	### NOTE: For checksum files in different formats, make an interpreter
	### STD1:  1547a418ff2fe25d0c1d34f9bc0b250b  illumos-gate-oi151a_release-sparc.tar.bz2
	### STD2:  1547a418ff2fe25d0c1d34f9bc0b250b  *illumos-gate-oi151a_release-sparc.tar.bz2
	### STD3:  1547a418ff2fe25d0c1d34f9bc0b250b  @illumos-gate-oi151a_release-sparc.tar.bz2
	### STD4:  1547a418ff2fe25d0c1d34f9bc0b250b  +illumos-gate-oi151a_release-sparc.tar.bz2
	### EXC1:  (illumos-gate-oi151a_release-sparc.tar.bz2) = 1547a418ff2fe25d0c1d34f9bc0b250b
	if [ x"$__CSALGO" != x ]; then
		__RESULT=0
		CKSUM_NOFILE_REACTION="$CKSUM_NOFILE_REACTION_DEFAULT"
		while read __SUM __FILE __TAIL; do
			if [ x"$__SUM" != x ]; then
				if [ x"$__TAIL" != x -a x"$__FILE" = "x=" ]; then
					### EXC1 case above, chomp parentheses if available
					__FILE="`echo "$__SUM" | sed 's,^(\\(.*\))$,\1,'`"
					__SUM="$__TAIL"
					__TAIL=""
				fi

				[ x"$__FILE" = x ] && \
				CKSUM_NOFILE_REACTION="ERROR" && \
				for __EXT in $__EXTLIST; do
					### In this loop we check if the checksum file has one of the
					### known tailing extensions (added to original file's name).
					case "${__CSFILE}" in
						`eval echo "\*$__EXT"`)
							[ "$VERBOSE" -ge 3 ] && echo "INFO: Matched '${__CSFILE}' '$__EXT'"
							__FILE="`basename "${__CSFILE}" "$__EXT"`" ;;
					esac
				done

				if [ x"$__FILE" = x ]; then
					### This should not happen, but...
					### Perhaps a signed *.md5sum.asc file?
					echo "ERROR: Can not detect original filename for '${__CSFILE}'" >&2
					__FILE="`basename "${__CSFILE}"`"
				fi

				case "$__FILE" in
				'*'*|'@'*|'+'*)
					### STD2,3,4 cases above
					check_checksum "$__DIR/${__FILE:1}" "$__SUM" "$__CSALGO"
					_RES=$?
					if [ $_RES != 0 ]; then
						### A missing file with weird name should not clear
						### the error state if the first check did error out.
						CKSUM_NOFILE_REACTION=QUIETERROR \
							check_checksum "$__DIR/$__FILE" "$__SUM" "$__CSALGO"
						_RES2=$?
						[ $_RES2 != 126 ] && _RES=$_RES2
					fi ;;
				*)
					### Normal filename (STD1 or EXC* cases after conversion)
					check_checksum "$__DIR/$__FILE" "$__SUM" "$__CSALGO"
					_RES=$? ;;
				esac

				[ "$_RES" != 0 ] && __RESULT="$_RES"
				[ "$_RES" = 127 ] && __FAIL_CS=$(($__FAIL_CS+1))
				[ "$_RES" = 126 ] && __FAIL_EX=$(($__FAIL_EX+1))
			fi
		done < "${__CSFILE}"

		if [ "$__FAIL_CS" != 0 ]; then
			echo "ERROR: ${__CSTYPE}SUM-check: $__FAIL_CS mismatch(es) found" >&2
		fi
		if [ "$__FAIL_EX" != 0 ]; then
			echo "ERROR: ${__CSTYPE}SUM-check: $__FAIL_EX required file(s) missing" >&2
		fi
		return $__RESULT
	fi
	echo "ERROR: Checksum-algorithm program for '${__CSTYPE}' is not configured!" >&2
	return 255
}

test_md5sum () {
	test_checksumfile "$1" "MD5" "$_ALGO_MD5SUM" ".md5 .MD5 .md5.txt .MD5.TXT"
}

test_sha256sum () {
	test_checksumfile "$1" "SHA256" "$_ALGO_SHA256SUM" ".sha256 .SHA256 .sha256.txt .SHA256.TXT .sha .SHA .sha.txt .SHA.TXT"
}

test_sha512sum () {
	test_checksumfile "$1" "SHA512" "$_ALGO_SHA512SUM" ".sha512 .SHA512 .sha512.txt .SHA512.TXT .sha .SHA .sha.txt .SHA.TXT"
}

test_sha1sum () {
	test_checksumfile "$1" "SHA1" "$_ALGO_SHA1SUM" ".sha1 .SHA1 .sha1.txt .SHA1.TXT .sha .SHA .sha.txt .SHA.TXT"
}

##############################################################
### Detect archive type (if any) and test it
test_archive() {
	RET="255"
	OUT=""
	NO_RENAME="0"
	if [ x"$1" != x -a -r "$1" -a -f "$1" ]; then
		FILETYPE="`$_FILE "$1"`"
		### NOTE: all test methods include 7z as fallback tester if it
		### is available; it is not mentioned explicitly in most cases
		case "`basename "$1"`===$FILETYPE" in
			### NOTE: Many archives include signed MD5 files
			### with embedded digests. These lines are currently
			### processed incorrectly.
			*.[Mm][Dd]5*===*text*|[Mm][Dd]5[Ss][Uu][Mm]*===*text*)
				OUT="`test_md5sum "$1" 2>&1`"
				RET=$?
				NO_RENAME="1"
				[ "$VERBOSE" -le 1 ] && OUT="`echo "$OUT" | grep -v "WARN"`" 
				;;

			*.[Ss][Hh][Aa]256*===*text*|[Ss][Hh][Aa]256[Ss][Uu][Mm]*===*text*)
				OUT="`test_sha256sum "$1" 2>&1`"
				RET=$?
				NO_RENAME="1"
				[ "$VERBOSE" -le 1 ] && OUT="`echo "$OUT" | grep -v "WARN"`" 
				;;

			*.[Ss][Hh][Aa]512*===*text*|[Ss][Hh][Aa]512[Ss][Uu][Mm]*===*text*)
				OUT="`test_sha512sum "$1" 2>&1`"
				RET=$?
				NO_RENAME="1"
				[ "$VERBOSE" -le 1 ] && OUT="`echo "$OUT" | grep -v "WARN"`" 
				;;

			*.[Ss][Hh][Aa]1*===*text*|[Ss][Hh][Aa]1[Ss][Uu][Mm]*===*text*)
				OUT="`test_sha1sum "$1" 2>&1`"
				RET=$?
				NO_RENAME="1"
				[ "$VERBOSE" -le 1 ] && OUT="`echo "$OUT" | grep -v "WARN"`" 
				;;

			*.[Ss][Hh][Aa]*===*text*|[Ss][Hh][Aa][Ss][Uu][Mm]*===*text*)
				### Try all known SHAxSUM algos
				OUT="`test_sha1sum "$1" 2>&1`" || \
				OUT="$OUT`echo ""; test_sha256sum "$1" 2>&1`" || \
				OUT="$OUT`echo ""; test_sha512sum "$1" 2>&1`"
				RET=$?
				NO_RENAME="1"
				[ "$VERBOSE" -le 1 ] && OUT="`echo "$OUT" | grep -v "WARN"`" 
				;;

			*.[Aa][Ss][Cc]===*|*.[Ss][Ii][Gg]===*|*.[RrDd][Ss][Aa]===*)
				if [ "$VERBOSE" -ge 2 ]; then
					echo "SKIP: Known but unsupported checksum file type: '$1'" >&2
					echo "" >&2
				fi
				NO_RENAME="1"
				;;

			*.[Dd][Mm][Gg]===*)
				### MacOS *.DMG archives seem like bz2, but
				### both bzcat and 7z bail out on them
				if [ "$VERBOSE" -ge 2 ]; then
					echo "SKIP: Known but unsupported archive file type: '$1'" >&2
					echo "" >&2
				fi
				NO_RENAME="1"
				;;

			*.[Gg][Zz]===*|*.[Tt][Gg][Zz]===*|*gzip\ compressed\ data*|*.[Vv][Bb][Oo][Xx]-[Ee][Xx][Tt][Pp][Aa][Cc][Kk]===*)
					case "$1" in
					*.[Cc][Pp][Ii][Oo]*)
						OUT="`test_cpio_gz "$1" 2>&1`"
						RET=$?
						;;
					*.[Tt][Aa][Rr]*|*.[Tt][Gf][Zz]*|*.[Vv][Bb][Oo][Xx]-[Ee][Xx][Tt][Pp][Aa][Cc][Kk]*)
						if [ x"$_GTAR" = x ]; then
							OUT="`test_gzip "$1" 2>&1`"
							RET=$?
						else
							OUT="`test_tgz "$1" 2>&1`"
							RET=$?
						fi
						;;
					*)	OUT="`test_gzip "$1" 2>&1`"
						RET=$?
						;;
					esac
					;;
			*.[Bb][Zz]*===*|*.[Tt][Bb][Zz]*===*|*bzip2\ compressed\ data*)
					case "$1" in
					*.[Cc][Pp][Ii][Oo]*)
						OUT="`test_cpio_bz2 "$1" 2>&1`"
						RET=$?
						;;
					*.[Tt][Aa][Rr]*|*.[Tt][Bb][Zz]*)
						if [ x"$_GTAR" = x ]; then
							OUT="`test_bzip2 "$1" 2>&1`"
							RET=$?
						else
							OUT="`test_tbz "$1" 2>&1`"
							RET=$?
						fi
						;;
					*)	OUT="`test_bzip2 "$1" 2>&1`"
						RET=$?
						;;
					esac
					;;
			*.[Zz]===*|*.[Tt][Zz]===*|*compressed\ data\ block\ compressed\ *\ bits*)
					case "$1" in
					*.[Cc][Pp][Ii][Oo]*)
						OUT="`test_cpio_Z "$1" 2>&1`"
						RET=$?
						;;
					*.[Tt][Aa][Rr]*|*.[Tt][Gf][Zz]*)
						if [ x"$_GTAR" = x ]; then
							OUT="`test_compress "$1" 2>&1`"
							RET=$?
						else
							OUT="`test_tZ "$1" 2>&1`"
							RET=$?
						fi
						;;
					*)	OUT="`test_compress "$1" 2>&1`"
						RET=$?
						;;
					esac
					;;
			*.[Tt][Aa][Rr]===*|*tar\ archive*)
				OUT="`test_tar "$1" 2>&1`"
				RET=$?
				;;
			*.[Cc][Pp][Ii][Oo]===*|*[Cc][Pp][Ii][Oo]\ archive*)
				OUT="`test_cpio "$1" 2>&1`"
				RET=$?
				;;
			*.[Zz][Ii][Pp]===*|*.[JjEeWw][Aa][Rr]===*|*[Zz][Ii][Pp]\ archive*)
				OUT="`test_unzip "$1" 2>&1`"
				RET=$?
				;;
			*.[Mm][Ss][Ii]===*|*Microsoft\ Document*)
				OUT="`test_msi "$1" 2>&1`"
				RET=$?
				;;
			*.[Cc][Aa][Bb]===*|*[Cc]abinet*)
				OUT="`test_cab "$1" 2>&1`"
				RET=$?
				;;
			*.[Ii][Ss][Oo]===*|*ISO\ 9660*)
				OUT="`test_iso "$1" 2>&1`"
				RET=$?
				;;
			*.[Rr][Aa][Rr]===*)
				OUT="`test_rar "$1" 2>&1`"
				RET=$?
				;;
			*.[Rr][Pp][Mm]===*)
				OUT="`test_rpm "$1" 2>&1`"
				RET=$?
				;;
			*.[Dd][Ee][Bb]===*)
				OUT="`test_deb "$1" 2>&1`"
				RET=$?
				;;
			*.[Ee][Xx][Ee]===*|*DOS\ executable*)
				OUT="`test_sfx_exe "$1" 2>&1`"
				RET=$?
				;;
			*executable\ shell\ script*)
				case "$1" in
					*.[Bb][Ii][Nn]n|*.[Ss][Hh]|*.[Rr][Uu][Nn])
					OUT="`test_sfx_bin "$1" 2>&1`"
					RET=$?
					;;
				esac
				;;
			*.7[Zz]*)
				OUT="`test_p7zip "$1" 2>&1`"
				RET=$?
				;;

			*)
				if [ "$VERBOSE" -ge 2 ]; then
					echo "SKIP: Unknown file type: '$1'" >&2
					[ "$VERBOSE" -ge 3 ] && echo "===== $FILETYPE" >&2
					echo "" >&2
				fi
				NO_RENAME="1"
				;;
		esac
		if [ "$RET" -gt 0 -a "$RET" != 255 ]; then
			echo "$OUT" >&2
			echo "=== FAILED	($RET)" >&2

			[ x"$NO_RENAME" = x0 ] && \
				rename_bad_file "$1"

			echo "" >&2
		fi
		if [ "$RET" = 0 ]; then
			if [ "$VERBOSE" -gt 0 ]; then
				echo "$OUT"
				echo "===   OK"
				echo ""
			fi
		fi
	else
		echo "ERROR: not a valid file name or file is not accessible: '$1'" >&2
	fi
	return $RET
}

test_rootobj() {
	if [ -r "$1" ]; then
		[ x"$DEBUG" != x ] && echo "=== HIDE_ERR = '$HIDE_ERR', VERBOSE = '$VERBOSE'"
		if [ -f "$1" ]; then
			test_archive "$1"
			TRORES=$?
			[ x"$TRORES" = x255 ] && return 0
			return $TRORES
		fi
		if [ -d "$1" -a -x "$1" ]; then
			echo "===== RECURSE: dir '$1'..."
			find "$1" -type f | { TRORES=0; while read F; do
				test_archive "$F"
				R=$?
				[ $R = 255 -o $R = 0 ] || TRORES=$R
			done; unset R; return $TRORES; }
			return
		fi
	fi
	echo "ERROR: not a valid file/dir name or it is not accessible: '$1'" >&2
	return 126
}

PATH=/opt/COSas/bin:/opt/COSac/bin:/usr/local/bin:/usr/sfw/bin:/opt/sfw/bin:/usr/gnu/bin:/opt/gnu/bin:/usr/bin:$PATH
export PATH

_FILE="`match_prog ${_FILE} file`"
if [ $? != 0 ]; then
	echo "ERROR: 'file' program not found, but is required!" >&2
	exit 127
fi
_GTAR="`match_prog ${_GTAR} gtar`" && export _GTAR
_GZIP="`match_prog ${_GZIP} pigz gzip`" && export _GZIP
_BZIP="`match_prog ${_BZIP} ${_BZIP2} pbzip2 bzip2`" && export _BZIP && _BZIP2="$_BZIP" && export _BZIP2
_UNZIP="`match_prog ${_UNZIP} unzip`" && export _UNZIP
_CPIO="`match_prog ${_CPIO} cpio`" && export _CPIO
_UNCOMPRESS="`match_prog ${_UNCOMPRESS} uncompress`"  && export _UNCOMPRESS
_P7ZIP="`match_prog ${_P7ZIP} 7z p7zip`" && export _P7ZIP

_MD5SUM="`match_prog ${_MD5SUM} md5sum`" && export _MD5SUM
_SHA256SUM="`match_prog ${_SHA256SUM} sha256sum`" && export _SHA256SUM
_SHA512SUM="`match_prog ${_SHA512SUM} sha512sum`" && export _SHA512SUM
_SHA1SUM="`match_prog ${_SHA1SUM} sha1sum`" && export _SHA1SUM
_OPENSSL="`match_prog ${_OPENSSL} openssl`" && export _OPENSSL

### TODO: add more programs (xz)
### TODO: parallelize (GNU parallel, gmake -j, etc.)

_ALGO_MD5SUM=""
_ALGO_SHA256SUM=""
_ALGO_SHA512SUM=""
_ALGO_SHA1SUM=""
if [ x"$_OPENSSL" != x -a -x "$_OPENSSL" ]; then
	_ALGO_MD5SUM="algo_md5sum_openssl"
	_ALGO_SHA256SUM="algo_sha256sum_openssl"
	_ALGO_SHA512SUM="algo_sha512sum_openssl"
	_ALGO_SHA1SUM="algo_sha1sum_openssl"
fi
if [ x"$_MD5SUM" != x -a -x "$_MD5SUM" ]; then
	_ALGO_MD5SUM="algo_md5sum_native"
fi
if [ x"$_SHA256SUM" != x -a -x "$_SHA256SUM" ]; then
	_ALGO_SHA256SUM="algo_sha256sum_native"
fi
if [ x"$_SHA512SUM" != x -a -x "$_SHA512SUM" ]; then
	_ALGO_SHA512SUM="algo_sha512sum_native"
fi
if [ x"$_SHA1SUM" != x -a -x "$_SHA1SUM" ]; then
	_ALGO_SHA1SUM="algo_sha1sum_native"
fi

###########################################
VERBOSE=1

# Two flags below are used in rename_bad_file()
LS_BADFILES=0
ACTIVE_RENAME=0

### TODO: Maybe add a command-line setting for this
[ x"$CKSUM_NOFILE_REACTION_DEFAULT" = x ] && \
	CKSUM_NOFILE_REACTION_DEFAULT="WARN"
[ x"$CKSUM_NOFILE_REACTION_DEFAULT" = xWARN ] || \
	CKSUM_NOFILE_REACTION_DEFAULT="ERROR"
CKSUM_NOFILE_REACTION="$CKSUM_NOFILE_REACTION_DEFAULT"

TESTED_ROOTS=0
RES_OVERALL=0
while [ $# -gt 0 ]; do
	case "$VERBOSE" in
		-*|0|1)	HIDE_ERR="2>/dev/null 1>/dev/null"
			HIDE_ERR2="2>/dev/null"
			HIDE_ERR1="1>/dev/null"
			;;
		2)		HIDE_ERR="2>/dev/null"
			HIDE_ERR2="2>/dev/null"
			HIDE_ERR1="" ;;
		3|*)	HIDE_ERR=""; HIDE_ERR1=""; HIDE_ERR2="" ;;
	esac

	if [ x"$1" != x ]; then
		case "$1" in
		-h)	echo "$0 tests archive file validity"
			echo "Usage: $0 [-v|-q] [-fr] [-ls] file... dir..."
			echo "	-v|-q	Increase/Decrease verbosity"
			echo "		Recognized verbosity levels (passed to archivers):"
			echo "		0 -q	Only report command-line objects and errors"
			echo "		1 (def)	Report all checked (not skipped) objects"
			echo "		2 -v	Report all objects and list archive contents"
			echo "		3 -v -v	Report all objects and print detailed archive contents"
			echo "	-fr	Active fix of broken archives by renaming files"
			echo "	-ls	List information about broken archives (ls -ladi)"
			echo "	file	File name or pattern to test explicitly"
			echo "	dir	Directory name or pattern to recurse into"
			exit 1
			;;
		-ls)	LS_BADFILES=1 ;;
		-fr)	ACTIVE_RENAME=1 ;;
		-v)	VERBOSE=$(($VERBOSE+1)) ;;
		-q)	VERBOSE=$(($VERBOSE-1))
			[ "$VERBOSE" -lt 0 ] && VERBOSE=0
			;;
		*)	test_rootobj "$1" || RES_OVERALL=$?
			TESTED_ROOTS=$(($TESTED_ROOTS+1))
			;;
		esac
	fi
	shift
done

if [ x"$TESTED_ROOTS" = x0 ]; then
	echo "WARNING: No targets given to test, assuming recursion from current dir..."
	test_rootobj . || RES_OVERALL=$?
fi

exit $RES_OVERALL
