#!/bin/bash
# This script create patches from mainline kernel KVER, for use in SUSE kernel-source package
# This script shall be run in a stable tree repo, i.e. https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
# Usage example: $0 5.10 1 81
# Which generates all patches from 5.10.1 to 5.10.81, and a series file, that can be used to 
# patch a 5.10 source tree to 5.10.81.

# The major version
KVER=$1
# The minor version to start with
KSTART=$2
# The minor version to end with
KEND=$3
# The dir to save the created patches, relative to this script
PATCHDIR=patches.stable
# Bug ID for tracking stable kernel backporting
BUGID=bsn#19

# For each minor release generate the patches
for v in $(eval echo {$KSTART..$KEND}); do
	if [ $v = "1" ]; then
		VLAST=$KVER
	else
		VLAST=$KVER.$((v-1))
	fi
	VTHIS=$KVER.$v

	git format-patch v$VLAST..v$VTHIS -o $PATCHDIR/$VTHIS \
		--no-numbered --no-renames --signoff \
		--add-header="References: $BUGID" \
		--add-header="Patch-mainline: v$VTHIS"

	cd $PATCHDIR/$VTHIS
	for f in *.patch; do
		mv "$f" $(echo $f | sed -e "s|^0|v$VTHIS-0|")
	done

	sed -i -E -e '1s|^From ([0-9a-z]{40}) (.*)|Git-commit: \1|' \
			-e 's|^References:|  References:|' *.patch

	mv *.patch ..
	cd -
	rm -rf $PATCHDIR/$VTHIS
done

ls -v $PATCHDIR/*.patch > $PATCHDIR/series

