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
