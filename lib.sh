# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.

### DECLARATIONS

# undvd version
version=0.3.2

# initialize colors if the terminal can support them
if [ "$TERM" != "dumb" ]; then
	p=$(dirname $(readlink -f $0)); . $p/colors.sh
fi

# bitrates
standard_bitrate=900
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
shellutils="awk bash grep egrep mount ps sed xargs"
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

# compute video bitrate based on title length
function compute_bitrate() {
	local title_length="$1"
	local output_size=$(( $2 * 1024 ))
	local audio_bitrate="$standard_audio_bitrate"

	local audio_size=$(( $title_length * ($audio_bitrate / 8)  ))
	local bitrate=$(( ( ($output_size - $audio_size) * 8 ) / $title_length ))

	echo $bitrate
}

# compute title scaling with mplayer
function title_scale() {
	local title="$1"
	local dvd_device="$2"
	local custom_scale="$3"

	local cmd="$mplayer -slave -quiet dvd://${title} -dvd-device '$dvd_device' -ao null -vo null -endpos 1 2>&1"
	local mplayer_output=$($bash -c "$cmd")
	local size=$(echo "$mplayer_output" | $grep "VIDEO:" | $awk '{ print $3 }')
	local sizex=$(echo $size | $sed 's|\(.*\)x\(.*\)|\1|g')
	local sizey=$(echo $size | $sed 's|\(.*\)x\(.*\)|\2|g')
	if [ "$sizex" ]; then
		if [ "$custom_scale" ]; then
			local nsizex=$(( $sizex * $custom_scale/$sizex ))
			local nsizey=$(( $sizey * $custom_scale/$sizex ))
		else
			local nsizex=$(( $sizex * 2/3 ))
			local nsizey=$(( $sizey * 2/3 ))
		fi
		local scale="scale=$nsizex:$nsizey"
	else
		local scale="scale"
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
