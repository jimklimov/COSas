#!/usr/bin/perl

### ldifsort.pl
### (C) Jan 2009-Aug 2013 by Jim Klimov, COS&HT
### $Id: ldifsort-fulltree.pl,v 1.13 2013/11/02 12:29:19 jim Exp $
### Sorts alphabetically the input LDIF file to an output long-line LDIF
### for easier DIFF comparison. Accepts standard wrapped-LDIF input.
###
### This special variant of ldifsort.pl also alphabetically sorts the LDAP
### entries (by DN tree) and may require more RAM/swap to complete the sort
### with large input sets.
### NOTE: Result may not be valid LDIF file format for import to LDAP with
### common (or any) tools. It is primarily intended for content comparisons!
###
### Usage: ./ldifsort.pl < dsexport=ldapsrv01-20090128T112356Z.ldif > c1.ldif
###   to strip comments and replication info from attribute names pipe thru:
###     | egrep -v '^#' | sed 's/^\([^;:]*\)[^ :]*\(:* .*\)$/\1\2/'
###   to strip replication info from attribute names and remove "deleted" values:
###     | egrep -v '^(.*;.*delete.*:|ds6ruv:|nsds50ruv:) ?.*$' | sed 's/^\([^;]*\);[^ :]*\(:* .*\)$/\1\2/'
###   to strip create/modify metadata:
###	| egrep -vi '^((creator|modifier)sName|(modify|create)Timestamp): '

### Parameters
$DEBUG=0;
$WRITE_COMMENT=1;

### Init variables
$COMMENT="";
$DN="";
$PREVLINE="";
$NUM=0;

$ldifother="";

### Counters
$NUMENTRIES=0;
$NUMBLOCKS=0;

sub convertDN() {
    local ( $sDN ) = @_;

    if ( $DEBUG > 5 ) { print STDERR "DEBUG: src(DN)\t=$sDN\n"; }

    if ( $sDN =~ /^dn::\s*(.*)$/ ) {
	$sDN="dn: " . decode_base64($1);
	if ( $DEBUG > 5 ) { print STDERR "DEBUG: src_decoded(DN)\t=$sDN\n"; }
    }

    ### Use lowercase to simplify comparison
    $sDN = lc($sDN);

    if ( $DEBUG > 5 ) { print STDERR "DEBUG: lc(DN)\t=$sDN\n"; }

    ### strip whitespaces around separators (commas)
    $sDN =~ s/\s*\,\s*/,/g;
    $sDN =~ s/^dn::?\s*//;

    if ( $DEBUG > 5 ) { print STDERR "DEBUG: cut(DN)\t=$sDN\n"; }

    $sDN = join ("," , reverse ( split (/,/ , $sDN ) ) );

    if ( $DEBUG > 5 ) { print STDERR "DEBUG: rev(DN)\t=$sDN\n"; }

    return $sDN;
}

use MIME::Base64 qw( decode_base64 );

while ( <> ) {
	chomp;

	if ( /^(#.*)$/ ) { 
	    ### LDIFs generated by Sun dsconf export can contain comments
	    $COMMENT .= $1 . "\n"
	} elsif ( /^(dn::? .*)$/ ) {
	    $DN=$1;
	} elsif ( /^ (.*)$/ ) {
	    ### A single space tabulates wrapped-LDIF long lines
	    if ( $PREVLINE ne "" ) {
	        $PREVLINE .= "$1";
	    } elsif ( $DN ne "" ) {
		$DN .= "$1";
	    } elsif ( $COMMENT ne "" ) {
		$COMMENT .= "$1";
	    } else {
		die "  !!! bogus line: $_\n";
	    }
	} elsif ( /^$/ ) {
	    ### Input entry has finished...

	    ### Capture last line to array
	    if ( $PREVLINE ne "" ) {
		$entrylines{$PREVLINE} = $NUM++;
	    }

	    if ( $DN ne "" ) {
		$NUMENTRIES++;
		$ldifdata{$DN}->{"nSRC"} = "$NUMENTRIES";
		$ldifdata{$DN}->{"sDN"} = "$DN";
		$ldifdata{$DN}->{"sDNcmp"} = &convertDN( "$DN" );

		### comment includes \n if exists at all
	        if ( $COMMENT ne "" ) {
		    $ldifdata{$DN}->{"sCOMMENT"} = "$COMMENT";
		    if ( $WRITE_COMMENT ne 0 ) {
			$ldifdata{$DN}->{"sText"} = "$COMMENT"; 
		    }
		}

		if ( $WRITE_COMMENT ne 0 && $DN =~ /^dn::\s*(.*)$/ ) {
		    $ldifdata{$DN}->{"sText"} .= 
			"# dn: " . decode_base64($1) . "\n";
		}

		$ldifdata{$DN}->{"sText"} .= "$DN\n";

	        foreach $line ( sort (keys %entrylines) ) {
		    if ( $line ne "" ) {
			$ldifdata{$DN}->{"sText"} .= "$line\n";
		    }
		}

	        if ( $DEBUG > 1 ) { print STDERR "$NUM\tattributes in\t$DN\n"; }
		$NUMBLOCKS++;
	    } else {
		### No DN, maybe Sun DSEE header comment
		### comment includes \n if exists at all
	        if ( $COMMENT ne "" && $WRITE_COMMENT ne 0 ) {
		    $ldifother .= "$COMMENT"; 
		}

	        foreach $line ( sort (keys %entrylines) ) {
		    if ( $line ne "" ) {
			$ldifother .= "$line\n";
		    }
		}

		$ldifother .= "\n";

	        if ( $DEBUG > 1 ) { print STDERR "$NUM\tattributes in no-DN block\n"; }
		$NUMBLOCKS++;
	    }

	    ### Init variables
	    $COMMENT="";
	    $DN="";
	    $PREVLINE="";
	    $NUM=0;
	    
	    ### Destroy assoc array
	    undef %entrylines;
	} else {
	    ### Most common case - an attribute line
	    if ( $PREVLINE ne "" ) {
		$entrylines{$PREVLINE} = $NUM++;
	    }
	    $PREVLINE = $_;
	}
}

### If there's any other data, it includes all needed newlines
print "$ldifother";

sub cmpDNs() {
    return ( $ldifdata{$a}->{"sDNcmp"} cmp $ldifdata{$b}->{"sDNcmp"} );
}

foreach $DN ( sort cmpDNs (keys %ldifdata) ) {
    if ( $ldifdata{$DN}->{"sText"} ne "" ) {
	if ( $DEBUG > 2 ) { print STDERR "DEBUG: cmp\t: ". $ldifdata{$DN}->{"sDNcmp"} . "\n"; }

	print $ldifdata{$DN}->{"sText"} . "\n";
    }
}

if ( $DEBUG > 0 ) {
    print STDERR "Stats:\n\tProcessed DN entries:\t$NUMENTRIES\n\tWritten text blocks:\t$NUMBLOCKS\n";
}