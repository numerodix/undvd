# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.

package common;

use strict;
use File::Basename;

use colors;

use base 'Exporter';
our @EXPORT_OK = qw($suite $defaults $tools);
our @EXPORT = qw(
	run
	init_cmds
	print_tool_banner
	print_version
	examine_dvd_for_titlecount
	examine_title
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
		return shift(@match);
	}

	my $s = $out . $err;
	my $data = {
		source => $file,
		width =>    find(1,  $s, "ID_VIDEO_WIDTH=(.+)"),
		heigth =>   find(1,  $s, "ID_VIDEO_HEIGHT=(.+)"),
		fps =>      find(1,  $s, "ID_VIDEO_FPS=(.+)"),
		len =>      find(-1, $s, "ID_LENGTH=(.+)"),
		abitrate => find(1,  $s, "ID_AUDIO_BITRATE=(.+)"),
		aformat =>  find(0,  $s, "ID_AUDIO_CODEC=(.+)"),
		vbitrate => find(1,  $s, "ID_VIDEO_BITRATE=(.+)"),
		vformat =>  find(0,  $s, "ID_VIDEO_CODEC=(.+)"),
	};

	return $data;
}



1;
