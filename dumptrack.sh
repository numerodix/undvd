#!/bin/bash
#
# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.


### DECLARATIONS

# version
p=$(dirname $(readlink -f $0)); . $p/version

# colors
wh="\033[1;37m"
pl="\033[m"
ye="\033[1;33m"
cy="\033[1;36m"
gr="\033[1;32m"
re="\033[1;31m"

echo -e "${wh}{( --- dumptrack.sh $version --- )}${pl}"

usage=" Usage:  ${wh}dumptrack.sh -s ${gr}<file>${wh} -t ${gr}01${wh} -o ${gr}<file>${wh}\n
\t-s \tsource file\n
\t-t \ttitle to dump\n
\t-o \toutput filename"

while getopts "s:t:o:" opts; do
        case $opts in
                s ) src=$OPTARG;;
                t ) track=$OPTARG;;
                o ) output=$OPTARG;;
                * ) echo -e $usage; exit 1;;
        esac
done


if [ "x$src" = "x" ]; then
        echo -e "${re}No source file given, exiting.${pl}"
        echo -e $usage
        exit 1
fi

if [ "x$track" = "x" ]; then
        echo -e "${re}No track given, exiting.${pl}"
        echo -e $usage
        exit 1
fi

if [ "x$output" = "x" ]; then
        echo -e "${re}No output file given, exiting.${pl}"
        echo -e $usage
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
( echo "$cmd"; sh -c "$cmd" ) &> logs/dump${title}.log
if [ $? != 0 ] ; then
	echo -e "${re}\nFailed, check log:${pl} logs/dump${title}.log"
	exit 1
fi
echo -e "${gr}done${pl}"

