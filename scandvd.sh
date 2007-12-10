#!/bin/bash
#
# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.


# load constants and functions
p=$(dirname $(readlink -f $0)); . $p/lib.sh

echo -e "${wh}{( --- scandvd.sh $version --- )}${pl}"

while getopts "d:q:i:" opts; do
	case $opts in
		d ) dvd_device=$OPTARG;;
		q ) dvd_device=$OPTARG;dvdisdir="-q ";;
		i ) dvd_device=$OPTARG;dvdisdir="-q ";;
		* ) echo -e " Usage:  ${wh}scandvd.sh [-d ${gr}/dev/dvd${wh} | -q ${gr}/path${wh} | -i ${gr}disc.iso ${wh}]${pl}"; exit 1;;
	esac
done

if [ $dvd_device ]; then
	dvd_device="\"$dvd_device\""
fi

cmd="lsdvd -avs $dvdisdir $dvd_device > ${tmpdir}/lsdisc 2> ${tmpdir}/lsdisc.err"

bash -c "$cmd"
if [ $? != 0 ]; then
	echo -en "${re}" ; cat "${tmpdir}/lsdisc.err"; echo -en ${pl}
	rm ${tmpdir}/lsdisc* &> /dev/null
	exit 1
fi


titles=$(cat ${tmpdir}/lsdisc | egrep "^Title" | awk '{ print $2 }' | sed 's|,||g')

echo "Scanning DVD for titles..."

for i in $titles; do
	cat ${tmpdir}/lsdisc | sed -n "/^Title: $i/, /^$/p" > ${tmpdir}/lstitle
	length=$(cat ${tmpdir}/lstitle | egrep "^Title: $i" | awk '{ print $4 }' | sed 's|\(.*\)\..*|\1|g')
#	audio=$(cat ${tmpdir}/lstitle | egrep "Audio:" | awk '{ printf $4 "=" $21 " " }' | xargs)
	audio=$(cat ${tmpdir}/lstitle | egrep "Audio:" | awk '{ print $4 }' | xargs)
	subtitles=$(cat ${tmpdir}/lstitle | egrep "Subtitle:" | awk '{ print $4 }' | xargs)

	echo -en   "${pl}${i}"
	echo -en "  ${wh}length: ${gr}${length}"
	echo -en "  ${wh}audio: ${pl}${audio}"
	if [ "$subtitles" ]; then echo -en "  ${wh}subtitles: ${pl}${subtitles}"; fi
	echo
done

echo -e "${pl}\nTo watch a title:"
echo -e " ${wh}mplayer       dvd://${gr}01${wh}     -alang ${gr}en${wh}  -slang ${gr}en/off"

echo -e "${pl}To rip titles:"
echo -e " ${wh}undvd.sh      -t ${gr}01,02,03${wh}  -a ${gr}en${wh}      -s ${gr}en/off${pl}"

rm ${tmpdir}/lsdisc* ${tmpdir}/lstitle* &> /dev/null
