#!/bin/bash
#
# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.
#
# More info: http://www.matusiak.eu/numerodix/blog/index.php/2007/01/30/undvd-dvd-ripping-made-easy/


# load constants and functions
p=$(dirname $(readlink -f $0)); . $p/lib.sh

echo -e "${wh}{( --- undvd.sh $version --- )}${pl}"

usage=" Usage:  ${wh}undvd.sh -t ${gr}01,02,03${wh} -a ${gr}en${wh} -s ${gr}es${wh} [-e ${gr}200${wh}] [-d ${gr}/dev/dvd${wh}] [more options]${pl}\n
\t-t \ttitles to rip (comma separated)\n
\t-a \taudio language (two letter code, eg. 'en')\n
\t-s \tsubtitle language (two letter code or 'off')\n
\t-e \texit after this many seconds (usually for testing)\n
\t-d \tdvd device to rip from (default is /dev/dvd)\n
\t-q \tdvd directory to rip from\n
\t-i \tdvd iso image to rip from\n
\t-z \t<show advanced options>"

adv_usage=" Advanced usage:  ${wh}undvd.sh [standard options] ${gr}[advanced
options]${pl}\n
\t-o \toutput file size in mb (integer value)\n
\t-1 \tforce 1-pass encoding\n
\t-2 \tforce 2-pass encoding\n
\t-f \tuse picture smoothing filter\n
\t-x \tuse xvid compression (faster, slightly lower quality)"

while getopts "t:a:s:e:d:q:i:o:fxz12" opts; do
	case $opts in
		t ) titles=$(echo $OPTARG | sed 's|,| |g');;
		a ) alang=$OPTARG;;
		s ) slang=$OPTARG;;
		e ) end=$OPTARG;;
		d ) dvd_device=$OPTARG;;
		q ) dvdisdir="y";mencoder_source="$OPTARG";;
		i ) skipclone="y";mencoder_source="$OPTARG";;
		f ) prescale="spp,";postscale=",hqdn3d";;
		x ) video_codec="xvid";acodec="$lame";;
		o ) output_filesize="$OPTARG";;
		1 ) passes="1";;
		2 ) twopass=y;passes="2";;
		z ) echo -e $adv_usage; exit 1;;
		* ) echo -e $usage; exit 1;;
	esac
done


if [ "x$end" = "x" ]; then
	endpos=""
else
	endpos="-endpos $end"
fi


if [ "x$titles" = "x" ]; then
	echo -e "${re}No titles to rip, exiting${pl}"
	echo -e $usage
	exit 1
fi

if [ "x$alang" = "x" ]; then
	echo -e "${re}No audio language selected, exiting${pl}"
	echo -e $usage
	exit 1
fi

if [ "x$slang" = "x" ]; then
	echo -e "${re}No subtitle language selected, exiting (use 'off' if you dont want any)${pl}"
	echo -e $usage
	exit 1
fi


mkdir -p logs
if [ $? != 0 ] ; then
	echo -e "${re}Could not write to $PWD, exiting${pl}"
	exit 1
fi

if [ ! $dvdisdir ] && [ ! $skipclone ]; then
	echo -en " * Copying dvd to disk first... "
	cmd="time \
	nice -n20 \
	dd if=${dvd_device} of=$disc_image.partial && \
	mv $disc_image.partial $disc_image"
	( echo "$cmd"; bash -c "$cmd" ) &> logs/iso.log
	if [ $? != 0 ] ; then
		echo -e "${re}\nFailed, dumping log:${pl}"
		cat logs/iso.log
		exit 1
	fi
	echo -e "${gr}done${pl}"
fi


for i in $titles; do
	title=$i
	
	echo -en " * Now ripping title ${wh}$title${pl}, with audio: ${wh}$alang${pl} and subtitles: ${wh}$slang${pl}"
	if [ "x$end" != "x" ]; then
		echo -e " ${pl}(only first ${wh}${end}${pl}s)"
	else
		echo
	fi
	
	
	# Find out how much to crop, very buggy
	
	#mplayer ${title}.vob -quiet -slave -vo null -ao null -ss 30 -endpos 1 -vf cropdetect > crop.file
	#crop=$(cat crop.file | awk '/CROP/ { print $8 " " $9 }' | tail -n1 | sed 's|(\(.*\))\.|\1|g')
	#echo $crop
	
	
	# Find out how to scale the dimensions
	
	scale=$(title_scale ${title} "$mencoder_source" $tmpdir)
	
	
	# User set bitrate

	if [ $output_filesize ]; then
		len=$(title_length ${title} "$mencoder_source" $tmpdir)
		bitrate=$(compute_bitrate $len $output_filesize)
	fi
	
	
	# Determine the number of passes
	
	if [ ! $passes ]; then
		if [ $bitrate -lt $standard_bitrate ]; then
			twopass=y
			passes=2
		else
			passes=1
		fi
	fi
	
	
	# Encode video
	
	pass=0
	for p in $(seq $passes); do
		pass=$(( $pass + 1 ))
	
		vcodec=$(vcodec_opts "$video_codec" "$twopass" "$pass" "$bitrate")
		
		cmd="time \
nice -n20 \
mencoder -v \
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
	
	mv ${title}.avi.partial ${title}.avi	
	rm crop.file divx2pass* *~ subtitles.idx subtitles.sub ${title}.vob 2> /dev/null

done
