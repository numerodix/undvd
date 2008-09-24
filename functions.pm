# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.

package functions;

use strict;
use File::Basename;

use colors;

use base 'Exporter';
our @EXPORT = qw(print_tool_banner run print_version);
our @EXPORT_OK = qw($suite $tools);


### DECLARATIONS

our $suite = {
	name => "undvd",
	version => "0.6.1",
	tool_name => basename($0),
};

my @videoutils = qw(lsdvd mencoder mplayer);
my @shellutils = qw(awk bash bc grep egrep getopt mount ps sed xargs);
my @coreutils = qw(cat date dd dirname head mkdir mv nice readlink rm seq sleep sort tail tr true);
my @extravideoutils = qw(mp4creator mkvmerge ogmmerge vobcopy);

our $tools = {};
foreach (@videoutils, @shellutils, @coreutils, @extravideoutils) {
	my ($out, $exit, $err) = run("which", $_);
	if (! $exit) { $tools->{$_} = $out; }
}


### FUNCTIONS

sub print_tool_banner {
	print "{( --- " . $suite->{tool_name} . " " . $suite->{version} . " --- )}\n";
}

# extremely suspicious
sub run {
	my (@args) = @_;

	my ($out, $exit, $err);
#	print join(' ', @_)."\n";
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


1;
