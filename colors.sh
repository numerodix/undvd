# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.

# regular colors
black="\e[0;30m"
red="\e[0;31m"
green="\e[0;32m"
yellow="\e[0;33m"
blue="\e[0;34m"
magenta="\e[0;35m"
cyan="\e[0;36m"
white="\e[0;37m"

reverse="\e[7m"

if [[ "$TERM" = "xterm" ]]; then
	red="\e[0;91m"
fi


h1=

e=$red
ok=$green
wa=$yellow

cela=$magenta
ceta="${magenta}${reverse}"

b="\e[0m\e[1m"
bb=$green
it=$yellow

in="\e[7m"
r="\e[0m"
