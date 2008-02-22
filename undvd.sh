#!/bin/bash
#
# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.
#
# More info: http://www.matusiak.eu/numerodix/blog/index.php/2007/01/30/undvd-dvd-ripping-made-easy/


# load constants and functions
p=$(dirname $(readlink -f $0)); . $p/lib.sh

echo -e "${h1}{( --- undvd.sh $version --- )}${r}"

usage="Usage:  ${b}undvd.sh -t ${bb}01,02,03${b} -a ${bb}en${b} -s ${bb}es${b} ${r}[${b}-d ${bb}/dev/dvd${r}] [${b}more options${r}]\n
  -t   titles to rip (comma separated)
  -a   audio language (two letter code, eg. ${bb}en${r})
  -s   subtitle language (two letter code or ${bb}off${r})\n
  -d   dvd device to rip from (default is ${bb}/dev/dvd${r})
  -q   dvd directory to rip from
  -i   dvd iso image to rip from\n
  -e   exit after this many seconds (usually for testing)\n
  -c   do sanity check (check for missing tools)
  -z   <show advanced options>"

adv_usage="Advanced usage:  ${b}undvd.sh ${r}[${b}standard options${r}] [${b}advanced options${r}]
  -o   output file size in mb (integer value)
  -1   force 1-pass encoding
  -2   force 2-pass encoding
  -u   dvd is encrypted (requires libdvdcss to read)
  -n   no disc cloning (encode straight from the dvd, save disk space)
  -r   scale video to width (integer value)
  -f   use picture smoothing filter
  -x   use xvid compression (faster, slightly lower quality)"

while getopts "t:a:s:e:d:q:i:o:r:unfx12zc" opts; do
	case $opts in
		t ) titles=$(echo $OPTARG | $sed 's|,| |g');;
		a ) alang=$OPTARG;;
		s ) slang=$OPTARG;;
		
		d ) dvd_device=$OPTARG;;
		q ) dvdisdir="y";mencoder_source="$OPTARG";;
		i ) skipclone="y";mencoder_source="$OPTARG";;
		
		e ) end=$OPTARG;;
		
		o ) output_filesize="$OPTARG";;
		1 ) passes="1";;
		2 ) twopass=y;passes="2";;
		u ) encrypted="y";;
		n ) skipclone="y";mencoder_source="$dvd_device";;
		r ) custom_scale="$OPTARG";;
		f ) prescale="spp,";postscale=",hqdn3d";;
		x ) video_codec="xvid";acodec="$lame";;
		
		c ) init_cmds "y"; exit;;
		z ) echo -e "$adv_usage"; exit;;
		* ) echo -e "$usage"; exit 1;;
	esac
done


if [ ! "$end" ]; then
	endpos=""
else
	endpos="-endpos $end"
fi


if [ ! "$titles" ]; then
	echo -e "${e}No titles to rip, exiting${r}"
	echo -e "$usage"
	exit 1
fi

if [ ! "$alang" ]; then
	echo -e "${e}No audio language selected, exiting${r}"
	echo -e "$usage"
	exit 1
fi

if [ ! "$slang" ]; then
	echo -e "${e}No subtitle language selected, exiting (use 'off' if you don't want any)${r}"
	echo -e "$usage"
	exit 1
fi


$mkdir -p logs
if [ $? != 0 ] ; then
	echo -e "${e}Could not write to $PWD, exiting${r}"
	exit 1
fi

if [ ! "$dvdisdir" ] && [ ! "$skipclone" ]; then
	echo -en " * Cloning dvd to disk first... "
	
	if [ "$encrypted" ]; then
		mencoder_source="disc"
		clone_vobcopy "$dvd_device" "$mencoder_source"
	else
		clone_dd "$dvd_device" "$disc_image"
	fi
	
	if [ $? != 0 ] ; then
		echo -e "${e}\nFailed, check log${r}"
		exit 1
	fi
	echo -e "${ok}done${r}"
fi


for title in $titles; do
	
	echo -en " * Now ripping title ${b}$title${r}, with audio ${b}$alang${r} and subtitles ${b}$slang${r}"
	if [ "$end" ]; then
		echo -e " ${r}(only first ${b}${end}${r}s)"
	else
		echo
	fi
	
	
	# Find out how much to crop, very buggy
	
	#mplayer ${title}.vob -quiet -slave -vo null -ao null -ss 30 -endpos 1 -vf cropdetect > crop.file
	#crop=$(cat crop.file | awk '/CROP/ { print $8 " " $9 }' | tail -n1 | sed 's|(\(.*\))\.|\1|g')
	#echo $crop
	
	
	# Find out how to scale the dimensions
	
	scale=$(title_scale ${title} "$mencoder_source" $tmpdir "$custom_scale")
	
	
	# User set bitrate

	if [ "$output_filesize" ]; then
		len=$(title_length ${title} "$mencoder_source" $tmpdir)
		bitrate=$(compute_bitrate $len $output_filesize)
	fi
	
	
	# Determine the number of passes
	
	if [ ! "$passes" ]; then
		if [ $bitrate -lt $standard_bitrate ]; then
			twopass=y
			passes=2
		else
			passes=1
		fi
	fi
	
	
	# Encode video
	
	pass=0
	for p in $($seq $passes); do
		pass=$(( $pass + 1 ))
	
		vcodec=$(vcodec_opts "$video_codec" "$twopass" "$pass" "$bitrate")
		
		cmd="time \
$nice -n20 \
$mencoder -v \
dvd://${title} \
-dvd-device \"$mencoder_source\" \
-alang ${alang} \
-slang ${slang} \
${crop} \
${endpos} \
-vf ${prescale}${scale}${postscale} \
-ovc ${vcodec} \
-oac ${acodec}"
		run_encode "$cmd" "$title" "$twopass" "$pass"
	done
	
	$mv ${title}.avi.partial ${title}.avi
	$rm crop.file divx2pass* 2> /dev/null

done
