# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.

package functions;

use strict;

use base 'Exporter';
our @EXPORT = qw(print_tool_banner run);


sub print_tool_banner {
	print "{( --- undvd 0.6.1 --- )}\n";
}

# extremely suspicious
sub run {
	my (@args) = @_;

	my ($exit, $out, $err);
#	print join(' ', @_)."\n";
	use IPC::Open3;
	my $pid = open3(\*WRITER, \*READER, \*ERROR, @args);
	wait;
	$exit = $? >> 8;

	while (my $output = <READER>) { $out .= $output; }
	while (my $output = <ERROR>) { $err .= $output; }

	chomp($out);
	chomp($err);

	return ($exit, $out, $err);
}


1;
