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

# bitrate
bitrate=900

# x264 encoding options
x264="x264 -x264encopts subq=5:frameref=2:partitions=all:weight_b:bitrate=$bitrate:threads=auto"
faac="faac -faacopts object=1:tns:quality=100"

# xvid encoding options
xvid="xvid -xvidencopts bitrate=$bitrate"
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

# seconds to pause between updating rip status line
timer_refresh=5


# obtain title length from lsdvd
function title_length() {
	title_no=$1
	dvd_device=$2
	tmpdir=$3

	cmd="lsdvd -avs $dvdisdir \"$dvd_device\" > ${tmpdir}/lsdisc 2> ${tmpdir}/lsdisc.err"
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
	audio_bitrate=$2
	output_size=$(( $3 * 1024 ))

	audio_size=$(( $title_length * ($audio_bitrate / 8)  ))
	echo $audio_size
	bitrate=$(( ( ($output_size - $audio_size) * 8 ) / $title_length ))

	echo $bitrate
}

len=$(title_length 03 /gentoo/st/sein8xcd1 /tmp)
echo $len

br=$(compute_bitrate $len 160 167)
echo $br

