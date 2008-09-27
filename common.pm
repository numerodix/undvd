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
	trunc
	p
	deep_copy
	init_logdir
	run
	init_cmds
	print_tool_banner
	print_version
	compute_bpp
	set_bpp
	compute_vbitrate
	examine_dvd_for_titlecount
	examine_title
	get_crop_eta
	crop_title
	print_title_line
	scale_title
	compute_media_size
	set_container_opts
	set_acodec_opts
	set_vcodec_opts
	run_encode
	remux_container
	);


### DECLARATIONS

# autoflush write buffer globally
$| = 1;

our $suite = {
	name => "undvd",
	version => "0.6.1",
	tool_name => basename(grep(-l, $0) ? readlink $0 : $0),
};

our $defaults = {
	logdir => "logs",

	timer_refresh => 1,

	dvd_device => "/dev/dvd",
	disc_image => "disc.iso",
	mencoder_source => "disc.iso",

	framesize_baseline => 720*576*(2/3)^2,	# frame size in pixels

	h264_1pass_bpp => .195,
	h264_2pass_bpp => .150,

	xvid_1pass_bpp => .250,
	xvid_2pass_bpp => .200,

	container => "avi",

	prescale => "",
	postscale => ",harddup",
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

# truncate text
sub trunc {
	my ($width, $side, $s, $fill) = @_;

	my $trunc_len = length($s) - $width;
	$s = substr($s, 0, $width);

	substr($s, length($s) - length($fill), length($fill), $fill)
		if (($trunc_len > 0) and $fill);

	my $pad_len = abs($width - length($s));
	my $pad = " " x $pad_len;

	$s = $pad . $s if $side == -1;
	$s = $s . $pad if $side == 1;

	return $s;
}

# print object
sub p {
	my @these = @_;
	foreach my $this (@these) {
		if (ref $this eq "ARRAY") {
			print "\ndump:  ".join(" , ", @$this)."\n";
		} else {
			use Data::Dumper;
			print "\n".Dumper($this);
		}
	}
}

# deep copy objects
sub deep_copy {
	my $this = shift;
	if (not ref $this) {
		$this;
	} elsif (ref $this eq "ARRAY") {
		[map deep_copy($_), @$this];
	} elsif (ref $this eq "HASH") {
		+{map { $_ => deep_copy($this->{$_}) } keys %$this};
	} else { die "what type is $_?" }
}


# create directory for logging
sub init_logdir {
	if (! -e $defaults->{logdir} and ! mkdir($defaults->{logdir})) {
		fatal("Could not write to %%%$ENV{PWD}%%%, exiting");
	} elsif (-e $defaults->{logdir} and ! -w $defaults->{logdir}) {
		fatal("Logging directory %%%".$defaults->{logdir}."%%% is not writable");
	}
}

# replace gnu which
sub which {
	my ($bin) = @_;

	foreach my $dir (split(":", $ENV{PATH})) {
		return ("$dir/$bin", 0) if (-x "$dir/$bin");
	}
	return ($bin, 1);
}

# launch command waiting for output and exit
sub run {
	my ($args, $nowait) = @_;

	print STDERR join(' ', @$args)."\n" if $ENV{"DEBUG"};

	# spawn process
	use IPC::Open3;
	my($writer, $reader, $error);
	my $pid = open3($writer, $reader, $error, @$args);

	if ($nowait) {
		return ($pid, $reader, $error);
	}

	# read from pipes as output comes
	my ($out, $exit, $err);
	while ((my $stdout = <$reader>) or (my $stderr = <$error>)) {
		$out .= $stdout;
		$err .= $stderr;
	}

	# wait for pid and capture exit value
	wait;
	$exit = $? >> 8;

	chomp($out);
	chomp($err);

	return ($out, $exit, $err);
}

# aggregate invocation results
sub run_agg {
	my ($invokes, $fh_logfile) = @_;

	my $exit;
	foreach my $args (@$invokes) {
		my ($o, $x, $e) = run($args);
		$exit += $x;
		print $fh_logfile join(" ", @$args)."\n";
		print $fh_logfile $o.$e."\n";
	}

	return $exit;
}

# check for missing dependencies
sub init_cmds {
	my $verbose = shift;

	print " * Checking for tool support...\n" if $verbose;
	foreach my $tool (@videoutils, @shellutils, @coreutils, @extravideoutils) {
		my ($tool_path, $exit) = which($tool);
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
		my ($out, $exit, $err) = run(\@args);
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

		my ($tool_path, $exit) = which($tool);
		if ($exit) {
			print "  [" . s_err("!") . "] $tool missing\n";
		} else {
			unshift(@args, $tool_path);
			my ($out, $exit, $err) = run(\@args);
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

# set bpp based on the codec and number of passes
sub set_bpp {
	my ($video_codec, $passes) = @_;

	my $bpp;
	if ($video_codec eq "h264") {
		$bpp = $defaults->{h264_1pass_bpp} if $passes == 1;
		$bpp = $defaults->{h264_2pass_bpp} if $passes > 1;
	} else {
		$bpp = $defaults->{xvid_1pass_bpp} if $passes == 1;
		$bpp = $defaults->{xvid_2pass_bpp} if $passes > 1;
	}

	return $bpp;
}

# set the number of passes based on codec and bpp
sub set_passes {
	my ($video_codec, $bpp) = @_;

	my $passes = 1;
	if ($video_codec eq "h264") {
		$passes = 2 if $bpp < $defaults->{h264_1pass_bpp};
	} else {
		$passes = 2 if $bpp < $defaults->{xvid_1pass_bpp};
	}

	return $passes;
}

# compute video bitrate based on title length
sub compute_vbitrate {
	my ($width, $height, $fps, $bpp) = @_;

	my $bitrate = int( ($width * $height * $fps * $bpp) / 1024);

	return $bitrate;
}

# extract number of titles from dvd
sub examine_dvd_for_titlecount {
	my $source = shift;

	my @args = ($tools->{mplayer}, "-ao", "null", "-vo", "null");
	push(@args, "-frames", "0", "-identify");
	push(@args, "-dvd-device", $source, "dvd://");

	my ($out, $exit, $err) = run(\@args);
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

	my ($out, $exit, $err) = run(\@args);

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
		filename =>    $file,
		width =>       find(0, $s, "ID_VIDEO_WIDTH=(.+)"),
		height =>      find(0, $s, "ID_VIDEO_HEIGHT=(.+)"),
		fps =>         find(0, $s, "ID_VIDEO_FPS=(.+)"),
		length =>      find(0, $s, "ID_LENGTH=(.+)"),
		abitrate =>    find(0, $s, "ID_AUDIO_BITRATE=(.+)"),
		aformat =>  lc(find(0, $s, "ID_AUDIO_CODEC=(.+)")),
		vbitrate =>    find(0, $s, "ID_VIDEO_BITRATE=(.+)"),
		vformat =>  lc(find(0, $s, "ID_VIDEO_FORMAT=(.+)")),
	};

	$data->{abitrate} = int($data->{abitrate} / 1024);	# to kbps
	$data->{vbitrate} = int($data->{vbitrate} / 1024);	# to kbps
	$data->{bpp} = compute_bpp($data->{width}, $data->{height}, $data->{fps},
		$data->{len}, 0, $data->{vbitrate});

	if ($dvd_device) {
		$data->{filesize} = int(
			($data->{abitrate} + $data->{vbitrate}) * $data->{length} / 8 / 1024);
	} else {
		$data->{filesize} = int( (stat($file))[7] / 1024 / 1024 );
	}

	return $data;
}

# estimate cropdetect duration
sub get_crop_eta {
	my ($length, $fps) = @_;

	return int($length * $fps / 250 / 60);
}

# figure out how much to crop
sub crop_title {
	my ($file, $dvd_device) = @_;

	my @source = ($file);
	if ($dvd_device) {
		push (@source, "-dvd-device", $dvd_device);
	}
	my @args = ($tools->{mplayer}, "-quiet", "-ao", "null", "-vo", "null");
	push(@args, "-fps", "10000", "-vf", "cropdetect");
	push(@args, @source);

	my ($out, $exit, $err) = run(\@args);

	my @cropdata = map { /^(\[CROP\].*)$/ } split("\n", $out . $err);
	my $cropline = pop(@cropdata);

	my ($w, $h, $x, $y) =
		map { /-vf crop=([0-9]+):([0-9]+):([0-9]+):([0-9]+)/ } $cropline;

	my $cropfilter = "crop=$w:$h:$x:$y,";

	return ($w, $h, $cropfilter);
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

	my ($dim, $fps, $length, $bpp, $passes, $vbitrate, $vformat, $abitrate, $aformat);
	my ($filesize, $filename);

	if ($is_header) {
		$dim = "dim";
		$fps = "fps";
		$length = "length";
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
		my $y = $data->{height} > 0 ? $data->{height} : "";
		$dim =    $x."x".$y ne "x"     ? $x."x".$y                 : "";
		$fps =    $data->{fps}    > 0  ? $data->{fps}              : "";
		$length = $data->{length} > 0  ? int($data->{length} / 60) : "";
		$bpp =    $data->{bpp}    > 0  ? $data->{bpp}              : "";
		$passes =   $data->{passes}     > 0 ? $data->{passes}   : "";
		$vbitrate = $data->{vbitrate}   > 0 ? $data->{vbitrate} : "";
		$vformat =  $data->{vformat} ne "0" ? $data->{vformat}  : "";
		$abitrate = $data->{abitrate}   > 0 ? $data->{abitrate} : "";
		$aformat =  $data->{aformat} ne "0" ? $data->{aformat}  : "";
		$filesize = $data->{filesize};
		$filename = $data->{filename};
	}

	$dim =      trunc(9, -1, $dim);
	$fps =      trunc(6, -1, $fps);
	$length =   trunc(3, -1, $length);
	$bpp =      trunc(5,  1, $bpp);
	$passes =   trunc(1, -1, $passes);
	$vbitrate = trunc(4, -1, $vbitrate);
	$vformat =  trunc(4, -1, $vformat);
	$abitrate = trunc(4, -1, $abitrate);
	$aformat =  trunc(4, -1, $aformat);
	$filesize = trunc(4, -1, $filesize);

	if ($filename =~ /dvd:\/\//) {
		$filesize = s_est($filesize);
	}

	$bpp = markup_bpp($bpp, $vformat) unless $is_header;

	my $line = "$dim  $fps  $length  $bpp $passes $vbitrate $vformat  "
		. "$abitrate $aformat  $filesize  $filename";
	$line = s_b($line) if $is_header;
	print "$line\n";
}

# compute title scaling
sub scale_title {
	my ($width, $height, $custom_scale) = @_;

	my ($nwidth, $nheight) = ($width, $height);

	if ($custom_scale ne "off") {	# scaling isn't disabled

		# scale to the width given by user (upscaling permitted)
		if ($custom_scale) {
			undef $nwidth;
			undef $nheight;

			if ($custom_scale =~ /^([0-9]+)$/) {
				$nwidth = $1;
			} elsif ($custom_scale =~ /^([0-9]*):([0-9]*)$/) {
				($nwidth, $nheight) = ($1, $2);
			} else {
				fatal("Failed to read a pair of positive integers from scaling "
					. "%%%$custom_scale%%%");
			}

			if (       $nwidth > 0 and ! $nheight > 0) {
				$nheight = int($height * $nwidth  / ($width  > 0 ? $width  : 1) );
			} elsif (! $nwidth > 0 and   $nheight > 0) {
				$nwidth =  int($width  * $nheight / ($height > 0 ? $height : 1) );
			}

		# apply default scaling heuristic
		} else {
			# compute scaling factor based on baseline value
			my $framesize = $width*$height > 0 ? $width*$height : 1;
			my $factor = sqrt($defaults->{framesize_baseline}/$framesize);

			# scale by factor, do not upscale
			if ($factor < 1) {
				$nwidth = int($width*$factor);
				$nheight = int($height*$factor);
			}
		}

		# dimensions have been changed, make sure they are multiples of 16
		($nwidth, $nheight) = scale_by_x($width, $height, $nwidth, $nheight);

		# make sure the new dimensions are sane
		if ($nwidth * $nheight <= 0) {
			($nwidth, $nheight) = ($width, $height);
		}
	}

	return ($nwidth, $nheight);
}

# scale dimensions to nearest (lower/upper) multiple of 16
sub scale_by_x {
	my ($orig_width, $orig_height, $width, $height) = @_;
	my $divisor = 16;

	# if the original dimensions are not multiples of 16, no amount of scaling
	# will bring us to an aspect ratio where the smaller dimensions are
	if (($orig_width % $divisor) + ($orig_height % $divisor) != 0) {
		$width = $orig_width;
		$height = $orig_height;
	} else {
		my $step = -1;
		my $completed;
		while (! $completed) {
			$step++;

			my $up_step = $width + ($step * $divisor);
			my $down_step = $width - ($step * $divisor);
			foreach my $x_step ($up_step, $down_step) {
				my $x_width = int($x_step - ($x_step % $divisor));
				my $x_height = int($x_width *
					($orig_height/ ($orig_width > 0 ? $orig_width : 1) ));
				if (($x_width % $divisor) + ($x_height % $divisor) == 0) {
					$completed = 1;
					$width = $x_width;
					$height = $x_height;
				}
			}
		}
	}

	return ($width, $height);
}

# compute size of media given length and bitrate
sub compute_media_size {
	my ($length, $bitrate) = @_;
	return ($bitrate / 8) * ($length / 1024);
}

# get container options and decide on codecs
sub set_container_opts {
	my ($acodec, $vcodec, $container) = @_;

	my $audio_codec = "mp3";
	my $video_codec = "h264";
	my $ext = "avi";
	my @opts = ("avi");

	if ($container =~ /(avi|mkv|ogm)/) {
	} elsif ($container eq "mp4") {
		$audio_codec = "aac";
		$video_codec = "h264";
	} else {

		# use lavf muxing
		if ($container =~ "(asf|au|dv|flv|ipod|mov|mpg|nut|rm|swf)") {
			$ext = $container;
			@opts = ("lavf", "-lavfopts", "format=$container");

			if ($container eq "flv") {
				$audio_codec = "mp3";
				$video_codec = "flv";
			}
		} else {
			fatal("Unrecognized container %%%$container%%%");
		}
	}

	$audio_codec = $acodec if $acodec;
	$video_codec = $vcodec if $vcodec;

	return ($audio_codec, $video_codec, $ext, @opts);
}

# get audio codec options
sub set_acodec_opts {
	my ($container, $codec, $orig_bitrate, $get_bitrate) = @_;

	my @opts;
	if ($container eq "flv"){
		push(@opts, "-srate", "44100");		# flv supports 44100, 22050, 11025
	}

	my $bitrate;
	if ($codec eq "copy") {
		$bitrate = $orig_bitrate;
		push(@opts, "copy");
	} elsif ($codec eq "mp3") {
		$bitrate = 160;
		push(@opts, "mp3lame", "-lameopts", "vbr=3:abr=$bitrate:q=3");
	} elsif ($codec eq "aac") {
		$bitrate = 192;
		push(@opts, "faac", "-faacopts", "br=$bitrate:mpeg=4:object=2",
			"-channels", "2");

	# use lavc codec
	} else {
		$bitrate = 224;		# mencoder manpage default
		my $cs = "ac3|flac|g726|libamr_nb|libamr_wb|mp2|roq_dpcm|sonic|sonicls|"
			. "vorbis|wmav1|wmav2";
		if ($codec =~ /($cs)/) {
			push(@opts, "lavc", "-lavcopts",
				"abitrate=$bitrate:acodec=$codec");
		} else {
			fatal("Unrecognized audio codec %%%$codec%%%");
		}
	}

	if ($get_bitrate) {
		return $bitrate;
	} else {
		return @opts;
	}
}

# get video codec options
sub set_vcodec_opts {
	my ($codec, $passes, $pass, $bitrate) = @_;

	my @opts;
	if ($codec eq "copy") {
		push(@opts, "copy");

	} elsif ($codec eq "h264") {
		my $local_opt = "subq=5:frameref=2";
		if ($passes > 1) {
			if ($pass < $passes) {
				$local_opt = "pass=$pass:subq=1:frameref=1";
			} else {
				$local_opt = "pass=$pass:$local_opt";
			}
		}
		push(@opts, "x264", "-x264encopts",
			"$local_opt:partitions=all:weight_b:bitrate=$bitrate:threads=auto");

	} elsif ($codec eq "xvid") {
		my $local_opt;
		if ($passes > 1) {
			if ($pass < $passes) {
				$local_opt = "pass=$pass:";
			} else {
				$local_opt = "pass=$pass:";
			}
		}
		push(@opts, "xvid", "-xvidencopts",
			"${local_opt}bitrate=$bitrate");

	# use lavc codec
	} else {
		my $local_opt;
		if ($passes > 1) {
			if ($pass < $passes) {
				$local_opt = "vpass=$pass:";
			} else {
				$local_opt = "vpass=$pass:";
			}
		}

		my $cs = "asv1|asv2|dvvideo|ffv1|flv|h261|h263|h263p|huffyuv|libtheora|"
			. "ljpeg|mjpeg|mpeg1video|mpeg2video|mpeg4|msmpeg4|msmpeg4v2|"
			. "roqvideo|rv10|snow|svq1|wmv1|wmv2";
		if ($cs =~ /($cs)/) {
			push(@opts, "lavc", "-lavcopts",
				"${local_opt}vbitrate=$bitrate:vcodec=$codec");

		} else {
			fatal("Unrecognized video codec %%%$codec%%%");
		}
	}

	return @opts;
}

# run encode and print updates
sub run_encode {
	my ($args, $file, $title_name, $ext, $length, $passes, $pass) = @_;

	# Set output and logging depending on number of passes

	my $output_file = "$title_name.$ext.partial";
	my $base = basename($title_name);
	my $logfile = $defaults->{logdir}."/$base.log";

	if ($passes > 1) {
		$logfile = "$logfile.pass$pass";
		if ($pass < $passes) {
			$output_file = "/dev/null";
		}
	} else {
		$pass = "-";
	}

	unshift(@$args, "time", "nice", "-n20", $tools->{mencoder}, "-v");
	push(@$args, "-o", $output_file, $file);

	# Print initial status message

	my $status = trunc(19, 1, "[$pass] Encoding");
	print "$status\r";

	# Execute encoder in the background

	my $fh_logfile;
	open($fh_logfile, ">", $logfile);
	print $fh_logfile join(" ", @$args)."\n";
	my ($pid, $reader, $error) = run(\@$args, 1);

	# Write mencoder's ETA estimate

	my $line = trunc(59, 1, $status);
	my $start_time = time();
	my ($exit, $perc, $secs, $fps, $size, $ela, $eta);

	use POSIX ":sys_wait_h";
	while ((my $kid = waitpid($pid, WNOHANG)) != -1) {
		sysread($reader, my $s, 1024*1024);
		$exit = $? >> 8;
		print $fh_logfile $s;

		if (int(time()) % $defaults->{timer_refresh} == 0) {
			$perc = s_it2( trunc(4, -1, $1) )    if ($s =~ /\(([0-9 ]{2}%)\)/);
			$secs =        trunc(6, -1, "$1s")   if ($s =~ /Pos:[ ]*([0-9]+)\.[0-9]*s/);
			$fps  =  s_it( trunc(7, -1, $1) )    if ($s =~ /([0-9]+fps)/);
			$size =        trunc(6, -1, $1)      if ($s =~ /([0-9]+mb)/);
			$ela  = s_ela( "+".int((time() - $start_time) / 60 )."min" ) if $perc;
			$eta  = s_eta(              "-$1" )  if ($s =~ /Trem:[ ]*([0-9]+min)/);
			$line = "$status   $perc   $secs   $fps   $size     " if $perc;
			print "${line}$ela  $eta    \r";
			sleep 1
		}
	}

	# Flush pipe and close logfile

	while (<$reader>) { print $fh_logfile $_; }
	close($fh_logfile);

	# Report exit code

	if ($exit == 0) {
		print $line . "[ " . s_ok("done")    . trunc(14, 1, " ]") . "\n";
	} else {
		print $line . "[ " . s_err("failed") . trunc(12, 1, " ] check log") . "\n";
	}
}

# run remux and print updates
sub remux_container {
	my ($root, $ext, $fps, $container, $acodec, $vcodec) = @_;

	if ($container =~ /(mp4|mkv|ogm)/) {

		# Set logging

		my $base = basename($root);
		my $logfile = $defaults->{logdir} . "/$base.remuxlog";

		my $fh_logfile;
		open($fh_logfile, ">", $logfile);

		sub pre {
			if (-f "$root.$container") {
				unlink("$root.$container");
			}
			my @args1 = ($tools->{mplayer}, "$root.$ext",
				"-dumpaudio", "-dumpfile", "$root.$acodec");
			my @args2 = ($tools->{mplayer}, "$root.$ext",
				"-dumpvideo", "-dumpfile", "$root.$vcodec");
			return (\@args1, \@args2);
		}

		sub post {
			unlink "$root.$acodec";
			unlink "$root.$vcodec";
			unlink "$root.$ext";
		}

		my $remux;

		if ($container eq "mp4") {
			$remux = sub {
				my @args1 = ($tools->{mp4creator}, "-create", "$root.$acodec",
					"$root.$container");
				my @args2 = ($tools->{mp4creator}, "-create", "$root.$vcodec",
					"-rate=$fps", "$root.$container");
				my @args3 = ($tools->{mp4creator}, "-hint=1", "$root.$container");
				my @args4 = ($tools->{mp4creator}, "-hint=2", "$root.$container");
				my @args5 = ($tools->{mp4creator}, "-optimize", "$root.$container");

				my @a = (pre, \@args1, \@args2, \@args3, \@args4, \@args5);
				my ($out, $exit, $err) = run_agg(\@a, $fh_logfile);
				post();
				return ($out, $exit, $err);
			};
		} elsif ($container eq "mkv") {
			$remux = sub {
				my @args = ($tools->{mkvmerge}, "-o", "$root.$container",
					"$root.$ext");

				my @a = (\@args);
				my ($out, $exit, $err) = run_agg(\@a, $fh_logfile);
				unlink("$root.$ext");
				return ($out, $exit, $err);
			};
		} elsif ($container eq "ogm") {
			$remux = sub {
				my @args = ($tools->{ogmmerge}, "-o", "$root.$container",
					"$root.$ext");

				my @a = (\@args);
				my ($out, $exit, $err) = run_agg(\@a, $fh_logfile);
				unlink("$root.$ext");
				return ($out, $exit, $err);
			};
		}

		# Print initial status message

		my $status = trunc(59, 1, "[.] Remuxing");
		print "$status\r";

		# Execute remux in the background

		my $exit = &$remux();

		# Report exit code

		close($fh_logfile);

		if ($exit == 0) {
			print "${status}[ " . s_ok("done")    . trunc(15, 1, " ]") . "\n";
		} else {
			print "${status}[ " . s_err("failed") . " ] check log" . "\n";
		}
	}
}


1;
