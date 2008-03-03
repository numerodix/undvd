#!/bin/bash
#
# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.
#
# More info: http://www.matusiak.eu/numerodix/blog/index.php/2007/01/30/undvd-dvd-ripping-made-easy/


# load constants and functions
p=$(dirname $(readlink -f $0)); . $p/lib.sh

echo -e "${h1}{( --- undvd.sh $version --- )}${r}"

usage="Usage:  ${b}undvd.sh -t ${bb}01,02,03${b} -a ${bb}en${b} -s ${bb}es${b} ${r}[${b}-d ${bb}/dev/dvd${r}] [${b}more options${r}]\n
  -t   titles to rip (comma separated)
  -a   audio language (two letter code, eg. ${bb}en${r})
  -s   subtitle language (two letter code or ${bb}off${r})\n
  -d   dvd device to rip from (default is ${bb}/dev/dvd${r})
  -q   dvd directory to rip from
  -i   dvd iso image to rip from\n
  -e   exit after this many seconds (usually for testing)\n
  -c   do sanity check (check for missing tools)
  -z   <show advanced options>"

adv_usage="Advanced usage:  ${b}undvd.sh ${r}[${b}standard options${r}] [${b}advanced options${r}]
  -o   output file size in mb (integer value)
  -1   force 1-pass encoding
  -2   force 2-pass encoding
  -u   dvd is encrypted (requires libdvdcss to read)
  -n   no disc cloning (encode straight from the dvd, save disk space)
  -r   scale video to width (integer value), ${bb}0${r} for no scaling
  -f   use picture smoothing filter
  -x   use xvid compression (faster, slightly lower quality)
  -D   dry run (display encoding parameters without encoding)"

while getopts "t:a:s:e:d:q:i:o:r:12unfxDcz" opts; do
	case $opts in
		t ) titles=$(echo $OPTARG | $sed 's|,| |g');;
		a ) alang=$OPTARG;;
		s ) slang=$OPTARG;;
		
		d ) dvd_device=$OPTARG;;
		q ) dvdisdir="y";mencoder_source="$OPTARG";;
		i ) skipclone="y";mencoder_source="$OPTARG";;
		
		e ) end=$OPTARG;;
		
		o ) target_size="$OPTARG";;
		1 ) target_passes="1";;
		2 ) target_twopass=y;target_passes="2";;
		u ) encrypted="y";;
		n ) skipclone="y";mencoder_source="$dvd_device";;
		r ) custom_scale="$OPTARG";;
		f ) prescale="spp,";postscale=",hqdn3d";;
		x ) video_codec="xvid";acodec="$lame";;
		D ) dry_run="y";;
		
		c ) init_cmds "y"; exit;;
		z ) echo -e "$adv_usage"; exit;;
		* ) echo -e "$usage"; exit 1;;
	esac
done


if [ ! "$end" ]; then
	endpos=""
else
	endpos="-endpos $end"
fi


if [ ! "$titles" ]; then
	echo -e "${e}No titles to rip, exiting${r}"
	echo -e "$usage"
	exit 1
fi

if [ ! "$alang" ]; then
	echo -e "${e}No audio language selected, exiting${r}"
	echo -e "$usage"
	exit 1
fi

if [ ! "$slang" ]; then
	echo -e "${e}No subtitle language selected, exiting (use 'off' if you don't want any)${r}"
	echo -e "$usage"
	exit 1
fi


$mkdir -p logs
if [ $? != 0 ] ; then
	echo -e "${e}Could not write to $PWD, exiting${r}"
	exit 1
fi

if [ ! "$dvdisdir" ] && [ ! "$skipclone" ]; then
	echo -en " * Cloning dvd to disk first... "
	
	if [ "$encrypted" ]; then
		mencoder_source="disc"
		clone_vobcopy "$dvd_device" "$mencoder_source"
	else
		clone_dd "$dvd_device" "$disc_image"
	fi
	
	if [ $? != 0 ] ; then
		echo -e "${e}\nFailed, check log${r}"
		exit 1
	fi
	echo -e "${ok}done${r}"
fi


# Display dry-run status

if [ "$dry_run" ]; then
	echo -e " * Performing dry-run on title(s) ${bb}$titles${r}"
	display_title_line "dims" "fps" "len" "bpp" "bitrate" "p" "codec" "size" "title" "header"
fi

for title in $titles; do
	
	# Display encode status

	if [ ! "$dry_run" ]; then
		echo -en " * Now ripping title ${bb}$title${r}, with audio ${bb}$alang${r} and subtitles ${bb}$slang${r}"
		if [ "$end" ]; then
			echo -e " ${r}(only first ${bb}${end}${r}s)"
		else
			echo
		fi
	fi
	
	
	# Extract information from the title
	
	info=($(examine_title "" "$mencoder_source" "$title"))
	width=${info[0]}
	height=${info[1]}
	fps=${info[2]}
	length=${info[3]}
	#bitrate=${info[4]}

	# Find out how to scale the dimensions
	
	scale_info=($(title_scale "$width" "$height" "$custom_scale"))
	width=${scale_info[0]}
	height=${scale_info[1]}
	scale="scale=$width:$height"

	# Estimate filesize of audio

	audio_size=$(compute_media_size "$length" "$standard_audio_bitrate")

	# Decide bpp

	if [ "$target_size" ]; then
		video_size=$(( $target_size - $audio_size ))
		[[ "0" > "$video_size" ]] && video_size=1
		bpp=$(compute_bpp "$width" "$height" "$fps" "$length" "$video_size")	
	else
		bpp=$(set_bpp "$video_codec" "$target_twopass")
	fi
	
	# Reset the number of passes based on the bpp
	
	unset twopass
	if [ "$target_passes" ]; then
		passes="$target_passes"
	else
		passes=$(set_passes "$video_codec" "$bpp")
	fi
	[ "$passes" = "2" ] && twopass=y

	# Compute bitrate
	
	bitrate=$(compute_bitrate "$width" "$height" "$fps" "$length" "$bpp")

	# Estimate output size
	unset output_size
	if [ "$target_size" ]; then
		output_size="$target_size"
	else
		video_size=$(compute_media_size "$length" "$bitrate")
		output_size=$(( $video_size+$audio_size ))
	fi



	if [ "$dry_run" ]; then

		# Dry run

		filesize="$output_size"
		format="$video_codec"
		display_title $width $height $fps $length $bpp $bitrate $passes $format $filesize $title

	else
	
		# Encode video
		
		pass=0
		for p in $($seq $passes); do
			pass=$(( $pass + 1 ))
		
			vcodec=$(vcodec_opts "$video_codec" "$twopass" "$pass" "$bitrate")
			
			cmd="time \
			$nice -n20 \
			$mencoder -v \
			dvd://${title} \
			-dvd-device '$mencoder_source' \
			-alang ${alang} \
			-slang ${slang} \
			${crop} \
			${endpos} \
			-vf ${prescale}${scale}${postscale} \
			-ovc ${vcodec} \
			-oac ${acodec}"
			run_encode "$cmd" "$title" "$twopass" "$pass"
		done
		
		[ -f ${title}.avi.partial ] && $mv ${title}.avi.partial ${title}.avi
		$rm divx2pass* 2> /dev/null

	fi

done
