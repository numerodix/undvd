#!/usr/bin/perl
#
# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.

use strict;

use colors;
use functions;


my $verbose = 0;


my ($exit, $lsdvd) = run("which", "lsdvd");

print " * Scanning DVD for titles...\n";
my ($exit, $out, $err) = run($lsdvd, "-avs", "-q", "/ex/tt/disc.iso", "2>/dev/null");

if ($exit) {
	print $colors::e . $err . $colors::r . "\n";
	print "usage\n";
	exit 2;
}


my @title_numbers = map( { /^Title: ([0-9]*)/ } split(/\n/, $out));

foreach my $titleno (@title_numbers) {
	my ($title_s, $length, @aids, @alangs, @sids, @slangs);
	if ($out =~ /(Title: $titleno.*?\n\n)/s) { $title_s = $1; }

	if ($title_s =~ /Title: $titleno, Length: ([0-9:]+)/) { $length = $1; }

	while ($title_s =~ m/Audio: .*Language: ([a-zA-Z]+)/g) { push(@alangs, $1); }
	while ($title_s =~ m/Audio: .*Stream id: (0x[0-9abcdefABCDEF]+)/g) {
		push(@aids, oct($1)); }

	while ($title_s =~ m/Subtitle: .*Language: ([a-zA-Z]+)/g) { push(@slangs, $1); }
	while ($title_s =~ m/Subtitle: .*Stream id: (0x[0-9abcdefABCDEF]+)/g) {
		push(@sids, oct($1)); }

	my $audio = "";
	for (my $i = 0; $i < scalar @aids; $i++) {
		if ($i == 0) { $audio = "audio: "; }
		$audio .= $colors::bb . $alangs[$i] . $colors::r . " ";
		if ($verbose) { $audio .= $colors::it . $aids[$i] . $colors::r . " "; }
	}
	$audio =~ s/\s*$//;

	my $subs = "";
	for (my $i = 0; $i < scalar @sids; $i++) {
		if ($i == 0) { $subs = "subs: "; }
		$subs .= $colors::bb . $slangs[$i] . $colors::r . " ";
		if ($verbose) { $subs .= $colors::it . $sids[$i] . $colors::r . " "; }
	}
	$subs =~ s/\s*$//;

	print $colors::b . $titleno . $colors::r
		."  length: " . $colors::bb . $length . $colors::r
		."  " . $audio
		."  " . $subs . "\n";
}

print "\nTo watch a title:\n";
print " "      . $colors::b . "mplayer" . $colors::r
	."       " . $colors::b . "dvd://"  . $colors::bb . "01" . $colors::r
	."     "   . $colors::b . "-alang " . $colors::bb . "en" . $colors::r
	."  "      . $colors::b . "-slang " . $colors::bb . "en/off" . $colors::r . "\n";
print "To rip titles:\n";
print " "        . $colors::b . "undvd" . $colors::r
	."         " . $colors::b . "-t " . $colors::bb . "01,02,03" . $colors::r
	."  "        . $colors::b . "-a " . $colors::bb . "en" . $colors::r
	."      "    . $colors::b . "-s " . $colors::bb . "en/off" . $colors::r . "\n";
