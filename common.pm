# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.

package common;

use strict;
use File::Basename;

use colors;

use base 'Exporter';
our @EXPORT_OK = qw($suite $defaults $tools);
our @EXPORT = qw(
	nonfatal
	fatal
	run
	init_cmds
	print_tool_banner
	print_version
	compute_bpp
	examine_dvd_for_titlecount
	examine_title
	print_title_line
	);


### DECLARATIONS

our $suite = {
	name => "undvd",
	version => "0.6.1",
	tool_name => basename(grep(-l, $0) ? readlink $0 : $0),
};

our $defaults = {
	dvd_device => "/dev/dvd",
	disc_image => "disc.iso",
	mencoder_source => "disc.iso",

	h264_1pass_bpp => .195,
	h264_2pass_bpp => .150,

	xvid_1pass_bpp => .250,
	xvid_2pass_bpp => .200,
};


my @videoutils = qw(lsdvd mencoder mplayer);
my @shellutils = qw(awk bash bc grep egrep getopt mount ps sed xargs);
my @coreutils = qw(cat date dd dirname head mkdir mv nice readlink rm seq sleep sort tail tr true);
my @extravideoutils = qw(mp4creator mkvmerge ogmmerge vobcopy);

my @mencoder_acodecs = qw(copy faac lavc mp3lame);
my @mencoder_vcodecs = qw(copy lavc x264 xvid);

my @mplayer_acodecs = qw(ac3);
my @mplayer_vcodecs = qw(mpeg-2);

our $tools = {};
init_cmds();


### FUNCTIONS

# non fatal error
sub nonfatal {
	my $s = shift;

	my $p = \&s_err;
	my $em = \&s_it;

	my $ms;
	while ($s =~ m/(%%%.*?%%%)/g) {
		$ms .= $p->(substr($s, 0, @-[0]));
		$ms .= $em->($&);
		$s = substr($s, @+[0]);
	}
	$ms .= $p->($s);
	$ms =~ s/%%%//g;

	print $p->("Error:") . "  $ms\n";
}

# fatal error
sub fatal {
	nonfatal($_[0]);
	exit 1;
}

# extremely suspicious
sub run {
	my (@args) = @_;

	my ($out, $exit, $err);
	print join(' ', @_)."\n" if $ENV{"DEBUG"};

	use IPC::Open3;
	my $pid = open3(\*WRITER, \*READER, \*ERROR, @args);
	wait;
	$exit = $? >> 8;

	while (my $output = <READER>) { $out .= $output; }
	while (my $output = <ERROR>) { $err .= $output; }

	chomp($out);
	chomp($err);

	return ($out, $exit, $err);
}

# check for missing dependencies
sub init_cmds {
	my $verbose = shift;

	print " * Checking for tool support...\n" if $verbose;
	foreach my $tool (@videoutils, @shellutils, @coreutils, @extravideoutils) {
		my ($tool_path, $exit, $err) = run("which", $tool);
		$tools->{$tool} = $tool_path;
		if (! $exit) {
			print "   " . s_ok("*") . " $tool_path\n" if $verbose;
		} else {
			print "   " . s_wa("*") . " $tool missing\n" if $verbose;
		}
	}

	sub codec_check {
		my $type = shift;
		my $codecs = shift;
		my $tool = shift;
		my @args = @_;

		print " * Checking for $tool $type codec support...\n";

		unshift(@args, $tools->{$tool});
		my ($out, $exit, $err) = run(@args);
		foreach my $codec (@$codecs) {
			if ($out . $err =~ /$codec/i) {
				print "   " . s_ok("*") . " $codec\n";
			} else {
				print "   " . s_wa("*") . " $codec missing\n";
			}
		}
	};

	if ($verbose) {
		codec_check("audio", \@mplayer_acodecs, "mplayer", qw(-ac help));
		codec_check("video", \@mplayer_vcodecs, "mplayer", qw(-vc help));
		codec_check("audio", \@mencoder_acodecs, "mencoder", qw(-oac help));
		codec_check("video", \@mencoder_vcodecs, "mencoder", qw(-ovc help));
	}
}

# print standard common banner
sub print_tool_banner {
	print "{( --- " . $suite->{tool_name} . " " . $suite->{version} . " --- )}\n";
}

# print package version and versions of tools
sub print_version {
	sub check_tool {
		my $tool = shift;
		my $re = shift;
		my @args = @_;

		my ($tool_path, $exit) = run("which", $tool);
		if ($exit) {
			print "  [" . s_err("!") . "] $tool missing\n";
		} else {
			unshift(@args, $tool_path);
			my ($out, $exit, $err) = run(@args);
			my $version = $1 if ($out . $err) =~ /$re/ms;
			print "  [" . s_ok("*") . "] $tool $version\n";
		}
	};
	print $suite->{name} . " " . $suite->{version} . "\n";
	check_tool("mplayer", "^MPlayer ([^ ]+)", qw());
	check_tool("mencoder", "^MEncoder ([^ ]+)", qw(-oac help));
	check_tool("lsdvd", "^lsdvd ([^ ]+)", qw(-V));
	check_tool("vobcopy", "^Vobcopy ([^ ]+)", qw(--version));
	check_tool("mp4creator", ".* version ([^ ]+)", qw(-version));
	check_tool("mkvmerge", "^mkvmerge ([^ ]+)", qw(--version));
	check_tool("ogmmerge", "^ogmmerge ([^ ]+)", qw(--version));
	exit;
}

# compute bits per pixel
sub compute_bpp {
	my $width = shift;
	my $height = shift;
	my $fps = shift;
	my $length = shift;
	my $video_size = shift;		# in mb
	my $bitrate = shift;	# kbps

	if ($bitrate) {
		$bitrate = $bitrate * 1024;
	} else {
		$video_size = $video_size * 1024 * 1024;
		$bitrate = (8 * $video_size)/( $length != 0 ? $length : 1 );
	}
	my $bpp = ($bitrate)/( $width*$height*$fps != 0 ? $width*$height*$fps : 1);

	return $bpp;
}

# extract number of titles from dvd
sub examine_dvd_for_titlecount {
	my $source = shift;

	my @args = ($tools->{mplayer}, "-ao", "null", "-vo", "null");
	push(@args, "-frames", "0", "-identify");
	push(@args, "-dvd-device", $source, "dvd://");

	my ($out, $exit, $err) = run(@args);
	my $titles = $1 if ($out . $err) =~ /^ID_DVD_TITLES=([^\s]+)/ms;

	return $titles;
}

# extract information from file or dvd title
sub examine_title {
	my $file = shift;
	my $dvd_device = shift;

	my @source = ($file);
	if ($dvd_device) {
		push (@source, "-dvd-device", $dvd_device);
	}
	my @args = ($tools->{mplayer}, "-ao", "null", "-vo", "null");
	push(@args, "-frames", "0", "-identify");
	push(@args, @source);

	my ($out, $exit, $err) = run(@args);

	sub find {
		my $default = shift;
		my $s = shift;
		my $re = shift;

		my @match = map { /^${re}$/ } split('\n', $s);
		if (@match) {
			@match = sort {$b <=> $a} @match;
			return shift(@match);
		} else { return $default; }
	}

	my $s = $out . $err;
	my $data = {
		filename => $file,
		width =>    find(0,  $s, "ID_VIDEO_WIDTH=(.+)"),
		heigth =>   find(0,  $s, "ID_VIDEO_HEIGHT=(.+)"),
		fps =>      find(0,  $s, "ID_VIDEO_FPS=(.+)"),
		len =>      find(0, $s, "ID_LENGTH=(.+)"),
		abitrate => find(0,  $s, "ID_AUDIO_BITRATE=(.+)"),
		aformat =>  lc(find(0,  $s, "ID_AUDIO_CODEC=(.+)")),
		vbitrate => find(0,  $s, "ID_VIDEO_BITRATE=(.+)"),
		vformat =>  lc(find(0,  $s, "ID_VIDEO_FORMAT=(.+)")),
	};

	$data->{abitrate} = int($data->{abitrate} / 1024);	# to kbps
	$data->{vbitrate} = int($data->{vbitrate} / 1024);	# to kbps

	use Data::Dumper;
#	print Dumper($data);

	return $data;
}

# set formatting of bpp output depending on value
sub markup_bpp {
	my $bpp = shift;
	my $video_codec = shift;

	if (($video_codec =~ "(h264|avc)")) {
		if ($bpp      < $defaults->{h264_2pass_bpp}) {
			$bpp = s_err($bpp);
		} elsif ($bpp > $defaults->{h264_1pass_bpp}) {
			$bpp = s_wa($bpp);
		} else {
			$bpp = s_bb($bpp);
		}
	} elsif (($video_codec =~ "xvid")) {
		if ($bpp      < $defaults->{xvid_2pass_bpp}) {
			$bpp = s_err($bpp);
		} elsif ($bpp > $defaults->{xvid_1pass_bpp}) {
			$bpp = s_wa($bpp);
		} else {
			$bpp = s_bb($bpp);
		}
	} else {
		$bpp = s_b($bpp);
	}

	return $bpp;
}

# print one line of title display, whether header or not
sub print_title_line {
	my $is_header = shift;
	my $data = shift;

	my ($dim, $fps, $len, $bpp, $passes, $vbitrate, $vformat, $abitrate, $aformat);
	my ($filesize, $filename);

	my $wrap = \&s_id;
	if ($is_header) {
		$wrap = \&s_b;

		$dim = "dim";
		$fps = "fps";
		$len = "length";
		$bpp = "bpp";
		$passes = "p";
		$vbitrate = "vbitrate";
		$vformat = "vcodec";
		$abitrate = "abitrate";
		$aformat = "acodec";
		$filesize = "size";
		$filename = "title";
	} else {
		my $x = $data->{width}  > 0 ? $data->{width}  : "";
		my $y = $data->{heigth} > 0 ? $data->{heigth} : "";
		$dim = $x."x".$y ne "x"     ? $x."x".$y            : "";
		$fps = $data->{fps} > 0  ? $data->{fps}            : "";
		$len = $data->{len} > 0  ? int($data->{len} / 60)  : "";
		$bpp = $data->{bpp} < 1  ? substr($data->{bpp}, 1) : $data->{bpp};
		$passes =   $data->{passes}     > 0 ? $data->{passes}   : "";
		$vbitrate = $data->{vbitrate}   > 0 ? $data->{vbitrate} : "";
		$vformat =  $data->{vformat} ne "0" ? $data->{vformat}  : "";
		$abitrate = $data->{abitrate}   > 0 ? $data->{abitrate} : "";
		$aformat =  $data->{aformat} ne "0" ? $data->{aformat}  : "";
		$filesize = $data->{filesize};
		$filename = $data->{filename};
	}

	sub trunc {
		my $width = shift;
		my $s = shift;

		$s = substr($s, 0, $width);
		my $fill = $width - length($s);

		my $pad;
		for (my $i = $fill; $i > 0; $i -= 1) { $pad .= " "; }

		return $pad . $s;
	}

	$dim = trunc(9, $dim);
	$fps = trunc(6, $fps);
	$len = trunc(3, $len);
	$bpp = trunc(4, $bpp);
	$passes = trunc(1, $passes);
	$vbitrate = trunc(4, $vbitrate);
	$vformat = trunc(4, $vformat);
	$abitrate = trunc(4, $abitrate);
	$aformat = trunc(4, $aformat);
	$filesize = trunc(4, $filesize);

	$bpp = markup_bpp($bpp, $vformat) unless $is_header;

	print $wrap->("$dim  $fps  $len  $bpp $passes $vbitrate $vformat  $abitrate $aformat  $filesize  $filename\n");
}


1;