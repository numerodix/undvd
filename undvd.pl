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
	.       s_b("-t") . " " . s_bb("01,02,03") . " "
	.       s_b("-a") . " " . s_bb("en") . " "
	.       s_b("-s") . " " . s_bb("es") . " "
	. "[" . s_b("-d") . " " . s_bb("/dev/dvd") . "]"
	. " [" . s_b("more options") . "]\n
  -t --title    title(s) to rip (comma separated)
  -a --audio    audio language (two letter code, eg. " . s_bb("en") . ", or integer id)
  -s --subs     subtitle language (two letter code or " . s_bb("off") . ", or integer id)\n
  -d --dev      dvd device to rip from (default is " . s_bb("/dev/dvd") . ")
  -q --dir      dvd directory to rip from
  -i --iso      dvd iso image to rip from\n
     --start    start after this many seconds (usually for testing)
  -e --end      end after this many seconds (usually for testing)\n
  -C            do sanity check (check for missing tools)
  -z --adv      <show advanced options>
     --version  show " . $suite->{name} . " version\n";

my $adv_usage = "Advanced usage:  " . s_b($suite->{tool_name}) . " "
	. " [" . s_b("standard options") . "]"
	. " [" . s_b("advanced options") . "]
  -o --size     output file size in mb (integer value)
     --bpp      bits per pixel (float value)
  -1            force 1-pass encoding
  -2            force 2-pass encoding
  -u --enc      dvd is encrypted, clone with vobcopy (needs libdvdcss)
  -n --noclone  no disc cloning (encode straight from the dvd)
  -c --crop     autocrop video
  -r --scale    scale video to x:y (integer value or " . s_bb("0") . ") or " . s_bb("off") . " to disable
  -f --smooth   use picture smoothing filter
  -D --dryrun   dry run (display encoding parameters without encoding)\n
     --cont     set container format
     --acodec   set audio codec
     --vcodec   set video codec\n";

my ($titles, $alang, $slang, $mencoder_source, $dvd_is_dir,
	$dvd_is_iso, $opt_noclone, $encrypted);
my ($opts_start, $opts_end, $target_size, $bpp, $autocrop);
my ($dry_run, $opts_acodec, $opts_vcodec, $opts_cont);

my $dvd_device = $defaults->{dvd_device};
my $skipclone = 0;
my $custom_scale;
my $target_passes = 1;
my $prescale = $defaults->{prescale};
my $postscale = $defaults->{postscale};

my $parse = GetOptions(
	"t|titles=s"=>\$titles,
	"a|audio=s"=>\$alang,
	"s|subs=s"=>\$slang,

	"d|dev=s"=> sub { $dvd_device = $_[1]; },
	"q|dir=s"=> sub { $dvd_is_dir = 1; $mencoder_source = $_[1]; },
	"i|iso=s"=> sub { $dvd_is_iso = 1; $mencoder_source = $_[1]; $skipclone = 1; },

	"start=f"=>\$opts_start,
	"e|end=f"=>\$opts_end,

	"C"=> sub { init_cmds(1); exit; },
	"z|adv"=> sub { print $adv_usage; exit; },
	"version"=>\&print_version,

	"o|size=i"=>\$target_size,
	"bpp=f"=>\$bpp,
	"1"=> sub { $target_passes = 1; },
	"2"=> sub { $target_passes = 2; },
	"u|enc"=> sub { $encrypted = 1; },
	"n|noclone"=> sub { $skipclone = 1; $opt_noclone = 1; },
	"c|crop"=> sub { $autocrop = 1; },
	"r|scale=s"=>\$custom_scale,
	"f|smooth"=> sub { $prescale .= "spp,"; $postscale = ",hqdn3d$postscale"; },
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


if (! -e $dvd_device) {
	print s_wa("=>") . " The dvd device " . s_bb($dvd_device) . " does not exist.\n";
	print s_wa("=>") . " Supply the right dvd device to " . $suite->{tool_name}
		.  ", eg:\n";
	print "    " . s_b($suite->{tool_name}) . " " . s_b("-d") . " " . s_bb($dvd_device)
		. " [" . s_b("other options") . "]\n";
	exit 2;
}

if ($opt_noclone) {
	if ((! $dvd_is_dir) and (! $dvd_is_iso)) {
		$mencoder_source = $dvd_device;
	}
}

my @startpos = ("-ss", $opts_start ? $opts_start : 0);
my @endpos;
if ($opts_end) {
	push(@endpos, "-endpos", $opts_end);
}

my @files = split(",", $titles);
if (scalar @files < 1) {
	nonfatal("No titles to rip, exiting");
	print $usage;
	exit 2;
}

my @audio_args;
if (! $alang) {
	nonfatal("No audio language selected, exiting");
	print $usage;
	exit 2;
} else {
	@audio_args = ternary_int_str($alang, "-aid", "-alang");
}

my @subs_args;
if (! $slang) {
	push(@subs_args, "-slang", "off");
} else {
	@subs_args = ternary_int_str($slang, "-sid", "-slang");
}


init_logdir();


# Set container and codecs

my $container = $opts_cont ? $opts_cont : $defaults->{container};
my ($audio_codec, $video_codec, $ext, @cont_args) = set_container_opts($opts_acodec,
	$opts_vcodec, $container);

print " - Output format :: "
	. "container: " . s_it($container)
	. "  audio: "   . s_it($audio_codec)
	. "  video: "   . s_it($video_codec) . "\n";


# Clone dvd

if ((! $dvd_is_dir) and (! $skipclone)) {
	print " * Cloning dvd to disk first... ";

	my $exit;
	if ($encrypted) {
		$exit = clone_vobcopy($dvd_device, $defaults->{disc_dir});
	} else {
		$exit = clone_dd($dvd_device, $defaults->{disc_image});
	}

	if ($exit) {
		print s_err("failed, check log")."\n";
	} else {
		print s_ok("done")."\n";
	}
}


# Display dry-run status

if ($dry_run) {
	print " * Performing dry-run\n";
	print_title_line(1);
}

foreach my $file (@files) {

	my $title_name = $file;


	# Display encode status

	if (! $dry_run) {
		print " * Now ripping title " . s_bb(trunc(38, 1, $file, "..."));
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

	my $title = examine_title("dvd://$file", $mencoder_source);

	# Init encoding target info

	my $ntitle = copy_hashref($title);
	$ntitle->{aformat} = $audio_codec;
	$ntitle->{vformat} = $video_codec;
	$ntitle->{filename} = "$title_name.$ext";


	# Do we need to crop?

	my $crop_arg;
	if ($autocrop) {
		my $est = get_crop_eta($ntitle->{length}, $ntitle->{fps});
		print " + Finding out how much to crop... (est: ${est}min)\r";
		my ($width, $height);
		($width, $height, $crop_arg) = crop_title("dvd://$file",
			$mencoder_source);
		if (! $width or ! $height or ! $crop_arg) {
			fatal("Crop detection failed");
		}
		$ntitle->{width} = $width;
		$ntitle->{height} = $height;
	}

	# Find out how to scale the dimensions

	my ($width, $height) =
		scale_title($ntitle->{width}, $ntitle->{height}, $custom_scale);
	$ntitle->{width} = $width;
	$ntitle->{height} = $height;
	my $scale_arg = "scale=$width:$height";

	# Estimate filesize of audio

	$ntitle->{abitrate} = set_acodec_opts($container, $ntitle->{aformat},
		$ntitle->{abitrate}, 1);
	my $audio_size = compute_media_size($ntitle->{length}, $ntitle->{abitrate});
	my @acodec_args = set_acodec_opts($container, $ntitle->{aformat},
		$ntitle->{abitrate});

	# Decide bpp

	if ($bpp) {
		$ntitle->{bpp} = $bpp;
	} elsif ($target_size) {
		my $video_size = $target_size - $audio_size;
		$video_size = 1 if $video_size <= 0;
		$ntitle->{bpp} = compute_bpp($ntitle->{width}, $ntitle->{height},
			$ntitle->{fps}, $ntitle->{length}, $video_size);
	} else {
		$ntitle->{bpp} = set_bpp($video_codec, $target_passes);
	}

	# Reset the number of passes based on the bpp

	if ($target_passes) {
		$ntitle->{passes} = $target_passes;
	} else {
		$ntitle->{passes} = set_passes($video_codec, $ntitle->{bpp});
	}

	# Compute bitrate

	$ntitle->{vbitrate} = compute_vbitrate($ntitle->{width},
		$ntitle->{height}, $ntitle->{fps}, $ntitle->{bpp});


	# Dry run

	if ($dry_run) {

		# Estimate output size

		if ($target_size) {
			$ntitle->{filesize} = $target_size;
		} else {
			my $video_size = compute_media_size($ntitle->{length},
				$ntitle->{vbitrate});
			$ntitle->{filesize} = int($video_size + $audio_size);
		}

		$ntitle->{filename} = "$title_name.$container";

		print_title_line(0, $title);
		print_title_line(0, $ntitle);


	# Encode video

	} else {

		for (my $pass = 1; $pass <= $ntitle->{passes}; $pass++) {
			my @vcodec_args = set_vcodec_opts($ntitle->{vformat},
				$ntitle->{passes}, $pass, $ntitle->{vbitrate});

			my @args = (@startpos, @endpos);
			push(@args, "-vf", "${crop_arg}${prescale}${scale_arg}${postscale}");
			push(@args, "-oac", @acodec_args);
			push(@args, "-ovc", @vcodec_args);
			push(@args, "-of", @cont_args);
			push(@args, "-dvd-device", $mencoder_source);

			run_encode(\@args, "dvd://$file", $title_name, $ext, $ntitle->{length},
				$ntitle->{passes}, $pass);
		}

		if (-f "$title_name.$ext.partial") {
			rename("$title_name.$ext.partial", "$title_name.$ext");
		}

		if (-f "divx2pass.log") {
			unlink("divx2pass.log");
		}

		remux_container($title_name, $ext, $ntitle->{fps}, $container,
			$ntitle->{aformat}, $ntitle->{vformat});

	}

}
