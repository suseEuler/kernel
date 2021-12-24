#!/bin/bash
#
# After generated mainline patches in patches.mainline from openEuler,
# the script is used to get the original mainline patch and rename
# patch file.
#
# The mainline-patch-files records all mainline patches's name, and it
# can be created like "ls patches.mainline/*|cat > mainline-patch-files"
#
# Put the script under OE kernel tree, and also add mainline repo to
# OE tree.

ML_BUG_ID=12

i=0
while read -r line; do
	echo $i
	echo $line
	i=$[$i+1]
	COMMIT=$(head -10 $line | grep Git-commit | awk '{print $2}')
	KERNELVERSION=$(head -10 $line | grep Patch-mainline | awk '{print $2}')
	if [ "$KERNELVERSION" = "v5.12-rc1-dontuse" ]; then
		KERNELVERSION=v5.12-rc2
	fi
	# Mainline patch file
	MPF=$(git format-patch -1 --no-numbered --no-renames --signoff $COMMIT)
	FOLDER=$(echo $MPF | awk -F '/' '{print $1}')

	if [ ! -f $MPF ]; then
		echo "XXX can't generate mainline patch file"
		continue
	fi

	LINE_AFTER_SUBJECT=$(grep -A 1 "^Subject" $MPF|tail -1|sed -e 's/ //g')
	if [ -z $LINE_AFTER_SUBJECT ]
	then
		sed -i -E -e "/^Subject: [PATCH]*/ a\Git-commit: $COMMIT\nPatch-mainline: $KERNELVERSION\nReferences: bsn#$ML_BUG_ID\n" $MPF
	else
		SUBJECT_LINENUM=$(sed -n -E '/^Subject/=' $MPF)
		NEXT_SUBJECT_LINENUM=$(($SUBJECT_LINENUM+1))
		sed -i -E -e "$NEXT_SUBJECT_LINENUM a\Git-commit: $COMMIT\nPatch-mainline: $KERNELVERSION\nReferences: bsn#$ML_BUG_ID\n" $MPF
	fi

	EXCEPTNUM=$(echo $MPF | cut -d "-" -f 2-)
	NEW_PATCH_NAME=$KERNELVERSION-$EXCEPTNUM
	mv $MPF $NEW_PATCH_NAME
	rm $line
	mv $NEW_PATCH_NAME patches.mainline/
	echo patches.mainline/$NEW_PATCH_NAME
done < mainline-patch-files
