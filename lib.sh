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


### FUNCTIONS

# bad version of vobcopy requires disc to be mounted
function check_bad_vobcopy() {
	local device=$(readlink -f $1)
	bad_ver="0.5.14"
	vobcopy_ver=$(vobcopy --help 2>&1 | head -n1 | awk '{ print $2 }')
	if [ "$vobcopy_ver" = $bad_ver ]; then
		mnt_point=$(get_mount_point $device)
		if [ ! $mnt_point ]; then
			echo -e "\n${ye}=> ${pl}Vobcopy $bad_ver detected, does not support reading directly from dvd device"
			echo -e "${ye}=> ${pl}You have to mount the disc first, eg:${pl}"
			echo -e "  ${wh}sudo mount $device ${gr}/mnt/dvd${pl}"
			echo -e "  ${wh}undvd.sh -q ${gr}/mnt/dvd${wh} [other options]"
			exit 1
		fi
	fi
}

# find mount point for disc
function get_mount_point() {
	local device=$(readlink -f $1)
	mount 2>/dev/null | grep $device | awk '{ print $3 }'
}

