#!/bin/bash

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
