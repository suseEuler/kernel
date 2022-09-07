#!/usr/bin/perl -w
#
# Copyright (c) 2022 Yunche Information Technology (Shenzhen) Co., Ltd.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.
#

#
# The script compares the hash value decrypted from the ko file's
# sign part with hash value calculated from ko data without signed info.
# Reference: https://unix.stackexchange.com/questions/493170/how-to-verify-a-kernel-module-signature/496800#496800
#
# Usage: ./checkmod.pl pubkey.pem MODULE.ko
#
# pubkey.pem: extracted from cert information in vmlinux
# MODULE.ko: ko file with sign part
#
# Return code:
#	0: equal
#	1: not equal
#

use strict;
use IPC::Open2;

sub feedcmddata {
	my ($cmd, $data) = @_;
	my ($pid, $output, $in);
	$pid = open2 $output, $in, $cmd;
	print $in $data;
	close $in;
	my @out = ();
	while(<$output>) {
		push @out, $_;
	}
	waitpid ($pid, 0);
	die "$cmd: status $?" if $? != 0;
	return join "", @out;
}

sub extract_OCTET {
	my ($data) = @_;
	my $output = feedcmddata "openssl asn1parse -inform der", $data;
	my @tmp = grep /OCTET STRING/, split /\n/, $output;
	@tmp = split /:/, $tmp[-1];
	return $tmp[-1];
}

my $pubkey = shift;
my $ko_file = shift;

my $full_sig = `./extract-module-sig.pl -s $ko_file 2>/dev/null`;
my $ko = `./extract-module-sig.pl -0 $ko_file 2>/dev/null`;
my $output;
my @tmp;
my $sig = extract_OCTET $full_sig;
$sig =~ s/\n$//;
$sig = pack("H*", $sig);
my $checked = feedcmddata "openssl rsautl -verify -inkey $pubkey -pubin", $sig;
my $ehash = lc extract_OCTET $checked;
my $fhash = feedcmddata "sha256sum", $ko;
@tmp = split /\s+/, $fhash;
$fhash = $tmp[0];
if ($ehash eq $fhash) {
	exit 0;
}
exit 1;
