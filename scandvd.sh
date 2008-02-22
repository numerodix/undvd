#!/bin/bash
#
# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.


# load constants and functions
p=$(dirname $(readlink -f $0)); . $p/lib.sh

echo -e "${h1}{( --- scandvd.sh $version --- )}${r}"

usage="Usage:  ${b}scandvd.sh ${r}[${b}-d ${bb}/dev/dvd${r} | ${b}-q ${bb}/path${r} | ${b}-i ${bb}disc.iso ${r}]\n
  -d   dvd device to read from (default is ${bb}/dev/dvd${r})
  -q   dvd directory to read from
  -i   dvd iso image to read from"

while getopts "d:q:i:" opts; do
	case $opts in
		d ) dvd_device=$OPTARG;;
		q ) dvd_device=$OPTARG;dvdisdir="-q ";;
		i ) dvd_device=$OPTARG;dvdisdir="-q ";;
		* ) echo -e "$usage"; exit 1;;
	esac
done

if [ "$dvd_device" ]; then
	dvd_device="\"$dvd_device\""
fi

cmd="$lsdvd -avs $dvdisdir $dvd_device > ${tmpdir}/lsdisc 2> ${tmpdir}/lsdisc.err"

$bash -c "$cmd"
if [ $? != 0 ]; then
	echo -en "${e}" ; $cat "${tmpdir}/lsdisc.err"; echo -en ${r}
	$rm ${tmpdir}/lsdisc* &> /dev/null
	echo -e "$usage"
	exit 1
fi


titles=$($cat ${tmpdir}/lsdisc | $egrep "^Title" | $awk '{ print $2 }' | $sed 's|,||g')

echo "Scanning DVD for titles..."

for title in $titles; do
	$cat ${tmpdir}/lsdisc | $sed -n "/^Title: $title/, /^$/p" > ${tmpdir}/lstitle
	length=$($cat ${tmpdir}/lstitle | $egrep "^Title: $title" | $awk '{ print $4 }' | $sed 's|\(.*\)\..*|\1|g')
#	audio=$($cat ${tmpdir}/lstitle | $egrep "Audio:" | $awk '{ printf $4 "=" $21 " " }' | $xargs)
	audio=$($cat ${tmpdir}/lstitle | $egrep "Audio:" | $awk '{ print $4 }' | $xargs)
	subtitles=$($cat ${tmpdir}/lstitle | $egrep "Subtitle:" | $awk '{ print $4 }' | $xargs)

	echo -en   "${b}${title}"
	echo -en "  ${r}length: ${bb}${length}"
	echo -en "  ${r}audio: ${bb}${audio}"
	if [ "$subtitles" ]; then echo -en "  ${r}subtitles: ${bb}${subtitles}${r}"; fi
	echo
done

echo -e "${r}\nTo watch a title:"
echo -e " ${b}mplayer       dvd://${bb}01${b}     -alang ${bb}en${b}  -slang ${bb}en/off${r}"

echo -e "${r}To rip titles:"
echo -e " ${b}undvd.sh      -t ${bb}01,02,03${b}  -a ${bb}en${b}      -s ${bb}en/off${r}"

$rm ${tmpdir}/lsdisc* ${tmpdir}/lstitle* &> /dev/null
