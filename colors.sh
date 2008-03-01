# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.

# regular colors
black="\e[0;30m"    # black
red="\e[0;31m"    # red
green="\e[0;32m"    # green
yellow="\e[0;33m"    # yellow
blue="\e[0;34m"    # blue
magenta="\e[0;35m"    # magenta
cyan="\e[0;36m"    # cyan
white="\e[0;37m"    # white

reverse="\e[7m"

if [ "$TERM" = "xterm" ]; then
	red="\e[0;91m"    # red
fi


h1=

e=$red
ok=$green
wa=$yellow

cela=$magenta
ceta="${magenta}${reverse}"

b="\e[0m\e[1m"
bb=$green

in="\e[7m"
r="\e[0m"
