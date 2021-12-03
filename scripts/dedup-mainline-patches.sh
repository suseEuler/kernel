#!/bin/bash
#
# After run generate-mainline-patches.sh, let's remove patch if it was
# already in relevant stable kernel.
#
# The mainline-patch-files records all mainline patches's name, and it
# can be created like "ls patches.mainline/*|cat > mainline-patch-files"
#
# TODO: improve the checking of duplicated patch

i=0
CURR_PWD=$PWD
START_STABLE_VERSION=v5.10
END_STABLE_VERSION=v5.10.83
while read -r line; do
	i=$[$i+1]

	echo $line
	SUBJECT=$(head -10 $line | grep Subject |  cut -d " " -f 3-)
	echo $SUBJECT
	cd $LINUX_STABLE_GIT; #stable tree, 5.10.y branch for OE OLK-5.10
	EXISTED=$(git log --oneline $START_STABLE_VERSION..$END_STABLE_VERSION | grep "$SUBJECT")
    	echo $EXISTED
	cd $CURR_PWD
	if [ -n "$EXISTED" ]; then
		rm $line
		echo rm $line
	fi

	echo $i
done < mainline-patch-files
