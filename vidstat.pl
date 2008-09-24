#!/usr/bin/perl
#
# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.

use strict;
use Getopt::Long qw(:config no_ignore_case);

BEGIN {
	use File::Basename;
	push(@INC, dirname(grep(-l, $0) ? readlink $0 : $0));
	require colors; colors->import(qw(:DEFAULT));
	require common; common->import(qw(:DEFAULT $suite $defaults $tools));
}


my $usage = "Usage:  "   . s_b($suite->{tool_name})   . " ["
	. s_bb("<file(s)>") . " | "
	. s_b("--dev") . " " . s_bb("/dev/dvd") . " | "
	. s_b("--dir") . " " . s_bb("/path")    . " | "
	. s_b("--iso") . " " . s_bb("disc.iso") . "]
  <file(s)>     files to read
  -d --dev      dvd device to read from (default is " . s_bb("/dev/dvd") . ")
  -q --dir      dvd directory to read from
  -i --iso      dvd iso image to read from
     --version  show " . $suite->{name} . " version\n";

my $dvd_device;
GetOptions(
	"d|dev=s"=>\$dvd_device,
	"q|dir=s"=>\$dvd_device,
	"i|iso=s"=>\$dvd_device,
	"version"=>\&print_version,
);

print_tool_banner();

if ((! $dvd_device) and (! @ARGV)) {
	print "$usage";
	exit 2;
}


my @titles = ();
if ($dvd_device) {
	my $titles_count = examine_dvd_for_titlecount($dvd_device);
	for (my $i = 1; $i <= $titles_count; $i++) {
		push(@titles, $i);
	}
} else {
	@titles = @ARGV;
}

foreach my $title (@titles) {
	my $dvd_source;
	if ($dvd_device) {
		$dvd_source = $dvd_device;
		$title = "dvd://$title";
	}
	my $data = examine_title($title, $dvd_device);
	use Data::Dumper;
	print Dumper($data);
}
