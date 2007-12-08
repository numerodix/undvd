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
\t-f \tuse picture smoothing filter\n
\t-x \tuse xvid compression (faster, slightly lower quality)"

while getopts "t:a:s:e:d:q:i:fx" opts; do
	case $opts in
		t ) titles=$(echo $OPTARG | sed 's|,| |g');;
		a ) alang=$OPTARG;;
		s ) slang=$OPTARG;;
		e ) end=$OPTARG;;
		d ) dvd_device=$OPTARG;;
		q ) dvdisdir="y";mencoder_source="$OPTARG";;
		i ) skipclone="y";mencoder_source="$OPTARG";;
		f ) prescale="spp,";postscale=",hqdn3d";;
		x ) vcodec=$xvid;acodec=$lame;;
		* ) echo -e $usage; exit 1;;
	esac
done

if [ "x$dvd_device" = "x" ]; then
	dvd_device="/dev/dvd"
fi


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
	
	# check for vobcopy bug. enforce mounted disc if found
	check_bad_vobcopy ${dvd_device}
	
	# transparently find mount point and pass to vobcopy
	mnt_point=$(get_mount_point ${dvd_device})
	cmd="time \
	nice -n20 \
	vobcopy -l -m -F 64 -t disc -i ${mnt_point}"
	
	# vobcopy detects existing output dir and prompts for action, we don't
	# want that
	[ -d disc ] && rm -rf disc
	
	( echo "$cmd"; bash -c "$cmd" ) &> logs/iso.log
	if [ $? != 0 ] ; then
		echo -e "${re}\nFailed, dumping log:${pl}"
		cat logs/iso.log
		exit 1
	fi
	
	# set mencoder_source to the new directory
	mencoder_source="disc"
	echo -e "${gr}done${pl}"
fi


for i in $titles; do
	title=$i
	
	echo -en " * Now ripping title ${wh}$title${pl}, with audio: ${wh}$alang${pl} and subtitles: ${wh}$slang${pl}"
	if [ "x$end" != "x" ]; then
		echo -e " ${pl}(stopping after ${wh}${end}${pl}s)"
	else
		echo
	fi
	
	
	# Find out how much to crop, very buggy
	
	#mplayer ${title}.vob -quiet -slave -vo null -ao null -ss 30 -endpos 1 -vf cropdetect > crop.file
	#crop=$(cat crop.file | awk '/CROP/ { print $8 " " $9 }' | tail -n1 | sed 's|(\(.*\))\.|\1|g')
	#echo $crop
	
	
	# Find out how to scale the dimensions
	
	mplayer -slave -quiet \
		dvd://${title} \
		-dvd-device "$mencoder_source" \
		-ao null \
		-vo null \
		-endpos 1 \
	&> /tmp/title.size
	size=$(cat /tmp/title.size | grep "VIDEO:" | awk '{ print $3 }')
	sizex=$(echo $size | sed 's|\(.*\)x\(.*\)|\1|g')
	sizey=$(echo $size | sed 's|\(.*\)x\(.*\)|\2|g')
	if [ "x$sizex" != x ]; then
		sizex=$(($sizex*2/3))
		sizey=$(($sizey*2/3))
		scale="scale=$sizex:$sizey"
		expand=",expand=$sizex:$sizey::1"
	else
		scale="scale"
	fi
	
	rm /tmp/title.size
	
	
	# Encode video
	
	status="${pl}[$title] Encoding, to monitor log:  tail -F logs/${title}.log    "
	echo -en "${status}\r"
	
	cmd="time \
nice -n20 \
mencoder -v \
dvd://${title} \
-dvd-device \"$mencoder_source\" \
-o ${title}.avi.partial \
-alang ${alang} \
-slang ${slang} \
${crop} \
${endpos} \
-vf ${prescale}${scale}${postscale} \
-ovc ${vcodec} \
-oac ${acodec} && \
mv ${title}.avi.partial ${title}.avi"
	( echo "$cmd"; sh -c "$cmd" ) &> logs/${title}.log &
	pid=$!
	
	# Write mencoder's ETA estimate
	
	start_time=$(date +%s)
	(while ps $pid &> /dev/null; do
		eta=$([ -e logs/${title}.log ] && tail -n15 logs/${title}.log | \
			grep "Trem:" | tail -n1 | sed 's|.*\( .*min\).*|\1|g' | tr " " "-")
		ela=$(( ( $(date +%s) - $start_time ) / 60 ))
		echo -ne "${status}${ye}+${ela}min${pl}  ${cy}${eta}${pl}    \r"
		sleep $timer_refresh
	done)
	
	# Report exit code
	
	wait $pid
	if [ $? = 0 ]; then
		echo -e "${status}[ ${gr}done${pl} ]             "
	else
		echo -e "${status}[ ${re}failed${pl} ] ${re}check log${pl}"
	fi
	
	rm crop.file divx2pass* *~ subtitles.idx subtitles.sub ${title}.vob 2> /dev/null

done
