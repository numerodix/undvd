#!/usr/bin/perl
#
# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.

use strict;
use Getopt::Long;

use colors;
use functions;


my $usage = "Usage:  "   . s_b("scandvd")   . " ["
	. s_b("--dev") . " " . s_bb("/dev/dvd") . " | "
	. s_b("--dir") . " " . s_bb("/path")    . " | "
	. s_b("--iso") . " " . s_bb("disc.iso") . "]
  -d --dev      dvd device to read from (default is " . s_bb("/dev/dvd") . ")
  -q --dir      dvd directory to read from
  -i --iso      dvd iso image to read from
  -v            be verbose (print id numbers)
     --version  show undvd version\n";

my ($verbose, $dvd_device, $dvd_is_dir);
GetOptions(
	"d|dev=s"=>\$dvd_device,
	"q|dir=s"=> sub { $dvd_device = $_[1]; $dvd_is_dir = "-q"; },
	"i|iso=s"=> sub { $dvd_device = $_[1]; $dvd_is_dir = "-q"; },
	"v"=>\$verbose,
);

print_tool_banner

my ($exit, $lsdvd) = run("which", "lsdvd");

print " * Scanning DVD for titles...\n";
my ($exit, $out, $err) = run($lsdvd, "-avs", $dvd_is_dir, $dvd_device, "2>/dev/null");

if ($exit) {
	print s_err($err) . "\n";
	print "$usage";
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
		if ($i == 0) { $audio = "  audio: "; }
		$audio .= s_bb($alangs[$i]) . " ";
		if ($verbose) { $audio .= s_it($aids[$i]) . " "; }
	}
	$audio =~ s/\s*$//;

	my $subs = "";
	for (my $i = 0; $i < scalar @sids; $i++) {
		if ($i == 0) { $subs = "  subs: "; }
		$subs .= s_bb($slangs[$i]) . " ";
		if ($verbose) { $subs .= s_it($sids[$i]) . " "; }
	}
	$subs =~ s/\s*$//;

	print s_b($titleno) ."  length: " . s_bb($length) . $audio . $subs . "\n";
}

print "\nTo watch a title:\n";
print " "      . s_b("mplayer")
	."       " . s_b("dvd://") . s_bb("01")
	."     "   . s_b("-alang") . " " . s_bb("en")
	."  "      . s_b("-slang") . " " . s_bb("en/off") . "\n";
print "To rip titles:\n";
print " "        . s_b("undvd")
	."         " . s_b("-t") . " " . s_bb("01,02,03")
	."  "        . s_b("-a") . " " . s_bb("en")
	."      "    . s_b("-s") . " " . s_bb("en/off") . "\n";
