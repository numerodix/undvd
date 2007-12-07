#!/bin/bash

v=$1
tag=$v
if [ ! $v ]; then
	echo "Usage: $0 <version>"
	exit 1
fi

if [ $v = "git" ]; then
	v="9999"
	tag=HEAD
fi

git-archive --prefix=undvd-$v/ $tag | gzip > undvd-$v.tar.gz 

# ubuntu
mkdir -p deb
cp undvd-$v.tar.gz deb
cd deb
tar zxvf undvd-$v.tar.gz
cd undvd-$v

cp $(which dh_make) ../../deb
sed -i "s,my \$dummy = <STDIN>;,,g" ../../deb/dh_make

export DEBFULLNAME="Martin Matusiak"
../../deb/dh_make -s -c gpl \
	-e $(git-config user.email) -f ../undvd-$v.tar.gz
cd debian

sed -i "s,Section: unknown,Section: multiverse/graphics,g" control
sed -i "s,Architecture: any,Architecture: all,g" control
sed -i "s|Depends: .*|Depends: mencoder, lsdvd, bash, coreutils, gawk, libdvdcss2|g" control
sed -i "s,Description: .*,Description: Simple dvd ripping command line app,g" control
sed -i "s,<insert long.*,undvd is dvd ripping made *simple* with an easy interface to mencoder with sensible default settings that give good results.  For those times you just want to rip a movie and not consider thousands of variables.,g" control

sed -i "s,9999-1,9999-0ubuntu1,g" changelog

cd ..
dpkg-buildpackage -rfakeroot
cd ..
cd ..

cp deb/undvd_$v-0ubuntu1_all.deb dist
rm -rf deb

rm undvd-$v.tar.gz


# package
mkdir -p undvd-$v/gentoo
cp dist/undvd-$v.ebuild undvd-$v/gentoo

mkdir -p undvd-$v/ubuntu
mv dist/undvd_$v-0ubuntu1_all.deb undvd-$v/ubuntu

files=$(find . -maxdepth 1 -type f | xargs)
git-archive --prefix=undvd-$v/ $tag $files > undvd-$v.tar
tar -rvf undvd-$v.tar undvd-$v
gzip undvd-$v.tar

rm -rf undvd-$v
