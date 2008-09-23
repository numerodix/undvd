# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.

package functions;

use strict;
use base 'Exporter';

our @EXPORT = qw(run r);


sub run {
	my (@args) = @_;

	my $cmd = join(' ', @args);
#	print "cmd: $cmd\n";	
	my $output = `$cmd`;
	my $exit = $?;

	chomp($output);

	return ($exit, $output);
}

sub r {
	my (@args) = @_;

	use POSIX qw(:sys_wait_h);

	pipe(READ_OUT, WRITE_OUT);
	pipe(READ_ERR, WRITE_ERR);
	if (my $pid = fork) {
		# parent
		$SIG{CHLD} = sub { 1 while (waitpid(-1, WNOHANG)) > 0 };
		close(WRITE_OUT);
		close(WRITE_ERR);
	} else {
		die "cannot fork: $!" unless defined $pid;
		# child
		open(STDOUT, ">&=WRITE_OUT") or die "Couldn't redirect STDOUT: $!";
		open(STDERR, ">&=WRITE_ERR") or die "Couldn't redirect STDERR: $!";
		close(READ_OUT);
		close(READ_ERR);
		exec(@args) or die "Couldn't run @args : $!\n";
	}

	my ($out, $err);
	while (<READ_OUT>) { $out .= $_; }
	while (<READ_ERR>) { $err .= $_; }
	close(READ_OUT);
	close(READ_ERR);

	chomp($out);
	chomp($err);

	return (0, $out, $err);
}


1;
