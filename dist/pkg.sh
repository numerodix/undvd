#!/bin/bash

v="$1"
action="$2"

dist=$(cd $(dirname $0); pwd)

proj=undvd
proj_url="http://sourceforge.net/projects/undvd/"

name=$(git-config user.name)
email=$(git-config user.email)

tag=$v
if [ ! $v ]; then
	echo "Usage: $0 <version> [action]"
	exit 1
fi

if [ $v = "git" ]; then
	v="9999"
	tag=HEAD
fi



function tarball() {
	local dest="$1"
	local nopack="$2"
	mkdir -p $dest
	files=$(find . -maxdepth 1 -type f | xargs)
	git-archive --prefix=$proj-$v/ $tag $files > $dest/$proj-$v.tar
	if [ ! $nopack ]; then
		gzip $dest/$proj-$v.tar
	fi
}

function gentoo() {
	local dest="$1"
	mkdir -p $dest
	cp $dist/$proj.ebuild $dest/$proj-$v.ebuild
}

function ubuntu() {
	local dest="$1"
	mkdir -p $dest; dest=$(cd $dest; pwd)
	
	mkdir -p $dest/tmp
	tarball $dest/tmp
	
	( cd $dest/tmp ;
	tar zxvf $proj-$v.tar.gz ;
	cd $proj-$v ;
	
	# patch stupid dh_make to make it non-interactive
	cp $(which dh_make) $dest/tmp ;
	sed -i "s,my \$dummy = <STDIN>;,,g" $dest/tmp/dh_make ;
	
	# run dh_make to generate boilerplate
	export DEBFULLNAME="$name" ;
	$dest/tmp/dh_make -s -c gpl \
		-e "$email" -f ../$proj-$v.tar.gz ;
	cd debian ;
	
	# remove obsolete files *sigh*
	rm README.Debian *.{ex,EX}
	
	# patch control file
	sed -i "s|Section: .*|Section: multiverse/graphics|g" control ;
	sed -i "s|Architecture: .*|Architecture: all|g" control ;
	sed -i "s|^Depends: .*|Depends: mencoder, lsdvd, bash, coreutils, gawk\nSuggests: libdvdcss2|g" control ;
	sed -i "s|Description: .*|Description: Simple dvd ripping command line app|g" control ;
	sed -i "s|<insert long.*|undvd is dvd ripping made *simple* with an easy interface to mencoder with sensible default settings that give good results. For those times you just want to rip a movie and not consider thousands of variables.|g" control ;
	
	# patch changelog file
	sed -i "s|$v-1|$v-0ubuntu1|g" changelog ;
	
	# patch copyright file
	sed -i "s|It was downloaded from .*|It was downloaded from $proj_url|g" copyright ;
	sed -i "s|.*<put author|\t$name <$email>|g" copyright ;
	sed -i "s|.*<likewise for another author.*||g" copyright ;
	sed -i "s|.*<Copyright (C) .*|\tCopyright (C) $(date +%Y) $name|g" copyright ;
	
	# build the package
	cd .. ;
	dpkg-buildpackage -rfakeroot )
	
	cp $dest/tmp/${proj}_$v-0ubuntu1_all.deb $dest
	
	rm -rf $dest/tmp
}

function fedora() {
	local dest="$1"
	mkdir -p $dest
	
	mkdir -p $dest/tmp
	
	# point macrofiles field in local .rpmrc to local .rpmmacros
	macrofiles=$(rpmbuild --showrc | grep macrofiles)
	echo "$macrofiles:$(cd $dest/tmp; pwd)/rpmmacros" > $dest/tmp/rpmrc
	
	# set rpmbuild path in local .rpmmacros
	echo "%_topdir      $(cd $dest/tmp; pwd)/rpmbuild" > $dest/tmp/rpmmacros
	
	# create dirs expected by rpmbuild
	for d in RPMS SOURCES SPECS SRPMS BUILD; do
		mkdir -p $dest/tmp/rpmbuild/$d
	done
	
	# place project tarball in SOURCES dir
	tarball $dest/tmp/rpmbuild/SOURCES
	
	# find system rpmrc files and append our local .rpmrc
	rcfiles="$(cd $dest/tmp; pwd)/rpmrc"
	for f in /usr/lib/rpm/rpmrc /usr/lib/rpm/red‐hat/rpmrc /etc/rpmrc ~/.rpmrc; do
		[ -e "$f" ] && rcfiles="$f:$rcfiles"
	done
	
	# copy project .spec file and reset BuildRoot path
	cp $dist/$proj.spec $dest/tmp
	sed -i "s|BuildRoot: .*|BuildRoot: $(cd $dest/tmp; pwd)/%{name}-buildroot|g" $dest/tmp/$proj.spec
	
	# build package locally given .spec file and local .rpmrc
	rpmbuild -ba $dest/tmp/$proj.spec --rcfile "$rcfiles"
	
	cp $dest/tmp/rpmbuild/RPMS/noarch/$proj-$v-1.noarch.rpm $dest
	
	rm -rf $dest/tmp
}

function package() {
	local dest="$1"
	mkdir -p $dest
		
	mkdir -p $dest/$proj-$v/gentoo
	gentoo $dest/$proj-$v/gentoo
	
	mkdir -p $dest/$proj-$v/ubuntu
	ubuntu $dest/$proj-$v/ubuntu
	
	mkdir -p $dest/$proj-$v/fedora
	fedora $dest/$proj-$v/fedora
	
#	mkdir -p undvd-$v/gentoo
#	cp dist/undvd.ebuild undvd-$v/gentoo/undvd-$v.ebuild
	
#	mkdir -p undvd-$v/ubuntu
#	mv dist/undvd_$v-0ubuntu1_all.deb undvd-$v/ubuntu
	
#	mkdir -p undvd-$v/fedora
#	sudo mkdir -p /usr/src/rpm/SOURCES
#	sudo cp undvd-$v.tar.gz /usr/src/rpm/SOURCES
#	sudo rpmbuild -ba dist/undvd.spec
#	cp /usr/src/rpm/RPMS/noarch/undvd-$v-1.noarch.rpm undvd-$v/fedora
	
#	rm undvd-$v.tar.gz
	
	tarball $dest "1"
	
	# zip it up
#	files=$(find . -maxdepth 1 -type f | xargs)
#	git-archive --prefix=undvd-$v/ $tag $files > undvd-$v.tar

	( cd $dest ; 
	tar cvf $proj-$v.tar.2 $proj-$v ;
	tar -Af $proj-$v.tar $proj-$v.tar.2 ;
	rm $proj-$v.tar.2 ;
	gzip $proj-$v.tar )
	
#	tar cvf undvd-$v.tar.2 undvd-$v
#	tar -Af undvd-$v.tar undvd-$v.tar.2
#	rm undvd-$v.tar.2
#	gzip undvd-$v.tar
	
	rm -rf $dest/$proj-$v
}


if [ "$action" = "fedora" ]; then
	fedora pub
elif [ "$action" = "gentoo" ]; then
	gentoo pub
elif [ "$action" = "ubuntu" ]; then
	ubuntu pub
else
	package pub
fi