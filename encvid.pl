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

GetOptions(
	"z|adv"=> sub { print $adv_usage; exit; },
	"version"=>\&print_version,
);

print_tool_banner();

print $usage;

