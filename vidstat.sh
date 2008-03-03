#!/bin/bash
#
# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.


# load constants and functions
p=$(dirname $(readlink -f $0)); . $p/lib.sh

display_tool_banner

usage="Usage:  ${b}vidstat.sh ${r}[${bb}<file>${r} | ${b}-d ${bb}/dev/dvd${r} | ${b}-q ${bb}/path${r} | ${b}-i ${bb}disc.iso${r}]
  <fs> files to read
  -d   dvd device to read from (default is ${bb}/dev/dvd${r})
  -q   dvd directory to read from
  -i   dvd iso image to read from"

while getopts "d:q:i:" opts; do
	case $opts in
		d ) input_dvd_device=$OPTARG;;
		q ) input_dvd_device=$OPTARG;dvdisdir="-q ";;
		i ) input_dvd_device=$OPTARG;dvdisdir="-q ";;
		* ) echo -e "$usage"; exit 1;;
	esac
done

if [[ ! "$@" ]]; then
	echo -e "$usage"
	exit 1
fi

if [ "$input_dvd_device" ]; then
	echo $dvd_device
fi

display_title_line "header"
for file in "$@"; do
	if [ ! -e "$file" ]; then 
		echo -e "${e}File $file does not exist"
		exit 1
	fi

	filename=$(basename "$file")

	filesize=$(stat "$file" | $grep "Size:" | $sed "s|.*Size: \([0-9]*\).*|\1|g")
	filesize=$( echo "scale=0; $filesize/1024/1024" | $bc )  # convert to mb

	info=($(examine_title "$file"))
	
	width=${info[0]}

	height=${info[1]}
	
	fps=${info[2]}
	
	length=${info[3]}
	
	bitrate=$( echo "scale=0; ${info[4]}/1024" | $bc )  # convert to kbps
	if [ "$bitrate" ]; then
		bpp=$(compute_bpp "$width" "$height" "$fps" "$length" "" "$bitrate")
	fi

	format=${info[5]}
	[ "$format" = "0" ] && format="???"

	passes="?"

	display_title "$width" "$height" "$fps" "$length" "$bpp" "$bitrate" "$passes" "$format" "$filesize" "$filename"
done
