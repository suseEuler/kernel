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

# To get SRCVERSION
. ./rpm/config.sh

SDIR=$PWD
BRANCH=$(git branch --show-current)
export SCRATCH_AREA=./tmp-fixme

if [ -z $BRANCH ]; then # when running on a detached head
	TMPTREE=$SCRATCH_AREA/linux-$SRCVERSION
else
	TMPTREE=$SCRATCH_AREA/linux-$SRCVERSION-$BRANCH
fi

while true; do
	if ./scripts/sequence-patch.sh --rapid; then
		echo "All done!"
		break
	else
		cd $TMPTREE
		FAILED_PATCH=$(quilt next | awk -F/ '{print $2"/"$3}')

		if quilt push --fuzz=0 --merge; then
			echo "quilt push with --fuzz=0 --merge succeeded"
			quilt refresh -p ab --no-index -U 3 --no-timestamps --diffstat
			sed -i -e "s|$FAILED_PATCH|# FIXME: fuzz=0 merge $FAILED_PATCH|" $SDIR/series.conf
		elif quilt push --fuzz=2; then
			echo "quilt push with --fuzz=2 succeeded"
			quilt refresh -p ab --no-index -U 3 --no-timestamps --diffstat
			sed -i -e "s|$FAILED_PATCH|# FIXME: fuzz=2 $FAILED_PATCH|" $SDIR/series.conf
		else
			echo "quilt push failed with reject(s), patch $FAILED_PATCH needs FIXME"
			sed -i -e "s|$FAILED_PATCH|# FIXME: rejected $FAILED_PATCH|" $SDIR/series.conf
		fi
		cd $SDIR
	fi
done
