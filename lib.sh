# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.

### DECLARATIONS

# undvd version
version=0.2.1

tmpdir="/tmp"

# colors
wh="\033[1;37m"
pl="\033[m"
ye="\033[1;33m"
cy="\033[1;36m"
gr="\033[1;32m"
re="\033[1;31m"

# bitrates
bitrate=900
standard_audio_bitrate=160

# x264 encoding options
x264="x264 -x264encopts subq=5:frameref=2:partitions=all:weight_b:bitrate=$bitrate:threads=auto"
faac="faac -faacopts object=1:tns:quality=100"

# xvid encoding options
xvid="xvid -xvidencopts bitrate=$bitrate"
lame="mp3lame -lameopts vbr=2:q=3"

# codec defaults
video_codec="x264"
acodec=$lame

# passes default
passes=1

# mplayer filters
prescale=
postscale=

# sources
dvd_device="/dev/dvd"
disc_image="disc.iso"
mencoder_source="$disc_image"

# seconds to pause between updating rip status line
timer_refresh=5


### FUNCTIONS

# get x264 codec options
function x264_opts() {
	twopass="$1"
	pass="$2"
	custom_bitrate="$3"
	
	opts="subq=5:frameref=2"
	
	if [ $custom_bitrate ]; then
		bitrate=$custom_bitrate
	fi
	
	if [ $twopass ]; then
		if [ $pass -eq "1" ]; then
			opts="subq=1:frameref=1:pass=1"
		elif [ $pass -eq "2" ]; then
			opts="$opts:pass=2"
		fi
	fi
	
	opts="x264 -x264encopts $opts:partitions=all:weight_b:bitrate=$bitrate:threads=auto"
	echo $opts
}

# obtain title length from lsdvd
function title_length() {
	title_no=$1
	dvd_device=$2
	tmpdir=$3

	cmd="lsdvd -avs \"$dvd_device\" > ${tmpdir}/lsdisc 2> ${tmpdir}/lsdisc.err"
	sh -c "$cmd"
	titles=$(cat ${tmpdir}/lsdisc | egrep "^Title" | awk '{ print $2 }' | sed 's|,||g')

	for t in $titles; do
		if [ $t -eq $title_no ]; then
			title_length=$(cat ${tmpdir}/lsdisc | egrep "^Title: $t" | awk '{ print $4 }' | sed 's|\(.*\)\..*|\1|g')
		fi
	done
	rm ${tmpdir}/lsdisc* &> /dev/null

	hours=${title_length:0:2}
	min=${title_length:3:2}
	sec=${title_length:6:2}
	title_length=$(( ($hours*3600) + ($min*60) + $sec ))

	echo $title_length
}

# compute video bitrate based on title length
function compute_bitrate() {
	title_length=$1
	output_size=$(( $2 * 1024 ))
	audio_bitrate=$standard_audio_bitrate

	audio_size=$(( $title_length * ($audio_bitrate / 8)  ))
	bitrate=$(( ( ($output_size - $audio_size) * 8 ) / $title_length ))

	echo $bitrate
}

# compute title scaling with mplayer
function title_scale() {
	title=$1
	dvd_device="$2"
	tmpdir="$3"

	cmd="mplayer -slave -quiet dvd://${title} -dvd-device \"$dvd_device\" -ao null -vo null -endpos 1"
	bash -c "$cmd" &> ${tmpdir}/title.size
	size=$(cat ${tmpdir}/title.size | grep "VIDEO:" | awk '{ print $3 }')
	sizex=$(echo $size | sed 's|\(.*\)x\(.*\)|\1|g')
	sizey=$(echo $size | sed 's|\(.*\)x\(.*\)|\2|g')
	if [ $sizex ]; then
		sizex=$(($sizex*2/3))
		sizey=$(($sizey*2/3))
		scale="scale=$sizex:$sizey"
	else
		scale="scale"
	fi
	rm ${tmpdir}/title.size 

	echo $scale
}
