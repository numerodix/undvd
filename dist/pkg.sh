#!/bin/bash

v="$1"
r=1
action="$2"

dist=$(cd $(dirname $0); pwd)

tag=$v
if [ ! $v ]; then
	echo "Usage: $0 <version> [action]"
	exit 1
fi

if [ $v = "git" ]; then
	v="9999"
	tag=HEAD
fi

proj=undvd
proj_url="http://sourceforge.net/projects/undvd/"
proj_tarball="http://www.opendesktop.org/content/$proj-$v.tar.gz"

desc_short="Simple dvd ripping command line app"
desc_long="undvd is dvd ripping made *simple* with an easy interface to\n \
mencoder with sensible default settings that give good results. For those\n \
times you just want to rip a movie and not consider thousands of variables."

deb_lic="gpl"
rpm_lic="GPL"

deb_arch="all"
rpm_arch="noarch"

deb_deps="mencoder, lsdvd, bash, coreutils, gawk"
deb_suggests="libdvdcss2"

deb_section="multiverse/graphics"
rpm_group="Applications/Multimedia"

myname=$(git-config user.name)
myemail=$(git-config user.email)



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
	export DEBFULLNAME="$myname" ;
	export DEBEMAIL="$myemail" ;
	$dest/tmp/dh_make -s -c $deb_lic \
		-e "$myemail" -f ../$proj-$v.tar.gz ;
	cd debian ;

	# remove obsolete files *sigh*
	rm README.Debian *.{ex,EX}
	
	# patch control file
	sed -i "s|Section: .*|Section: $deb_section|g" control ;
	sed -i "s|Architecture: .*|Architecture: $deb_arch|g" control ;
	sed -i "s|^Depends: .*|Depends: $deb_deps\nSuggests: $deb_suggests|g" control ;
	sed -i "s|Description: .*|Description: $desc_short|g" control ;
	sed -i "s|<insert long.*|$desc_long|g" control ;
	
	# patch changelog file
	sed -i "s|$v-1|$v-0ubuntu$r|g" changelog ;
	
	# patch copyright file
	sed -i "s|It was downloaded from .*|It was downloaded from $proj_url|g" copyright ;
	sed -i "s|.*<put author|\t$myname <$myemail>|g" copyright ;
	sed -i "s|.*<likewise for another author.*||g" copyright ;
	sed -i "s|.*<Copyright (C) .*|\tCopyright (C) $(date +%Y) $myname|g" copyright ;
	
	# build the package
	cd .. ;
	dpkg-buildpackage -rfakeroot )
	
	cp $dest/tmp/${proj}_$v-0ubuntu1_$deb_arch.deb $dest
	exit
	rm -rf $dest/tmp
}

function fedora() {
	local dest="$1"
	mkdir -p $dest; dest=$(cd $dest; pwd)
	
	mkdir -p $dest/tmp
	
	# point macrofiles field in local .rpmrc to local .rpmmacros
	macrofiles=$(rpmbuild --showrc | grep macrofiles)
	echo "$macrofiles:$dest/tmp/rpmmacros" > $dest/tmp/rpmrc
	
	# set rpmbuild path in local .rpmmacros
	echo "%_topdir      $dest/tmp/rpmbuild" > $dest/tmp/rpmmacros
	
	# create dirs expected by rpmbuild
	for d in RPMS SOURCES SPECS SRPMS BUILD; do
		mkdir -p $dest/tmp/rpmbuild/$d
	done
	
	# place project tarball in SOURCES dir
	tarball $dest/tmp/rpmbuild/SOURCES
	
	# find system rpmrc files and append our local .rpmrc
	rcfiles="$dest/tmp/rpmrc"
	for f in /usr/lib/rpm/rpmrc /usr/lib/rpm/red‐hat/rpmrc /etc/rpmrc ~/.rpmrc; do
		[ -e "$f" ] && rcfiles="$f:$rcfiles"
	done
	
	# copy project .spec file and patch spec
	cp $dist/$proj.spec $dest/tmp
	sed -i "s|Summary: .*|Summary: $desc_short|g" $dest/tmp/$proj.spec
	sed -i "s|Name: .*|Name: $proj|g" $dest/tmp/$proj.spec
	sed -i "s|Version: .*|Version: $v|g" $dest/tmp/$proj.spec
	sed -i "s|Release: .*|Release: $r|g" $dest/tmp/$proj.spec
	sed -i "s|License: .*|License: $rpm_lic|g" $dest/tmp/$proj.spec
	sed -i "s|Group: .*|Group: $rpm_group|g" $dest/tmp/$proj.spec
	sed -i "s|BuildRoot: .*|BuildRoot: $dest/tmp/%{name}-buildroot|g" $dest/tmp/$proj.spec
	sed -i "s|Source: .*|Source: $proj_tarball|g" $dest/tmp/$proj.spec
	sed -i "s|BuildArch: .*|BuildArch: $rpm_arch|g" $dest/tmp/$proj.spec

	# build package locally given .spec file and local .rpmrc
	rpmbuild -ba $dest/tmp/$proj.spec --rcfile "$rcfiles"
	
	cp $dest/tmp/rpmbuild/RPMS/$rpm_arch/$proj-$v-1.$rpm_arch.rpm $dest

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
	
	tarball $dest "1"
	
	( cd $dest ;
	tar cvf $proj-$v.tar.2 $proj-$v ;
	tar -Af $proj-$v.tar $proj-$v.tar.2 ;
	rm $proj-$v.tar.2 ;
	gzip $proj-$v.tar )

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
