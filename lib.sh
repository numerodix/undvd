# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.

### DECLARATIONS

# undvd version
version=0.6.1

# initialize colors if the terminal can support them
if [[ "$TERM" && "$TERM" != "dumb" ]]; then
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

# codec defaults
container="avi"

# mplayer filters
prescale=
postscale=",harddup"

# sources
dvd_device="/dev/dvd"
disc_image="disc.iso"
mencoder_source="$disc_image"

# seconds to pause between updating rip status line
timer_refresh=5

# tools we need
videoutils="lsdvd mencoder mplayer"
shellutils="awk bash bc grep egrep getopt mount ps sed xargs"
coreutils="cat date dd dirname head mkdir mv nice readlink rm seq sleep sort tail tr true"
extravideoutils="mp4creator mkvmerge ogmmerge vobcopy"

mencoder_acodecs="copy faac lavc mp3lame"
mencoder_vcodecs="copy lavc x264 xvid"

mplayer_acodecs="ac3"
mplayer_vcodecs="mpeg-2"


### FUNCTIONS

suite_name="undvd"
tool_name=$(basename $0)

function fatal() {
	local msg="$1"; shift;

	echo -e "${e}$msg${r}" > /dev/stderr
	kill -s SIGTERM $$
}

# escape quotes in filenames
function escape_chars() {
	local s="$1"; shift;
	# for some reason single quotes are not a problem?
	s=$(echo "$s" | $sed 's|\\|\\\\|g')
	s=$(echo "$s" | $sed 's|`|\\`|g')
	s=$(echo "$s" | $sed 's|"|\\"|g')
	echo "$s"
}

function display_tool_banner() {
	echo -e "${h1}{( --- ${tool_name} $version --- )}${r}"
}

# check for missing dependencies
function init_cmds() {
	local verbose="$1"; shift;
	
	[[ $verbose ]] && echo -e " * Checking for tool support... "
	for tool in $coreutils $shellutils $videoutils $extravideoutils; do
		local path=$(which $tool 2>/dev/null)
		if [[ ! "$path" && $verbose ]]; then
			echo -e "   ${wa}*${r} $tool missing"
		elif [[ $verbose ]]; then
			echo -e "   ${ok}*${r} $path"
		fi
		eval "$tool=$path"
	done
	
	if [[ $verbose ]]; then
		codec_check "audio" "mplayer" "-ac help" "$mplayer_acodecs"
		codec_check "video" "mplayer" "-vc help" "$mplayer_vcodecs"
		codec_check "audio" "mencoder" "-oac help" "$mencoder_acodecs"
		codec_check "video" "mencoder" "-ovc help" "$mencoder_vcodecs"
	fi
}

# check for codec support in player/encoder
function codec_check() {
	local type="$1"; shift;
	local cmd="$1"; shift;
	local arg="$1"; shift;
	local codecs="$1"; shift;

	echo -e " * Checking for $cmd $type codec support... "
	for codec in $codecs; do
		local c=$($cmd $arg 2>/dev/null | $grep -i $codec)
		if [[ ! "$c" ]]; then
			echo -e "   ${wa}*${r} $codec missing"
		else
			echo -e "   ${ok}*${r} $codec"
		fi
	done
}

# get version of the tool
function tool_version() {
	local name="$1"; shift;
	local args="$1"; shift;
	local extract="$1"; shift;

	v=$($name $args 2>&1 | $head -n1 | eval $extract)
	if which $name &>/dev/null; then
		echo -e "[${bb}*${r}] $name $v"
	else
		echo -e "[${e}!${r}] $name missing"
	fi
}

# print package version and versions of tools
function print_version() {
	local name="$suite_name"

    echo "${name} $version"
    echo "  $(tool_version "mplayer" "-ac help" "\$awk '{ print \$2 }'")"
    echo "  $(tool_version "mencoder" "-oac help" "\$awk '{ print \$2 }'")"
    echo "  $(tool_version "lsdvd" "-V" "\$awk '{ print \$2 }'")"
    echo "  $(tool_version "vobcopy" "--version" "\$awk '{ print \$2 }'")"
    echo "  $(tool_version "mp4creator" "-version" "\$awk '{ print \$5 }'")"
    echo "  $(tool_version "mkvmerge" "--version" "\$awk '{ print \$2 }'")"
    echo "  $(tool_version "ogmmerge" "--version" "\$awk '{ print \$2 }'")"
    exit
}

# generate parse command to execute in caller
# note: $usage and $@ variables evaluated in calling context!
function get_parsecmd() {
	local tool_name="$1"; shift;
	local shorts="$1"; shift;
	local longs="$1"; shift;

	echo "
		echo -en \${e};
		opts=\`\$getopt -o \"$shorts\" --long \"$longs\" -n \"$tool_name\" -- \"\$@\"\`;
		if [ \$? != 0 ]; then
			echo -en \${r};
			echo -e \"\$usage\";
			exit 1;
		else
			echo -en \${r};
		fi;
		eval set -- \"\$opts\""
}

# match an int
function check_int() {
	local v="$1"; shift;
	if egrep '^[0-9]*$' <(echo "$v") &>/dev/null; then
		return 0
	else
		return 1
	fi
}

# match an int
function check_float() {
	local v="$1"; shift;
	if check_int "$(echo "$v/1" | $bc 2>&1)"; then
		return 0
	else
		return 1
	fi
}

# validate value against type
function check() {
	local type="$1"; shift;
	local value="$1"; shift;

	if [[ "$type" = "int" ]]; then
		if ! check_int "$value"; then
			fatal "Failed to read positive int value ${bb}$value"
		fi
	elif [[ "$type" = "float" ]]; then
		if ! check_float "$value"; then
			fatal "Failed to read positive float value ${bb}$value"
		fi
	fi

	echo "$value"
}

# prepend with int key if int, otherwise with string key
function ternary_int_str() {
	local value="$1"; shift;
	local int_key="$1"; shift;
	local str_key="$1"; shift;

	if [[ "$value" =~ ^[0-9]+$ ]]; then
		echo "$int_key $value"
	else
		echo "$str_key $value"
	fi
}

# clone disc to iso image
function clone_dd() {
	local dvd_device="$1"; shift;
	local img="$1"; shift;

	local src="\"$(escape_chars "$dvd_device")\""
	local cmd="time \
	$nice -n20 \
	$dd if=${src} of=$img.partial && \
	$mv $img.partial $img"
	( echo "$cmd"; $bash -c "$cmd" ) &> logs/clone.log
}

# clone encrypted disc to directory
function clone_vobcopy() {
	local dvd_device="$1"; shift;
	local dir="$1"; shift;
	
	dvd_device=$(escape_chars "$(readlink -f "$dvd_device")")

	local mnt_point=$($mount | $grep "$dvd_device" | $awk '{ print $3 }')

	if [[ ! "$mnt_point" ]]; then
		echo -e "\n${wa}=>${r} Your dvd device ${bb}$dvd_device${r} has to be mounted for this."
		echo -e "${wa}=>${r} Mount the dvd and supply the device to ${tool_name}, eg:"
		echo -e "    ${b}sudo mount ${bb}${dvd_device}${b} /mnt/dvd -t iso9660${r}"
		echo -e "    ${b}${tool_name} -d ${bb}${dvd_device}${r} [${b}other options${r}]"
		exit 1
	fi
	
	[[ -d "$dir" ]] && rm -rf "$dir"
	cmd="time \
	$nice -n20 \
	$vobcopy -f -l -m -F 64 -i \"$mnt_point\" -t \"$dir\""
	( echo "$cmd"; $bash -c "$cmd" ) &> logs/clone.log
}

# extract number of titles from dvd
function examine_dvd_for_titlecount() {
	local source="$1"; shift;

	local src="-dvd-device \"$(escape_chars "$source")\" dvd://"
	local cmd="mplayer -ao null -vo null -frames 0 -identify $src 2>&1"
	local mplayer_output=$($bash -c "$cmd")

	local titles=$( echo "$mplayer_output" | $grep "ID_DVD_TITLES" | \
		$sed "s|ID_DVD_TITLES=\(.*\)|\1|g" )

	echo "$titles"
}

# extract information from file or dvd title
function examine_title() {
	local file="$1"; shift;
	local dvd_device="$1"; shift;

	local src="\"$(escape_chars "$file")\""
	if [[ "$dvd_device" ]]; then
		local src="$src -dvd-device \"$(escape_chars "$dvd_device")\""
	fi
	local cmd="mplayer -ao null -vo null -frames 0 -identify $src 2>&1"
	local mplayer_output=$($bash -c "$cmd")

	local width=$( echo "$mplayer_output" | $grep ID_VIDEO_WIDTH | \
		$sed "s|ID_VIDEO_WIDTH=\(.*\)|\1|g" )
	[[ $? != 0 || ! "$width" || "$width" = "0" ]] && width=1

	local height=$( echo "$mplayer_output" | $grep ID_VIDEO_HEIGHT | \
		$sed "s|ID_VIDEO_HEIGHT=\(.*\)|\1|g" )
	[[ $? != 0 || ! "$height" || "$height" = "0" ]] && height=1

	local fps=$( echo "$mplayer_output" | $grep ID_VIDEO_FPS | \
		$sed "s|ID_VIDEO_FPS=\(.*\)|\1|g" )
	[[ $? != 0 || ! "$fps" || "$fps" = "0.000" ]] && fps=1

	local length=$( echo "$mplayer_output" | $grep ID_LENGTH | \
		$sed "s|ID_LENGTH=\(.*\)|\1|g" )
	if [[ $? != 0 || ! "$length" || "$length" = "0.00" ]]; then
		length=-1
	else
		length=$( echo "scale=0; $length/1"| $bc )
	fi

	local abitrate=$( echo "$mplayer_output" | $grep ID_AUDIO_BITRATE | \
		$sed "s|ID_AUDIO_BITRATE=\(.*\)|\1|g" | $sort -n | $tail -n1 )
	if [[ $? != 0 || ! "$abitrate" || "$abitrate" = "0" ]]; then
		abitrate=1
	else
		abitrate=$( echo "scale=0; $abitrate/1"| $bc )
	fi
		
	local vbitrate=$( echo "$mplayer_output" | $grep ID_VIDEO_BITRATE | \
		$sed "s|ID_VIDEO_BITRATE=\(.*\)|\1|g" )
	if [[ $? != 0 || ! "$vbitrate" || "$vbitrate" = "0" ]]; then
		vbitrate=1
	else
		vbitrate=$( echo "scale=0; $vbitrate/1"| $bc )
	fi

	local aformat=$( echo "$mplayer_output" | $grep ID_AUDIO_CODEC | \
		$sed "s|ID_AUDIO_CODEC=\(.*\)|\1|g" )
	if [[ $? != 0 || ! "$aformat" ]]; then
		aformat=0
	else
		aformat=$( echo $aformat | $tr "[:upper:]" "[:lower:]" )
	fi

	local vformat=$( echo "$mplayer_output" | $grep ID_VIDEO_FORMAT | \
		$sed "s|ID_VIDEO_FORMAT=\(.*\)|\1|g" )
	if [[ $? != 0 || ! "$vformat" ]]; then
		vformat=0
	else
		vformat=$( echo $vformat | $tr "[:upper:]" "[:lower:]" )
	fi

	echo "$width $height $fps $length $abitrate $aformat $vbitrate $vformat"
}

# extract information from file or dvd title
function crop_title() {
	local file="$1"; shift;
	local dvd_device="$1"; shift;

	local src="\"$(escape_chars "$file")\""
	if [[ "$dvd_device" ]]; then
		local src="$src -dvd-device \"$(escape_chars "$dvd_device")\""
	fi
	local cmd="mplayer -ao null -vo null -fps 10000 -vf cropdetect $src 2>&1"
	local mplayer_output=$($bash -c "$cmd")

	local crop_filter=$(echo "$mplayer_output" |\
		 $awk '/CROP/' | $tail -n1 | $sed 's|.*(-vf crop=\(.*\)).*|\1|g')

	local width=$(echo "$crop_filter" | $sed "s|\(.*\):.*:.*:.*|\1|g")
	local height=$(echo "$crop_filter" | $sed "s|.*:\(.*\):.*:.*|\1|g")

	echo "$width $height $crop_filter"
}

# compute bits per pixel
function compute_bpp() {
	local width="$1"; shift;
	local height="$1"; shift;
	local fps="$1"; shift;
	local length="$1"; shift;
	local video_size="$1"; shift;  # in mb
	local bitrate="$1"; shift;  # kbps

	if [[ "$bitrate" ]]; then
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
	local video_codec="$1"; shift;
	local twopass="$1"; shift;

	if [[ "$video_codec" = "h264" ]]; then
		local bpp="$h264_1pass_bpp"
		[[ "$twopass" ]] && bpp="$h264_2pass_bpp"
	else
		local bpp="$xvid_1pass_bpp"
		[[ "$twopass" ]] && bpp="$xvid_2pass_bpp"
	fi

	echo $bpp
}

# set the number of passes based on codec and bpp
function set_passes() {
	local video_codec="$1"; shift;
	local bpp="$1"; shift;

	local passes=1
	
	if [[ "$video_codec" = "h264" ]]; then
		[[ "$bpp" < "$h264_1pass_bpp" ]] && passes=2
	else
		[[ "$bpp" < "$xvid_1pass_bpp" ]] && passes=2
	fi

	echo $passes
}

# compute video bitrate based on title length
function compute_bitrate() {
	local width="$1"; shift;
	local height="$1"; shift;
	local fps="$1"; shift;
	local bpp="$1"; shift;

	local bitrate=$( echo "scale=0; ($width*$height*$fps*$bpp)/1024." | $bc )

	echo $bitrate
}

# compute size of media given length and bitrate
function compute_media_size() {
	local length="$1"; shift;  # in seconds
	local bitrate="$1"; shift;  # kbps
	echo $( echo "scale=0; ($bitrate/8)*$length/1024" | $bc )
}

# display a title
function display_title() {
	local width="$1"; shift;
	local height="$1"; shift;
	local fps="$1"; shift;
	local length="$1"; shift;
	local bpp="$1"; shift;
	local passes="$1"; shift;
	local vbitrate="$1"; shift;
	local vformat="$1"; shift;
	local abitrate="$1"; shift;
	local aformat="$1"; shift;
	local filesize="$1"; shift;
	local filename="$1"; shift;

	bpp=$( echo "scale=3; $bpp/(1)" | $bc )
	vbitrate=$( echo "scale=0; $vbitrate/(1)" | $bc )  # kbps
	abitrate=$( echo "scale=0; $abitrate/(1)" | $bc )  # kbps
	filesize=$( echo "scale=0; $filesize/(1)" | $bc )  # in mb

	[[ "$length" != "-1" ]] && length=$( echo "scale=0; $length/60" | $bc )
	
	display_title_line "" "${width}x$height" "$fps" "$length" "$bpp" "$passes" "$vbitrate" "$vformat" "$abitrate" "$aformat" "$filesize" "$filename"
}

# truncate string and pad with whitespace to fit the desired length
function fill() {
	local s="$1"; shift;
	local w="$1"; shift;
	local l="$1"; shift;

	str=${s:0:$w}
	local f=$(( $w-${#s} ))
	pad=""
	for i in $($seq 1 $f); do
		pad=" $pad"
	done

	if [[ "$l" ]]; then
		if [[ "${#str}" == "$w" ]]; then
			echo "${str::$w-3}...$pad"
		else
			echo "$str$pad"
		fi
	else
		echo "$pad$str"
	fi
}

# set formatting of bpp output depending on value
function format_bpp() {
	local bpp="$1"; shift;
	local video_codec="$1"; shift;

	if [[ "$video_codec" = "h264" ]]; then
		if [[ "$bpp" < "$h264_2pass_bpp" ]]; then
			bpp="${e}$bpp${r}"
		elif [[ "$bpp" > "$h264_1pass_bpp" ]]; then 
			bpp="${wa}$bpp${r}"
		else
			bpp="${bb}$bpp${r}"
		fi
	elif [[ "$video_codec" = "xvid" ]]; then
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
	local header="$1"; shift;
	local dimensions="$1"; shift;
	local fps="$1"; shift;
	local length="$1"; shift;
	local bpp="$1"; shift;
	local passes="$1"; shift;
	local vbitrate="$1"; shift;
	local vformat="$1"; shift;
	local abitrate="$1"; shift;
	local aformat="$1"; shift;
	local filesize="$1"; shift;
	local filename="$1"; shift;

	if [[ "$header" ]]; then
		dimensions="dim"
		fps="fps"
		length="len"
		bpp="bpp"
		passes="p"
		vbitrate="vbitrate"
		vformat="vcodec"
		abitrate="abitrate"
		aformat="acodec"
		filesize="size"
		filename="title"
	fi

	[[ "$dimensions" = "1x1" ]] && unset dimensions
	[[ "$fps" = "1"          ]] && unset fps
	[[ "$length" = "-1"      ]] && unset length
	[[ "$bpp" = "0"          ]] && unset bpp
	[[ "$passes" = "0"       ]] && unset passes
	[[ "$vbitrate" = "0"     ]] && unset vbitrate
	[[ "$vformat" = "0"      ]] && unset vformat
	[[ "$abitrate" = "0"     ]] && unset abitrate
	[[ "$aformat" = "0"      ]] && unset aformat
	[[ "$filesize" = "-1"    ]] && unset filesize

	dimensions=$(fill "$dimensions" 9)
	fps=$(fill "$fps" 6)
	length=$(fill "$length" 3)
	bpp=$(fill "$bpp" 4)
	passes=$(fill "$passes" 1)
	vbitrate=$(fill "$vbitrate" 4)
	vformat=$(fill "$vformat" 4)
	abitrate=$(fill "$abitrate" 4)
	aformat=$(fill "$aformat" 4)
	filesize=$(fill "$filesize" 4)

	pre=
	post=
	if [[ "$header" ]]; then
		pre="${b}"
		post="${r}"
	else
		bpp=$(format_bpp "$bpp" "$vformat")
	fi
	echo -e "${pre}$dimensions  $fps  $length  $bpp $passes $vbitrate $vformat  $abitrate $aformat  $filesize  $filename${post}"
}

# compute title scaling
function title_scale() {
	local width="$1"; shift;
	local height="$1"; shift;
	local custom_scale="$1"; shift;

	local nwidth="$width"
	local nheight="$height"
	if [[ "$custom_scale" != "off" ]]; then  # scaling isn't disabled
		unset nwidth
		unset nheight
		aspect_ratio="$height/$width"
		
		# scale to the width given by user (upscaling permitted)
		if [[ "$custom_scale" ]]; then
			if check_int "$custom_scale"; then
				nwidth="$custom_scale"
			else
				nwidth=${custom_scale%:*}
				nheight=${custom_scale#*:}
				aspect_ratio="$nheight/$nwidth"
			fi

			if [[ "$nwidth" ]] && ! check_int "$nwidth"; then
				fatal "Failed to read positive int value ${bb}$nwidth"; return
			fi
			if [[ "$nheight" ]] && ! check_int "$nheight"; then
				fatal "Failed to read positive int value ${bb}$nheight"; return
			fi

			[[ "$nwidth"  == 0 ]] && unset nwidth
			[[ "$nheight" == 0 ]] && unset nheight

			if [[      "$nwidth" && ! "$nheight" ]]; then
				nwidth=$((  $width  * $nwidth/$width ))
				nheight=$(( $height * $nwidth/$width ))
			elif [[ ! "$nwidth" &&    "$nheight" ]]; then
				nwidth=$((  $width  * $nheight/$height ))
				nheight=$(( $height * $nheight/$height ))
			fi

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
			if [[ "$need_scaling" ]]; then
				nwidth=$( echo "scale=40; $width*$sfactor" | $bc )
				nwidth=$( echo "scale=0; ($nwidth+1)/1" | $bc )
				nheight=$( echo "scale=40; $height*$sfactor" | $bc )
				nheight=$( echo "scale=0; ($nheight+1)/1" | $bc )
			fi
		fi

		# dimensions have been changed, make sure they are multiples of 16
		scale_info=( $(scale16 "$width" "$height" "$nwidth" "$nheight" "$aspect_ratio") )
		nwidth=${scale_info[0]}
		nheight=${scale_info[1]}

		# make sure the new dimensions are sane
		if (( $nwidth * $nheight <= 0 )); then
			nwidth="$width"
			nheight="$height"
		fi
	fi

	echo "$nwidth $nheight"

}

# scale dimensions to nearest (lower/upper) multiple of 16
function scale16() {
	local orig_width="$1"; shift;
	local orig_height="$1"; shift;
	local width="$1"; shift;
	local height="$1"; shift;
	local aspect_ratio="$1"; shift;
	local divisor=16

	# if the original dimensions are not multiples of 16, no amount of scaling
	# will bring us to an aspect ratio where the smaller dimensions are
	if (( ($orig_width%$divisor) + ($orig_height%$divisor) != 0 )); then
		width="$orig_width"
		height="$orig_height"
	else

		step=-1
		unset completed
		while [[ ! "$completed" ]]; do
			step=$(( $step + 1 ))

			local up_step=$(( $width + ($step * $divisor) ))
			local down_step=$(( $width - ($step * $divisor) ))
			for x_step in $down_step $up_step; do
				local x_width=$(( $x_step - ($x_step % $divisor) ))
				local x_height=$( echo "scale=0; $x_width*$aspect_ratio/1" | $bc )
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

# get container options and decide on codecs
function container_opts() {
	local container="$1"; shift;
	local acodec="$1"; shift;
	local vcodec="$1"; shift;

	local audio_codec="mp3"
	local video_codec="h264"
	local ext="avi"
	local opts="avi"

	if [[ "$container" = "avi" ]] || [[ "$container" = "mkv" ]] || \
		[[ "$container" = "ogm" ]]; then
		$true
	elif [[ "$container" = "mp4" ]]; then
		audio_codec="aac"
		video_codec="h264"

	# use lavf muxing
	else
		$(echo $container | $egrep '(asf|au|dv|flv|ipod|mov|mpg|nut|rm|swf)' &>/dev/null)
		if [[ $? == 0 ]]; then
			ext="$container"
			opts="lavf -lavfopts format=$container"

			if [[ "$container" = "flv" ]]; then
				audio_codec="mp3"
				video_codec="flv"
			fi

		else
			fatal "Unrecognized container: ${bb}$container"; return
		fi
	fi

	[[ "$acodec" ]] && audio_codec="$acodec"
	[[ "$vcodec" ]] && video_codec="$vcodec"

	echo "$audio_codec $video_codec $ext $opts"
}

# get audio codec options
function acodec_opts() {
	local container="$1"; shift;
	local codec="$1"; shift;
	local orig_bitrate="$1"; shift;
	local get_bitrate="$1"; shift

	local opts=
	if [[ "$container" = "flv" ]]; then
		opts=" -srate 44100"  # flv supports 44100, 22050, 11025
	fi

	if [[ "$codec" = "copy" ]]; then
		local bitrate=$orig_bitrate
		opts="copy"
	elif [[ "$codec" = "mp3" ]]; then
		local bitrate=160
		opts="mp3lame -lameopts vbr=3:abr=$bitrate:q=3$opts"
	elif [[ "$codec" = "aac" ]]; then
		local bitrate=192
		opts="faac -faacopts br=$bitrate:mpeg=4:object=2 -channels 2$opts"

	# use lavc codec
	else
		local bitrate=224	# mencoder manpage default
		$(echo $codec | \
			$egrep '(ac3|flac|g726|libamr_nb|libamr_wb|mp2|roq_dpcm|sonic|sonicls|vorbis|wmav1|wmav2)' &>/dev/null)
		if [[ $? == 0 ]]; then
			opts="lavc -lavcopts abitrate=$bitrate:acodec=$codec$opts"

		else
			fatal "Unrecognized audio codec: ${bb}$codec"; return
		fi
	fi

	if [[ "$get_bitrate" = "y" ]]; then
		echo "$bitrate"
	else
		echo "$opts"
	fi
}

# get video codec options
function vcodec_opts() {
	local codec="$1"; shift;
	local twopass="$1"; shift;
	local pass="$1"; shift;
	local bitrate="$1"; shift;
	
	local opts=
	if [[ "$codec" = "copy" ]]; then
		opts="copy"
	elif [[ "$codec" = "h264" ]]; then
		opts="subq=5:frameref=2"
		if [[ "$twopass" ]]; then
			if [[ $pass -eq 1 ]]; then
				opts="pass=1:subq=1:frameref=1"
			elif [[ $pass -eq 2 ]]; then
				opts="pass=2:$opts"
			fi
		fi
		opts="x264 -x264encopts $opts:partitions=all:weight_b:bitrate=$bitrate:threads=auto"
	elif [[ "$codec" = "xvid" ]]; then
		if [[ "$twopass" ]]; then
			if [[ $pass -eq 1 ]]; then
				opts="pass=1:"
			elif [[ $pass -eq 2 ]]; then
				opts="pass=2:"
			fi
		fi
		opts="xvid -xvidencopts ${opts}bitrate=$bitrate"

	# use lavc codec
	else
		if [[ "$twopass" ]]; then
			if [[ $pass -eq 1 ]]; then
				opts="vpass=1:"
			elif [[ $pass -eq 2 ]]; then
				opts="vpass=2:"
			fi
		fi

		$(echo $codec | $egrep '(asv1|asv2|dvvideo|ffv1|flv|h261|h263|h263p|huffyuv|libtheora|ljpeg|mjpeg|mpeg1video|mpeg2video|mpeg4|msmpeg4|msmpeg4v2|roqvideo|rv10|snow|svq1|wmv1|wmv2)' &>/dev/null)
		if [[ $? == 0 ]]; then
			opts="lavc -lavcopts ${opts}vbitrate=$bitrate:vcodec=$codec"

		else
			fatal "Unrecognized video codec: ${bb}$codec"; return
		fi
	fi

	echo "$opts"
}

# run encode and print updates
function run_encode() {
	local cmd="$1"; shift;
	local title="$1"; shift;
	local ext="$1"; shift;
	local length="$1"; shift;
	local twopass="$1"; shift;
	local pass="$1"; shift;
	
	# Set output and logging depending on number of passes
	
	local output_file="\"$(escape_chars "${title}.${ext}.partial")\""
	local base="$(basename "$(escape_chars "$title")")"
	local logfile="logs/${base}.log"
	
	if [[ "$twopass" ]]; then
		if [[ $pass -eq 1 ]]; then
			output_file="/dev/null"
			logfile="$logfile.pass1"
		elif [[ $pass -eq 2 ]]; then
			logfile="$logfile.pass2"
		fi
	else
		pass="-"
	fi
	
	cmd="$cmd -o $output_file"
	
	# Print initial status message
	
	local status="${r}[$pass] Encoding       "
	echo -en "${status}\r"
	
	# Execute encoder in the background
	
	( echo $cmd; $bash -c "$cmd" ) &> "$logfile" &
	local pid=$!
	
	# Write mencoder's ETA estimate
	
	local start_time=$($date +%s)
	while $ps $pid &> /dev/null; do
		local line=$([ -e "$logfile" ] && $tail -n15 "$logfile" | \
			$grep -a "Trem:" | $tail -n1)

		local perc=$(echo "$line" | $sed 's|.*(\([0-9 %]*\)).*|\1|g' | $tr -d " ")
		local secs=$(echo "$line" | $sed 's|.*Pos:[ ]*\([0-9]*\).*|\1|g' | $tr -d " ")
		if [[ "$secs" ]]; then
			[[ "$perc" = "0%" ]] && perc="$(( 100 * $secs / $length ))%"
			secs="${secs}s"
		else
			unset secs
			unset perc
		fi
		local fps=$(echo "$line" | $sed 's|.*\( .*fps\).*|\1|g' | $tr -d " ")
		local size=$(echo "$line" | $sed 's|.*\( .*mb\).*|\1|g' | $tr -d " ")
		[[ "$size" = "0mb" ]] && size="??mb"
		local eta=$( echo "$line" | $sed 's|.*\( .*min\).*|\1|g' | $tr -d " ")
		[[ "$eta" ]] && eta="-${eta}"

		size=$(fill "$size" 6)
		fps=$(fill "$fps" 7)
		secs=$(fill "$secs" 6)
		perc=$(fill "$perc" 4)

		local ela=$(( ( $($date +%s) - $start_time ) / 60 ))
		local str="${status}   ${it2}${perc}${r}   ${secs}   ${it}${fps}${r}   ${size}     "
		echo -ne "${str}${cela}+${ela}min${r}  ${ceta}${eta}${r}    \r"
		$sleep $timer_refresh
	done
	
	# Report exit code
	
	wait $pid
	if [[ $? = 0 ]]; then
		echo -e "${str}[ ${ok}done${r} ]             "
	else
		echo -e "${str}[ ${e}failed${r} ] check log"
	fi
}

function remux_container() {
	local root="$1"; shift;
	local ext="$1"; shift;
	local fps="$1"; shift;
	local container="$1"; shift;
	local acodec="$1"; shift;
	local vcodec="$1"; shift;

	$(echo $container | $egrep '(mp4|mkv|ogm)' &>/dev/null)
	if [[ $? == 0 ]]; then

		local pre="
			if [[ -e \"$(escape_chars "$root.$container")\" ]]; then \
				$rm \"$(escape_chars "$root.$container")\"; \
			fi &&
			$mplayer \"$(escape_chars "$root.$ext")\" -dumpaudio \
				-dumpfile \"$(escape_chars "$root.$acodec")\" &&
			$mplayer \"$(escape_chars "$root.$ext")\" -dumpvideo \
				-dumpfile \"$(escape_chars "$root.$vcodec")\""

		local post="
			$rm \"$(escape_chars "$root.$acodec")\" &&
			$rm \"$(escape_chars "$root.$vcodec")\" &&
			$rm \"$(escape_chars "$root.$ext")\""

		if [[ "$container" = "mp4" ]]; then
			local cmd="$pre &&
				$mp4creator -create=\"$(escape_chars "$root.$acodec")\" \
					\"$(escape_chars "$root.$container")\" &&
				$mp4creator -create=\"$(escape_chars "$root.$vcodec")\" \
					-rate=$fps \"$(escape_chars "$root.$container")\" &&
				$mp4creator -hint=1 \"$(escape_chars "$root.$container")\" &&
				$mp4creator -hint=2 \"$(escape_chars "$root.$container")\" &&
				$mp4creator -optimize \"$(escape_chars "$root.$container")\" &&
				$post"
		elif [[ "$container" = "mkv" ]]; then
			local cmd="
				$mkvmerge -o \"$(escape_chars "$root.$container")\" \
					\"$(escape_chars "$root.$ext")\" &&
				$rm \"$(escape_chars "$root.$ext")\""
		elif [[ "$container" = "ogm" ]]; then
			local cmd="
				$ogmmerge -o \"$(escape_chars "$root.$container")\" \
					\"$(escape_chars "$root.$ext")\" &&
				$rm \"$(escape_chars "$root.$ext")\""
		fi

		# Set logging depending on number of passes

		local base="$(basename "$(escape_chars "$title")")"
		local logfile="logs/${base}.remuxlog"

		# Print initial status message

		local status="${r}[.] Remuxing                                               "
		echo -en "${status}\r"

		# Execute remux in the background

		( echo $cmd; $bash -c "$cmd" ) &> "$logfile" &
		local pid=$!

		# Report exit code

		wait $pid
		if [[ $? = 0 ]]; then
			echo -e "${status}[ ${ok}done${r} ]             "
		else
			echo -e "${status}[ ${e}failed${r} ] check log"
		fi
	fi
}


# initialize command variables
init_cmds
