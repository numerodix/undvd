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

my ($opts_start, $opts_end, $target_size, $bpp, $target_passes, $autocrop, $prescale, $postscale);
my ($dry_run, $acodec, $vcodec);
my $custom_scale;# = "off";
my $container = $defaults->{container};

my $parse = GetOptions(
	"start=f"=>\$opts_start,
	"e|end=f"=>\$opts_end,

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

	"cont=s"=>\$container,
	"acodec=s"=>\$acodec,
	"vcodec=s"=>\$vcodec,
);

print_tool_banner();

if (! $parse) {
	print $usage;
	exit 2;
}

my @startpos = ("-ss", $opts_start ? $opts_start : 0);
my @endpos;
if ($opts_end) {
	push(@endpos, "-endpos", $opts_end);
}

my @files = @ARGV;
if (scalar @files < 1) {
	nonfatal("No files to encode, exiting");
	print $usage;
	exit 2;
}


init_logdir();


# Set container and codecs

my ($audio_codec, $video_codec, $ext, @cont_opts) = set_container_opts($acodec,
	$vcodec, $container);

print " - Output format :: "
	. "container: " . s_it($container)
	. "  audio: "   . s_it($audio_codec)
	. "  video: "   . s_it($video_codec) . "\n";


# Display dry-run status

if ($dry_run) {
	print " * Performing dry-run\n";
	print_title_line(1);
}

foreach my $file (@files) {

	if (! -e $file) {
		nonfatal("File %%%$file%%% does not exist");
		next;
	}

	my $title = $file;
	$title =~ s/\..*//g;


	# Display encode status

	if (! $dry_run) {
		print " * Now encoding file " . s_bb(substr($file, 0, 36));
		if ($opts_start and $opts_end) {
			print "  [" . s_bb($opts_start) . "s - " . s_bb($opts_end) . "s]";
		} elsif ($opts_start) {
			print "  [" . s_bb($opts_start) . "s -> ]";
		} elsif ($opts_end) {
			print "  [ -> " . s_bb($opts_end) . "s]";
		}
		print "\n";
	}


	# Extract information from the title

	my $title_data = examine_title($file);


	# Do we need to crop?

	if ($autocrop) {
		print " + Finding out how much to crop...\r";
		my ($width, $height, @crop_opts) = crop_title($file);
		if (! $width or ! $height or ! @crop_opts) {
			fatal("Crop detection failed");
		}
		$title_data->{width} = $width;
		$title_data->{heigth} = $height;
		use Data::Dumper;
		print Dumper($title_data);
	}

	# Find out how to scale the dimensions

	my ($width, $height) =
		scale_title($title_data->{width}, $title_data->{heigth}, $custom_scale);
	$title_data->{width} = $width;
	$title_data->{heigth} = $height;
	my $scale_opts = "scale=$width:$height";

	# Estimate filesize of audio



}
