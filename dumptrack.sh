#!/bin/bash
#
# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.


# load constants and functions
p=$(dirname $(readlink -f $0)); . $p/lib.sh

echo -e "${h1}{( --- dumptrack.sh $version --- )}${r}"

usage="Usage:  ${b}dumptrack.sh -s ${bb}<file>${b} -t ${bb}01${b} -o ${bb}<file>${r}
  -s   source file
  -t   title to dump
  -o   output filename"

while getopts "s:t:o:" opts; do
	case $opts in
		s ) src=$OPTARG;;
		t ) track=$OPTARG;;
		o ) output=$OPTARG;;
		* ) echo -e "$usage"; exit 1;;
	esac
done


if [ "x$src" = "x" ]; then
	echo -e "${e}No source file given, exiting.${r}"
	echo -e "$usage"
	exit 1
fi

if [ "x$track" = "x" ]; then
	echo -e "${e}No track given, exiting.${r}"
	echo -e "$usage"
	exit 1
fi

if [ "x$output" = "x" ]; then
	echo -e "${e}No output file given, exiting.${r}"
	echo -e "$usage"
	exit 1
fi

mkdir -p logs

# --audio-desync=500
cmd="vlc -I dummy \"$src@$track\" \
:sout='#transcode{vcodec=mp1v,vb=4096,acodec=mp3,ab=128,scale=1,channels=2,\
deinterlace,audio-sync}:std{access=file, mux=ps,url=\"$output\"}' vlc:quit"

#echo $cmd
#exit 1
echo -en " * Dumping track with vlc... "
( echo "$cmd"; bash -c "$cmd" ) &> logs/dump${title}.log
if [ $? != 0 ] ; then
	echo -e "${e}\nFailed, check log:${r} logs/dump${title}.log"
	exit 1
fi
echo -e "${ok}done${r}"

