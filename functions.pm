# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.

package functions;

use strict;
use base 'Exporter';

our @EXPORT = qw(run);


# extremely suspicious
sub run {
	my (@args) = @_;

	my ($exit, $out, $err);

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
