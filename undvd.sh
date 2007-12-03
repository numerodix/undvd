#!/bin/bash
#
# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.
#
# More info: http://www.matusiak.eu/numerodix/blog/index.php/2007/01/30/undvd-dvd-ripping-made-easy/
#
# revision 3 - -q switch made consistent with scandvd, fixing variable quoting bug
# revision 2 - adding option to rip from directory instead of disc/iso
# revision 1 - changed shell to bash and updated color scheme


### DECLARATIONS

# version
p=$(dirname $(readlink -f $0)); . $p/version

# x264 encoding options
x264="x264 -x264encopts subq=5:frameref=2:partitions=all:weight_b:bitrate=900:threads=auto"
faac="faac -faacopts object=1:tns:quality=100"

# xvid encoding options
xvid="xvid -xvidencopts bitrate=900"
lame="mp3lame -lameopts vbr=2:q=3"

# codec defaults
vcodec=$x264
acodec=$lame

# mplayer filters
prescale=
postscale=

# sources
disc_image="disc.iso"
mencoder_source="$disc_image"

# colors
wh="\033[1;37m"
pl="\033[m"
ye="\033[1;33m"
cy="\033[1;36m"
gr="\033[1;32m"
re="\033[1;31m"

echo -e "${wh}{( --- undvd.sh $version --- )}${pl}"

usage=" Usage:  ${wh}undvd.sh -t ${gr}01,02,03${wh} -a ${gr}en${wh} -s ${gr}es${wh} [-e ${gr}200${wh}] [-d ${gr}/dev/dvd${wh}] [more options]${pl}\n
\t-t \ttitles to rip (comma separated)\n
\t-a \taudio language (two letter code, eg. 'en')\n
\t-s \tsubtitle language (two letter code or 'off')\n
\t-e \texit after this many seconds (usually for testing)\n
\t-d \tdvd device to rip from (default is /dev/dvd)\n
\t-q \tdvd directory to rip from\n
\t-z \tskip copy dvd to disk (if disc.iso exists)\n
\t-f \tuse picture smoothing filter\n
\t-x \tuse xvid compression (faster, slightly lower quality)"

while getopts "t:a:s:e:d:q:zfx" opts; do
	case $opts in
		t ) titles=$(echo $OPTARG | sed 's|,| |g');;
		a ) alang=$OPTARG;;
		s ) slang=$OPTARG;;
		e ) end=$OPTARG;;
		d ) dvd_device=$OPTARG;;
		q ) dvdisdir="y";mencoder_source="$OPTARG";;
		z ) skipclone="y";;
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


if [ "x$dvdisdir" = "x" ]; then
	echo -en " * Copying dvd to disk first... "
	cmd="time \
	nice -n20 \
	dd if=${dvd_device} of=$disc_image.partial && \
	mv $disc_image.partial $disc_image"
	if [ "x$skipclone" != "x" ]; then
		echo -e "${ye}skipping${pl}"
	else
		( echo "$cmd"; sh -c "$cmd" ) &> logs/iso.log
		if [ $? != 0 ] ; then
			echo -e "${re}\nFailed, dumping log:${pl}"
			cat logs/iso.log
			exit 1
		fi
		echo -e "${gr}done${pl}"
	fi
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
	
	(while ps $pid &> /dev/null; do
		eta=$([ -e logs/${title}.log ] && tail -n15 logs/${title}.log | \
			grep "Trem:" | tail -n1 | sed 's|.*\( .*min\).*|\1|g')
		echo -ne "${status}${cy}time left:$eta${pl}       \r"
		sleep 3
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
