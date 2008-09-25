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


my $usage = "Usage:  " . s_b($suite->{tool_name}) . " "
	. s_bb("<file(s)>")
	. " [" . s_b("options") . "]
  <file(s)>     files to encode\n
     --start    start after this many seconds (usually for testing)
  -e --end      end after this many seconds (usually for testing)\n
  -C            do sanity check (check for missing tools)
  -z --adv      <show advanced options>
     --version  show " . $suite->{name} . " version\n";

my $adv_usage = "Advanced usage:  " . s_b($suite->{tool_name}) . " "
	. s_bb("<file(s)>")
	. " [" . s_b("options") . "]
  -o --size     output file size in mb (integer value)
     --bpp      bits per pixel (float value)
  -1            force 1-pass encoding
  -2            force 2-pass encoding
  -c --crop     autocrop video
  -r --scale    scale video to x:y (integer value or " . s_bb("0") . ") or " . s_bb("off") . " to disable
  -f --smooth   use picture smoothing filter
  -D --dryrun   dry run (display encoding parameters without encoding)\n
     --cont     set container format
     --acodec   set audio codec
     --vcodec   set video codec\n";

my ($opts_start, $opts_end);
my ($target_size, $bpp, $target_passes, $autocrop, $custom_scale, $prescale,
	$postscale, $dry_run);
my ($opts_cont, $opts_acodec, $opts_vcodec);

my $parse = GetOptions(
	"start=i"=>\$opts_start,
	"e|end=i"=>\$opts_end,

	"C"=> sub { init_cmds(1); exit; },
	"z|adv"=> sub { print $adv_usage; exit; },
	"version"=>\&print_version,

	"o|size=i"=>\$target_size,
	"bpp=f"=>\$bpp,
	"1"=> sub { $target_passes = 1; },
	"2"=> sub { $target_passes = 2; },
	"c|crop"=> sub { $autocrop = 1; },
	"r|scale=s"=>\$custom_scale,
	"f|smooth"=> sub { $prescale = "spp,"; $postscale = ",hqdn3d"; },
	"D|dryrun"=> sub { $dry_run = 1; },

	"cont=s"=>\$opts_cont,
	"acodec=s"=>\$opts_acodec,
	"vcodec=s"=>\$opts_vcodec,
);

print_tool_banner();

if (! $parse) {
	print $usage;
	exit 2;
}


if (scalar @ARGV < 1) {
	nonfatal("No files to encode, exiting");
	print $usage;
	exit 2;
}
