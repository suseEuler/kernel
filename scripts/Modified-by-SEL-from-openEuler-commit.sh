#!/bin/bash
#
# Copyright (c) 2022 Yunche Information Technology (Shenzhen) Co., Ltd.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.
#

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
