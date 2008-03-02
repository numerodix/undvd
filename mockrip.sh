#!/bin/bash
#
# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.


# load constants and functions
p=$(dirname $(readlink -f $0)); . $p/lib.sh

#display_title "X" "Y" "fps" "len" "bpp" "bitr" "fmt" "size" "name"
for file in "$@"; do
	filename=$(basename "$file")
	filesize=$(stat "$file" | $grep "Size:" | $sed "s|.*Size: \([0-9]*\).*|\1|g")
	info=($(examine_title "$file"))
	width=${info[0]}
	height=${info[1]}
	fps=${info[2]}
	length=${info[3]}
	bitrate=${info[4]}
	format=${info[5]}
	bpp=$( echo "scale=3; ($bitrate)/($width*$height*$fps)" | $bc )
	display_title $width $height $fps $length $bpp $bitrate $format $filesize "$filename"
done
exit

echo -e "\n1148mb   902.5 kbps"
echo "$(compute_bitrate "480" "384" "25.000" "148" "-1" "1148")"
echo "$(compute_bitrate "480" "384" "25.000" "148" "0.125")"
echo "$(compute_bitrate "480" "384" "25.000" "148" "0.200")"

echo -e "\n171mb   888.8 kbps"
echo "$(compute_bitrate "480" "384" "25.000" "22" "-1" "171")"
echo "$(compute_bitrate "480" "384" "25.000" "22" "0.200")"
echo "$(compute_bitrate "480" "384" "25.000" "22" "0.125")"

echo -e "\n144mb   726.4 kbps"
echo "$(compute_bitrate "480" "320" "29.970" "23" "-1" "144")"
echo "$(compute_bitrate "480" "320" "29.970" "23" "0.200")"
echo "$(compute_bitrate "480" "320" "29.970" "23" "0.125")"
