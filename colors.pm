# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.

package colors;

use strict;


# regular colors
our $black = "\e[0;30m";
our $red = "\e[0;31m";
our $green = "\e[0;32m";
our $yellow = "\e[0;33m";
our $blue = "\e[0;34m";
our $magenta = "\e[0;35m";
our $cyan = "\e[0;36m";
our $white = "\e[0;37m";

our $reverse = "\e[7m";

if ($ENV{'TERM'} == "xterm" ) {
	$red = "\e[0;91m";
}


our $h1 = "";

our $e = $red;
our $ok = $green;
our $wa = $yellow;

our $cela = $magenta;
our $ceta = "${magenta}${reverse}";

our $b = "\e[0m\e[1m";
our $bb = $green;
our $it = $yellow;
our $it2 = $cyan;

our $in = "\e[7m";
our $r = "\e[0m";

1;
