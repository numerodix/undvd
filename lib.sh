# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.

### DECLARATIONS

# undvd version
version=0.3.3

# initialize colors if the terminal can support them
if [ "$TERM" != "dumb" ]; then
	p=$(dirname $(readlink -f $0)); . $p/colors.sh
fi

# bitrates
standard_bitrate=900
standard_bitrate=575
bitrate="$standard_bitrate"
standard_audio_bitrate=160

# x264 encoding options
#x264="x264 -x264encopts subq=5:frameref=2:partitions=all:weight_b:bitrate=$bitrate:threads=auto"
#faac="faac -faacopts object=1:tns:quality=100"

# xvid encoding options
#xvid="xvid -xvidencopts bitrate=$bitrate"
lame="mp3lame -lameopts vbr=2:q=3"

# codec defaults
video_codec="x264"
acodec="$lame"

# mplayer filters
prescale=
postscale=

# sources
dvd_device="/dev/dvd"
disc_image="disc.iso"
mencoder_source="$disc_image"

# seconds to pause between updating rip status line
timer_refresh=5

# tools we need
videoutils="lsdvd mencoder mplayer vobcopy"
shellutils="awk bash bc grep egrep mount ps sed xargs"
coreutils="cat date dd dirname mkdir mv nice readlink rm seq sleep tail tr"

mencoder_acodecs="mp3lame"
mencoder_vcodecs="xvid x264"

mplayer_acodecs="ac3"
mplayer_vcodecs="mpeg-2"


### FUNCTIONS

# check for missing dependencies
function init_cmds() {
	local verbose="$1"
	
	[ $verbose ] && echo -e " * Checking for tool support... "
	for tool in $coreutils $shellutils $videoutils; do
		local path=$(which $tool 2>/dev/null)
		if [ ! "$path" ] && [ $verbose ]; then
			echo -e "   ${wa}*${r} $tool missing"
		elif [ $verbose ]; then
			echo -e "   ${ok}*${r} $path"
		fi
		eval "$tool=$path"
	done
	
	if [ $verbose ]; then
		codec_check "audio" "mencoder" "-oac help" "$mencoder_acodecs"
		codec_check "video" "mencoder" "-ovc help" "$mencoder_vcodecs"
		codec_check "audio" "mplayer" "-ac help" "$mplayer_acodecs"
		codec_check "video" "mplayer" "-vc help" "$mplayer_vcodecs"
	fi
}

# check for codec support in player/encoder
function codec_check() {
	local type="$1"
	local cmd="$2"
	local arg="$3"
	local codecs="$4"

	echo -e " * Checking for $cmd $type codec support... "
	for codec in $codecs; do
		local c=$($cmd $arg 2>/dev/null | $grep -i $codec)
		if [ ! "$c" ]; then
			echo -e "   ${wa}*${r} $codec missing"
		elif [ $verbose ]; then
			echo -e "   ${ok}*${r} $codec"
		fi
	done
}

# clone disc to iso image
function clone_dd() {
	local dvd_device="$1"
	local img="$2"

	cmd="time \
	$nice -n20 \
	$dd if=${dvd_device} of=$img.partial && \
	$mv $img.partial $img"
	( echo "$cmd"; $bash -c "$cmd" ) &> logs/clone.log
}

# clone encrypted disc to directory
function clone_vobcopy() {
	local dvd_device=$($readlink -f $1)
	local dir="$2"
	
	mnt_point=$($mount | $grep $dvd_device | $awk '{ print $3 }')

	if [ ! "$mnt_point" ]; then
		echo -e "\n${wa}=>${r} Your dvd device $dvd_device has to be mounted for this."
		echo -e "${wa}=>${r} Mount the dvd and supply the device to undvd, eg:"
		echo -e "    ${b}sudo mount ${bb}${dvd_device}${b} /mnt/dvd -t iso9660${r}"
		echo -e "    ${b}undvd.sh -d ${bb}${dvd_device}${r} [${b}other options${r}]"
	fi
	
	[ -d "$dir" ] && rm -rf $dir
	cmd="time \
	$nice -n20 \
	$vobcopy -f -l -m -F 64 -i $mnt_point -t $dir"
	( echo "$cmd"; $bash -c "$cmd" ) &> logs/clone.log
}

# obtain title length from lsdvd
function title_length() {
	local title_no="$1"
	local dvd_device="$2"

	local cmd="$lsdvd -avs '$dvd_device' 2>&1"
	local lsdvd_output=$($bash -c "$cmd")
	local titles=$(echo "$lsdvd_output" | $egrep "^Title" | $awk '{ print $2 }' | $sed 's|,||g')

	for t in $titles; do
		if [ $t -eq $title_no ]; then
			local title_length=$(echo "$lsdvd_output" | $egrep "^Title: $t" | $awk '{ print $4 }' | $sed 's|\(.*\)\..*|\1|g')
		fi
	done

	local hours=${title_length:0:2}
	local min=${title_length:3:2}
	local sec=${title_length:6:2}
	local title_length=$(( ($hours*3600) + ($min*60) + $sec ))

	echo $title_length
}

function examine_title() {
	local file="$1"

	cmd="mplayer -ao null -vo null -frames 0 -identify '$file' 2>&1"
	local mplayer_output=$($bash -c "$cmd")
	local width=$( echo "$mplayer_output" | $grep ID_VIDEO_WIDTH | $sed "s|ID_VIDEO_WIDTH=\(.*\)|\1|g" )
	local height=$( echo "$mplayer_output" | $grep ID_VIDEO_HEIGHT | $sed "s|ID_VIDEO_HEIGHT=\(.*\)|\1|g" )
	local fps=$( echo "$mplayer_output" | $grep ID_VIDEO_FPS | $sed "s|ID_VIDEO_FPS=\(.*\)|\1|g" )
	local length=$( echo "$mplayer_output" | $grep ID_LENGTH | $sed "s|ID_LENGTH=\(.*\)|\1|g" )
	local bitrate=$( echo "$mplayer_output" | $grep ID_VIDEO_BITRATE | $sed "s|ID_VIDEO_BITRATE=\(.*\)|\1|g" )
	local format=$( echo "$mplayer_output" | $grep ID_VIDEO_FORMAT | $sed "s|ID_VIDEO_FORMAT=\(.*\)|\1|g" )

	format=$( echo $format | $tr "[:upper:]" "[:lower:]" )
	echo "$width $height $fps $length $bitrate $format"
}

# compute bits per pixel per second
function compute_bpp() {
	local width="$1"
	local height="$2"
	local fps="$3"
	local length="$4"
	local video_size="$5"

	local bpp=$( echo "scale=3; (8*$video_size)/($width*$height*$fps*$length)" | $bc )

	echo $bpp
}

# compute video bitrate based on title length
function compute_bitrate() {
	local width="$1"
	local height="$2"
	local fps="$3"
	local length=$(( $4 * 60 ))  # in minutes
	local bpp="$5"
	local output_size="$6"  # in mb
	local audio_bitrate=$(( $standard_audio_bitrate * 1024 ))  # kbps

	if [ "$output_size" ]; then
		output_size=$(( $output_size * 1024*1024 ))
		local audio_size=$( echo "scale=0; $length*($audio_bitrate/8.)" | $bc )
		local video_size=$(( $output_size - $audio_size ))
		bpp=$(compute_bpp "$width" "$height" "$fps" "$length" "$video_size")
	fi
	local bitrate=$( echo "scale=0; ($width*$height*$fps*$bpp)/1024." | $bc )

	echo $bitrate
}

function display_title() {
	local width="$1"
	local height="$2"
	local fps="$3"
	local length=$( echo "scale=0; $4/60" | $bc )  # in seconds
	local bpp="$5"
	local bitrate=$( echo "scale=0; $6/(1024)" | $bc )  # bps
	local format="$7"
	local filesize=$( echo "scale=0; $8/(1024*1024)" | $bc )  # in bytes
	local filename="$9"
	
	display_title_line "${width}x${height}" $fps $length $bpp $bitrate $format $filesize "$filename"
}

function fill() {
	str=${1:0:$2}
	local f=$(( $2-${#1} ))
	pad=""
	for i in $($seq 1 $f); do
		pad=" $pad"
	done
	echo "$pad$str"
}

function display_title_line() {
	local dimensions=$(fill "$1" 9)
	local fps=$(fill "$2" 6)
	local length=$(fill "$3" 3)
	local bpp=$(fill "$4" 4)
	local bitrate=$(fill "$5" 4)
	local format=$(fill "$6" 4)
	local filesize=$(fill "$7" 4)
	local filename="$8"
	echo "$dimensions  $fps  $length  $bpp  $bitrate  $format  $filesize  $filename"
}

# compute title scaling with mplayer
function title_scale() {
	local title="$1"
	local dvd_device="$2"
	local custom_scale="$3"

	local scale="scale"
	if [ "$custom_scale" != "0" ]; then
		local cmd="$mplayer -slave -quiet dvd://${title} -dvd-device '$dvd_device' -ao null -vo null -endpos 1 2>&1"
		local mplayer_output=$($bash -c "$cmd")
		local size=$(echo "$mplayer_output" | $grep "VIDEO:" | $awk '{ print $3 }')
		local sizex=$(echo $size | $sed 's|\(.*\)x\(.*\)|\1|g')
		local sizey=$(echo $size | $sed 's|\(.*\)x\(.*\)|\2|g')
		if [ "$sizex" -a "$custom_scale" != "0" ]; then
			if [ "$custom_scale" ]; then
				local nsizex=$(( $sizex * $custom_scale/$sizex ))
				local nsizey=$(( $sizey * $custom_scale/$sizex ))
			else
				local nsizex=$(( $sizex * 2/3 ))
				local nsizey=$(( $sizey * 2/3 ))
			fi
			local scale="scale=$nsizex:$nsizey"
		fi
	fi

	echo $scale
}

# get video codec options
function vcodec_opts() {
	local codec="$1"
	local twopass="$2"
	local pass="$3"
	local custom_bitrate="$4"
	
	if [ "$custom_bitrate" ]; then
		local bitrate=$custom_bitrate
	fi
	
	if [ "$codec" = "x264" ]; then
		local opts="subq=5:frameref=2"
		
		if [ "$twopass" ]; then
			if [ $pass -eq 1 ]; then
				opts="pass=1:subq=1:frameref=1"
			elif [ $pass -eq 2 ]; then
				opts="pass=2:$opts"
			fi
		fi
		
		opts="x264 -x264encopts $opts:partitions=all:weight_b:bitrate=$bitrate:threads=auto"
	elif [ "$codec" = "xvid" ]; then
		local opts=
	
		if [ "$twopass" ]; then
			if [ $pass -eq 1 ]; then
				opts="pass=1:"
			elif [ $pass -eq 2 ]; then
				opts="pass=2:"
			fi
		fi
	
		opts="xvid -xvidencopts ${opts}bitrate=$bitrate"
	fi
	echo $opts
}

# run encode and print updates
function run_encode() {
	local cmd="$1"
	local title="$2"
	local twopass="$3"
	local pass="$4"
	
	# Set output and logging depending on number of passes
	
	local output_file="${title}.avi.partial"
	local logfile="logs/${title}.log"
	
	if [ "$twopass" ]; then
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
	
	local status="${r}[$pass] Encoding, to monitor log:  tail -F $logfile    "
	echo -en "${status}\r"
	
	# Execute encoder in the background
	
	( echo "$cmd"; $bash -c "$cmd" ) &> $logfile &
	local pid=$!
	
	# Write mencoder's ETA estimate
	
	local start_time=$($date +%s)
	(while $ps $pid &> /dev/null; do
		local eta=$([ -e $logfile ] && $tail -n15 $logfile | \
			$grep "Trem:" | $tail -n1 | $sed 's|.*\( .*min\).*|\1|g' | $tr " " "-")
		local ela=$(( ( $($date +%s) - $start_time ) / 60 ))
		echo -ne "${status}${cela}+${ela}min${r}  ${ceta}${eta}${r}    \r"
		$sleep $timer_refresh
	done)
	
	# Report exit code
	
	wait $pid
	if [ $? = 0 ]; then
		echo -e "${status}[ ${ok}done${r} ]             "
	else
		echo -e "${status}[ ${e}failed${r} ] check log"
	fi
}


# initialize command variables
init_cmds
