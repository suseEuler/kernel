#!/bin/bash

if [ $# != 1 ]; then
	exit
fi

patch=$1

grep -q "Modified-by-SEL:" $patch && exit

openeuler_commit=$(grep -r "openEuler-commit:" $patch | awk '{ print $2 }')
if [ "$openeuler_commit" = "" ]; then
	tag="No"
else
	patches_dir=$(dirname $patch)
	if [ "$patches_dir" = "patches.mainline" ]; then
		tag="Yes, modified according to openEuler commit $openeuler_commit"
		sed -i '/openEuler-commit:/'d $patch
	elif [ "$patches_dir" = "patches.openEuler" ]; then
		tag="FIXME"
	elif [ "$patches_dir" = "patches.euleros" ]; then
		tag="FIXME"
	else
		tag="No"
	fi
fi
sed -i '/References:/a\Modified-by-SEL: '"$tag"'' $patch
