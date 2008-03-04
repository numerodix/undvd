#!/bin/bash
#
# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.


# load constants and functions
p=$(dirname $(readlink -f $0)); . $p/lib.sh

display_tool_banner

usage="Usage:  ${b}vidstat.sh ${r}[${bb}<file(s)>${r} | ${b}-d ${bb}/dev/dvd${r} | ${b}-q ${bb}/path${r} | ${b}-i ${bb}disc.iso${r}]
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


# Build array either of dvd titles or files given as input

files=() ; i=0
if [ "$input_dvd_device" ]; then
	cmd="mplayer -ao null -vo null -frames 0 -identify -dvd-device \"$input_dvd_device\" dvd:// 2>&1"
	mplayer_output=$($bash -c "$cmd")
	titles=$( echo "$mplayer_output" | $grep "ID_DVD_TITLES" | $sed "s|ID_DVD_TITLES=\(.*\)|\1|g" )
	if [ "$titles" ]; then
		for f in $($seq 1 $titles); do
			files[$i]="$f"
			i=$(( $i+1 ))
		done
	else
		echo -e "${e}Could not read from $input_dvd_device${r}"
		exit 1
	fi
else
	for f in "$@"; do
		files[$i]="$f"
		i=$(( $i+1 ))
	done
fi


display_title_line "header"
for file in "${files[@]}"; do
	if [ ! "$input_dvd_device" -a ! -e "$file" ]; then 
		echo -e "${e}File $file does not exist"
		exit 1
	fi

	if [ "$input_dvd_device" ]; then
		filename="$file"
		filesize="0"
		info=($(examine_title "" "$input_dvd_device" "$file"))
	else
		filename=$(basename "$file")

		filesize=$(stat "$file" | $grep "Size:" | $sed "s|.*Size: \([0-9]*\).*|\1|g")
		filesize=$( echo "scale=0; $filesize/1024/1024" | $bc )  # convert to mb

		info=($(examine_title "$file"))
	fi
	
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
