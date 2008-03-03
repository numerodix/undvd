#!/bin/bash
#
# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.


# load constants and functions
p=$(dirname $(readlink -f $0)); . $p/lib.sh

display_tool_banner

display_title_line "header"
for file in "$@"; do
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

	passes="?"

	display_title "$width" "$height" "$fps" "$length" "$bpp" "$bitrate" "$passes" "$format" "$filesize" "$filename"
done
