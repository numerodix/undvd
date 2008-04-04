# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.

### DECLARATIONS

# undvd version
version=0.4.2

# initialize colors if the terminal can support them
if [ "$TERM" != "dumb" ]; then
	p=$(dirname $(readlink -f $0)); . $p/colors.sh
fi

# constants
nominal_width="720"
nominal_height="576"
standard_ratio="2/3"
scale_baseline="$nominal_width*$nominal_height*($standard_ratio)^2"  # in pixels

h264_1pass_bpp=.195
h264_2pass_bpp=.150

xvid_1pass_bpp=.250
xvid_2pass_bpp=.200

standard_audio_bitrate=160

# audio encoding options
lame="mp3lame -lameopts vbr=2:q=3"

# codec defaults
video_codec="h264"
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

function display_tool_banner() {
	echo -e "${h1}{( --- $(basename $0) $version --- )}${r}"
}

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

# extract information from file or dvd
function examine_title() {
	local file="$1"
	local mencoder_source="$2"
	local title="$3"

	local src="\"$file\""
	if [ "$mencoder_source" -a "$title" ]; then
		src="-dvd-device \"$mencoder_source\" dvd://$title"
	fi
	local cmd="mplayer -ao null -vo null -frames 0 -identify $src 2>&1"
	local mplayer_output=$($bash -c "$cmd")

	local width=$( echo "$mplayer_output" | $grep ID_VIDEO_WIDTH | $sed "s|ID_VIDEO_WIDTH=\(.*\)|\1|g" )
	[[ $? != 0 || ! "$width" || "$width" = "0" ]] && width=1

	local height=$( echo "$mplayer_output" | $grep ID_VIDEO_HEIGHT | $sed "s|ID_VIDEO_HEIGHT=\(.*\)|\1|g" )
	[[ $? != 0 || ! "$height" || "$height" = "0" ]] && height=1

	local fps=$( echo "$mplayer_output" | $grep ID_VIDEO_FPS | $sed "s|ID_VIDEO_FPS=\(.*\)|\1|g" )
	[[ $? != 0 || ! "$fps" || "$fps" = "0.000" ]] && fps=1

	local length=$( echo "$mplayer_output" | $grep ID_LENGTH | $sed "s|ID_LENGTH=\(.*\)|\1|g" )
	if [[ $? != 0 || ! "$length" || "$length" = "0.00" ]]; then
		length=-1
	else
		length=$( echo "scale=0; $length/1"| $bc )
	fi
		
	local bitrate=$( echo "$mplayer_output" | $grep ID_VIDEO_BITRATE | $sed "s|ID_VIDEO_BITRATE=\(.*\)|\1|g" )
	if [[ $? != 0 || ! "$bitrate" || "$bitrate" = "0" ]]; then
		bitrate=1
	else
		bitrate=$( echo "scale=0; $bitrate/1"| $bc )
	fi

	local format=$( echo "$mplayer_output" | $grep ID_VIDEO_FORMAT | $sed "s|ID_VIDEO_FORMAT=\(.*\)|\1|g" )
	if [[ $? != 0 || ! "$format" ]]; then
		format=0
	else
		format=$( echo $format | $tr "[:upper:]" "[:lower:]" )
	fi

	echo "$width $height $fps $length $bitrate $format"
}

# extract information from file or dvd
function crop_title() {
	local mencoder_source="$1"
	local title="$2"

	local src="-dvd-device \"$mencoder_source\" dvd://$title"
	local cmd="mplayer -ao null -vo null -fps 10000 -vf cropdetect $src 2>&1"
	local mplayer_output=$($bash -c "$cmd")

	local crop_filter=$(echo "$mplayer_output" |\
		 awk '/CROP/' | tail -n1 | sed 's|.*(-vf crop=\(.*\)).*|\1|g')

	local w=$(echo "$crop_filter" | sed "s|\(.*\):.*:.*:.*|\1|g")
	local h=$(echo "$crop_filter" | sed "s|.*:\(.*\):.*:.*|\1|g")
	local x=$(echo "$crop_filter" | sed "s|.*:.*:\(.*\):.*|\1|g")
	local y=$(echo "$crop_filter" | sed "s|.*:.*:.*:\(.*\)|\1|g")

	local width=$(( $w-$x ))
	local height=$(( $h-$y ))

	echo "$width $height $crop_filter"
}

# compute bits per pixel
function compute_bpp() {
	local width="$1"
	local height="$2"
	local fps="$3"
	local length="$4"
	local video_size="$5"  # in mb
	local bitrate="$6"  # kbps

	if [ "$bitrate" ]; then
		bitrate=$( echo "scale=5; $bitrate*1024" | $bc )
	else
		video_size=$(( $video_size *1024*1024 ))  # in mb
		bitrate=$( echo "scale=5; (8*$video_size)/$length" | $bc )
	fi
	local bpp=$( echo "scale=3; ($bitrate)/($width*$height*$fps)" | $bc )

	echo $bpp
}

# set bpp based on the codec and number of passes
function set_bpp() {
	local video_codec="$1"
	local twopass="$2"

	if [ "$video_codec" = "h264" ]; then
		local bpp="$h264_1pass_bpp"
		[ "$twopass" ] && bpp="$h264_2pass_bpp"
	else
		local bpp="$xvid_1pass_bpp"
		[ "$twopass" ] && bpp="$xvid_2pass_bpp"
	fi

	echo $bpp
}

# set the number of passes based on codec and bpp
function set_passes() {
	local video_codec="$1"
	local bpp="$2"

	local passes=1
	
	if [ "$video_codec" = "h264" ]; then
		[[ "$bpp" < "$h264_1pass_bpp" ]] && passes=2
	else
		[[ "$bpp" < "$xvid_1pass_bpp" ]] && passes=2
	fi

	echo $passes
}

# compute video bitrate based on title length
function compute_bitrate() {
	local width="$1"
	local height="$2"
	local fps="$3"
	local length="$4"  # in seconds
	local bpp="$5"
	local output_size="$6"  # in mb
	local audio_bitrate=$(( $standard_audio_bitrate * 1024 ))  # kbps

	local bitrate=$( echo "scale=0; ($width*$height*$fps*$bpp)/1024." | $bc )

	echo $bitrate
}

# compute size of media given length and bitrate
function compute_media_size() {
	local length="$1"  # in seconds
	local bitrate="$2"  # kbps
	echo $( echo "scale=0; ($bitrate/8)*$length/1024" | $bc )
}

# display a title
function display_title() {
	local width="$1"
	local height="$2"
	local fps="$3"
	local length="$4"  # in seconds
	local bpp=$( echo "scale=3; $5/(1)" | $bc )
	local bitrate=$( echo "scale=0; $6/(1)" | $bc )  # kbps
	local passes="$7"
	local format="$8"
	local filesize=$( echo "scale=0; $9/(1)" | $bc )  # in mb
	local filename="${10}"

	[ "$length" != "-1" ] && length=$( echo "scale=0; $length/60" | $bc )
	
	display_title_line "" "${width}x${height}" "$fps" "$length" "$bpp" "$bitrate" "$passes" "$format" "$filesize" "$filename"
}

# truncate string and pad with whitespace to fit the desired length
function fill() {
	str=${1:0:$2}
	local f=$(( $2-${#1} ))
	pad=""
	for i in $($seq 1 $f); do
		pad=" $pad"
	done
	echo "$pad$str"
}

# set formatting of bpp output depending on value
function format_bpp() {
	local bpp="$1"
	local video_codec="$2"

	if [[ "$video_codec" = "h264" ]]; then
		if [[ "$bpp" < "$h264_2pass_bpp" ]]; then
			bpp="${e}$bpp${r}"
		elif [[ "$bpp" > "$h264_1pass_bpp" ]]; then 
			bpp="${wa}$bpp${r}"
		else
			bpp="${bb}$bpp${r}"
		fi
	elif [ "$video_codec" = "xvid" ]; then
		if [[ "$bpp" < "$xvid_2pass_bpp" ]]; then
			bpp="${e}$bpp${r}"
		elif [[ "$bpp" > "$xvid_1pass_bpp" ]]; then 
			bpp="${wa}$bpp${r}"
		else
			bpp="${bb}$bpp${r}"
		fi
	else
		bpp="${b}$bpp${r}"
	fi
	
	echo "$bpp"
}

# print one line of title display, whether header or not
function display_title_line() {
	local header="$1"
	local dimensions="$2"
	local fps="$3"
	local length="$4"
	local bpp="$5"
	local bitrate="$6"
	local passes="$7"
	local format="$8"
	local filesize="$9"
	local filename="${10}"

	if [ "$header" ]; then
		dimensions="dim"
		fps="fps"
		length="len"
		bpp="bpp"
		bitrate="bitrate"
		passes="p"
		format="codec"
		filesize="size"
		filename="title"
	fi

	[ "$dimensions" = "1x1" ] && unset dimensions
	[ "$fps" = "1" ] && unset fps
	[ "$length" = "-1" ] && unset length
	[ "$bpp" = "0" ] && unset bpp
	[ "$bitrate" = "0" ] && unset bitrate
	[ "$filesize" = "-1" ] && unset filesize
	[ "$format" = "0" ] && unset format
	[ "$passes" = "0" ] && unset passes

	dimensions=$(fill "$dimensions" 9)
	fps=$(fill "$fps" 6)
	length=$(fill "$length" 3)
	bpp=$(fill "$bpp" 4)
	bitrate=$(fill "$bitrate" 4)
	passes=$(fill "$passes" 1)
	format=$(fill "$format" 4)
	filesize=$(fill "$filesize" 4)

	pre=
	post=
	if [ "$header" ]; then 
		pre="${b}"
		post="${r}"
	else
		bpp=$(format_bpp "$bpp" "$8")
	fi
	echo -e "${pre}$dimensions  $fps  $length  $bpp  $bitrate  $passes $format  $filesize  $filename${post}"
}

# compute title scaling
function title_scale() {
	local width="$1"
	local height="$2"
	local custom_scale="$3"

	local nwidth="$width"
	local nheight="$height"
	if [ "$custom_scale" != "0" ]; then  # scaling isn't disabled
		
		# scale to the width given by user (upscaling permitted)
		if [ "$custom_scale" ]; then
			nwidth=$(( $width * $custom_scale/$width ))
			nheight=$(( $height * $custom_scale/$width ))

		# apply default scaling heuristic
		else
			# compute scaling factor based on baseline value
			local sbaseline="$scale_baseline"
			local scurrent="$width*$height"
			local sfactor="sqrt($sbaseline/($scurrent))"

			# evaluate factor*1000 to integer value
			local factor=$( echo "scale=40; $sfactor*1000/1" | $bc )
			local factor=$( echo "scale=0; $factor/1" | $bc )

			# if multiplier is less than 1 we will downscale
			(( $factor < 1000 )) && local need_scaling="y"
	
			# scale by factor
			if [ "$need_scaling" ]; then
				nwidth=$( echo "scale=40; $width*$sfactor" | $bc )
				nwidth=$( echo "scale=0; ($nwidth+1)/1" | $bc )
				nheight=$( echo "scale=40; $height*$sfactor" | $bc )
				nheight=$( echo "scale=0; ($nheight+1)/1" | $bc )
			fi
		fi

		# dimensions have been changed, make sure they are multiples of 16
		scale_info=( $(scale16 "$width" "$height" "$nwidth" "$nheight") )
		nwidth=${scale_info[0]}
		nheight=${scale_info[1]}

		# make sure the new dimensions are sane
		if (( $nwidth * $nheight <= 0 )); then
			local nwidth="$width"
			local nheight="$height"
		fi
	fi

	echo "$nwidth $nheight"

}

# scale dimensions to nearest (lower/upper) multiple of 16
function scale16() {
	local orig_width="$1"
	local orig_height="$2"
	local width="$3"
	local height="$4"
	local divisor=16

	# if the original dimensions are not multiples of 16, no amount of scaling
	# will bring us to an aspect ratio where the smaller dimensions are
	if (( ($orig_width%$divisor) + ($orig_height%$divisor) != 0 )); then
		width="$orig_width"
		height="$orig_height"
	else
		local ratio="$orig_height/$orig_width"

		step=-1
		unset completed
		while [ ! "$completed" ]; do
			step=$(( $step + 1 ))

			local up_step=$(( $width + ($step * $divisor) ))
			local down_step=$(( $width - ($step * $divisor) ))
			for x_step in $down_step $up_step; do
				local x_width=$(( $x_step - ($x_step % $divisor) ))
				local x_height=$( echo "scale=0; $x_width*$ratio/1" | $bc )
				if (( ($x_width % $divisor) + ($x_height % $divisor) == 0 )); then
					completed="y"
					width=$x_width
					height=$x_height
				fi
			done
		done
	fi

	echo "$width $height"
}

# get video codec options
function vcodec_opts() {
	local codec="$1"
	local twopass="$2"
	local pass="$3"
	local bitrate="$4"
	
	if [ "$codec" = "h264" ]; then
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
	
	( echo $cmd; $bash -c "$cmd" ) &> $logfile &
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
