#!/bin/bash

v=$1
if [ ! $v ]; then
	echo "Usage: $0 <version>"
	exit 1
fi

git-archive --prefix=undvd-$v/ HEAD | gzip > undvd-$v.tar.gz 
