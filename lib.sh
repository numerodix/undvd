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
standard_bitrate=900
bitrate=$standard_bitrate
standard_audio_bitrate=160

# x264 encoding options
#x264="x264 -x264encopts subq=5:frameref=2:partitions=all:weight_b:bitrate=$bitrate:threads=auto"
faac="faac -faacopts object=1:tns:quality=100"

# xvid encoding options
#xvid="xvid -xvidencopts bitrate=$bitrate"
lame="mp3lame -lameopts vbr=2:q=3"

# codec defaults
video_codec="x264"
acodec=$lame

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

# obtain title length from lsdvd
function title_length() {
	title_no=$1
	dvd_device=$2
	tmpdir=$3

	cmd="lsdvd -avs \"$dvd_device\" > ${tmpdir}/lsdisc 2> ${tmpdir}/lsdisc.err"
	bash -c "$cmd"
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
	custom_scale="$4"

	cmd="mplayer -slave -quiet dvd://${title} -dvd-device \"$dvd_device\" -ao null -vo null -endpos 1"
	bash -c "$cmd" &> ${tmpdir}/title.size
	size=$(cat ${tmpdir}/title.size | grep "VIDEO:" | awk '{ print $3 }')
	sizex=$(echo $size | sed 's|\(.*\)x\(.*\)|\1|g')
	sizey=$(echo $size | sed 's|\(.*\)x\(.*\)|\2|g')
	if [ $sizex ]; then
		if [ $custom_scale ]; then
			nsizex=$(( $sizex * $custom_scale/$sizex ))
			nsizey=$(( $sizey * $custom_scale/$sizex ))
		else
			nsizex=$(( $sizex * 2/3 ))
			nsizey=$(( $sizey * 2/3 ))
		fi
		scale="scale=$nsizex:$nsizey"
	else
		scale="scale"
	fi
	rm ${tmpdir}/title.size

	echo $scale
}

# get video codec options
function vcodec_opts() {
	codec="$1"
	twopass="$2"
	pass="$3"
	custom_bitrate="$4"
	
	if [ $custom_bitrate ]; then
		bitrate=$custom_bitrate
	fi
	
	if [ "$codec" = "x264" ]; then
		opts="subq=5:frameref=2"
		
		if [ $twopass ]; then
			if [ $pass -eq "1" ]; then
				opts="pass=1:subq=1:frameref=1"
			elif [ $pass -eq "2" ]; then
				opts="pass=2:$opts"
			fi
		fi
		
		opts="x264 -x264encopts $opts:partitions=all:weight_b:bitrate=$bitrate:threads=auto"
	elif [ "$codec" = "xvid" ]; then
		opts=
	
		if [ $twopass ]; then
			if [ $pass -eq "1" ]; then
				opts="pass=1:"
			elif [ $pass -eq "2" ]; then
				opts="pass=2:"
			fi
		fi
	
		opts="xvid -xvidencopts ${opts}bitrate=$bitrate"
	fi
	echo $opts
}

# run encode and print updates
function run_encode() {
	cmd="$1"
	title="$2"
	twopass="$3"
	pass="$4"
	
	# Set output and logging depending on number of passes
	
	output_file="${title}.avi.partial"
	logfile="logs/${title}.log"
	
	if [ $twopass ]; then
		if [ $pass -eq 1 ]; then
			output_file="/dev/null"
			logfile="$logfile.pass1"
		elif [ $pass -eq 2 ]; then
			logfile="$logfile.pass2"
		fi
	else
		pass="-"
	fi
	
	cmd="$cmd -o $output_file"
	
	# Print initial status message
	
	status="${pl}[$pass] Encoding, to monitor log:  tail -F $logfile    "
	echo -en "${status}\r"
	
	# Execute encoder in the background
	
	( echo "$cmd"; bash -c "$cmd" ) &> $logfile &
	pid=$!
	
	# Write mencoder's ETA estimate
	
	start_time=$(date +%s)
	(while ps $pid &> /dev/null; do
		eta=$([ -e $logfile ] && tail -n15 $logfile | \
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
}