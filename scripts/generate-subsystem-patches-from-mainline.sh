#!/bin/bash
#
# This is used to backport specific subsystem from latest mainline.
#
# TODO: improve the checking of duplicated patch

# XXX setup them based on your own requirement.
LINUX_GIT=
LINUX_STABLE_GIT=
SUBSYSTEM_PATH=
# ID of bsn
ID=

START_VERSION=v5.10
END_STABLE_VERSION=v5.10.83

cd $LINUX_GIT
END_MAINLINE_VERSION=$(git tag --sort=taggerdate|tail -1)
echo !!! $END_MAINLINE_VERSION

# The path should be changed with specific subsystem path, and also file name
git log --oneline --no-merges $START_VERSION..$END_MAINLINE_VERSION $SUBSYSTEM_PATH > port-commits

generate_patch_from_file() {
	echo start $1
	i=0
	while read -r line; do
		i=$[$i+1]
		echo $i = "$line"
		COMMIT=$(echo $line|awk '{print $1}')
		KERNELVERSION=$(git tag --sort=taggerdate --contains $COMMIT|head -1)
		if [ "$KERNELVERSION" = "v5.12-rc1-dontuse" ]; then
			KERNELVERSION=v5.12-rc2
		fi
		echo 000 $KERNELVERSION
		MPF=$(git format-patch -1 --no-numbered --no-renames --signoff $COMMIT)
		echo 111 $MPF
		SUBJECT=$(head -10 $MPF|grep Subject|cut -d " " -f 3-)

		# check it the SUBJECT is existed in stable kernel
		cd $LINUX_STABLE_GIT
		EXISTED=$(git log --oneline $START_VERSION..$END_STABLE_VERSION | grep -F -i "$SUBJECT")
		cd $LINUX_GIT
		if [ -n "$EXISTED" ]; then
			rm $MPF
			echo XXX duplicated patch in $START_VERSION
			continue
		fi

		# insert meta info to patch file
		COMMIT=$(git show $COMMIT --pretty=tformat:%H|head -1)
		LINE_AFTER_SUBJECT=$(grep -A 1 "^Subject" $MPF|tail -1|sed -e 's/ //g')
		if [ -z $LINE_AFTER_SUBJECT ]
		then
			sed -i -E -e "/^Subject: [PATCH]*/ a\Git-commit: $COMMIT\nPatch-mainline: $KERNELVERSION\nReferences: bsn#$ID\n" $MPF
		else
			SUBJECT_LINENUM=$(sed -n -E '/^Subject/=' $MPF)
			NEXT_SUBJECT_LINENUM=$(($SUBJECT_LINENUM+1))
			sed -i -E -e "$NEXT_SUBJECT_LINENUM a\Git-commit: $COMMIT\nPatch-mainline: $KERNELVERSION\nReferences: bsn#$ID\n" $MPF
		fi

		EXCEPTNUM=$(echo $MPF | cut -d "-" -f 2-)
		NEW_PATCH_NAME=$KERNELVERSION-$EXCEPTNUM
		echo $NEW_PATCH_NAME
		mv $MPF $NEW_PATCH_NAME
	done < $1
	echo end $1
}

generate_patch_from_file port-commits
