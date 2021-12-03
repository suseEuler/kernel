#!/bin/bash
# This script breaks down openEuler kernel code into patches on top of the
# mainline kernel, for use in SUSE kernel-source package
# How to use:
# - git clone https://gitee.com/openeuler/kernel.git
# - cd kernel
# - run this script in the kernel repo dir (not this kernel-source repo)
# Then all the patches will be put to different folders based on category
#
# Note:
# 1. XXX setup your own mainline kernel tree with MAINLINE_PWD or LINUX_GIT
#        and run "git gc" under mainline kernel tree to speed up the script
#
# 2. rename $SERIES to series.conf, then copy it and other folders
#    (patches.*) to SUSE Euler kernel-source tree. Then we can get
#    kernel-source package based on them by run tar-up.sh
#
# Author: Kai Liu <kai.liu@suse.com>
#	  Guoqing Jiang <guoqing.jiang@suse.com>

# The upstream base version
UVER=v5.10
# The openEuler version
OVER=openEuler-21.09
# The folders to save the created patches, related to metadatas in euler patches
MAINLINEDIR=patches.mainline
STABLEDIR=patches.stable
EULERDIR=patches.euler
HULKDIR=patches.hulk
DRIVERDIR=patches.driver
MAILLISTDIR=patches.maillist
VIRTDIR=patches.virt
ZHAOXINDIR=patches.zhaoxin
RTOSDIR=patches.rtos
ASCENDDIR=patches.ascend
UNIONDIR=patches.uniontech
ANOLISDIR=patches.anolis

# Where the mainline kernel git is. SUSE kernel-source scripts use this $LINUX_GIT
# env var for this location so we reuse it.
MAINLINE_PWD=$LINUX_GIT
OE_BUG_ID=22

rm -rf $MAINLINEDIR $STABLEDIR $EULERDIR $HULKDIR $DRIVERDIR $MAILLISTDIR $VIRTDIR \
       $ZHAOXINDIR $RTOSDIR $ASCENDDIR $ANOLISDIR $UNIONDIR

if [ $# -gt 2 ] ; then
	echo "USAGE: $0 upstream-base-version openEuler-version"
	echo " e.g.: $0 v5.10 openEuler-21.03"
	echo "   or: $0 which run with default v5.10 and openEuler-21.09"
	exit 1;
fi

if [ -z $MAINLINE_PWD ]; then
	echo "You need to set either MAINLINE_PWD or LINUX_GIT!"
	exit 1;
fi

# Overwrite version based on parameter
if [ -n "$1" ]; then
	UVER=$1
fi
if [ -n "$2" ]; then
	OVER=$2
fi

# If the file which includes the last handled commit exists, then
# generate patches for that commit.
FILE_WITH_LAST_COMMIT=$PWD/fwlc-$OVER
LAST_COMMIT=$(git log --no-merges --pretty="format:%H" -n1 $OVER)
if [ -e $FILE_WITH_LAST_COMMIT ]; then
	UVER=$(cat $FILE_WITH_LAST_COMMIT)
	# in case openEuler kernel is not updated since last run
	if [[ $LAST_COMMIT == $UVER* ]]; then
		echo "No changes since last run"
		exit 1
	fi
fi

PATCHDIR=patches.others
# The series file which record all the patches in order
rm -rf series.$OVER
SERIES=series.$OVER

rm -rf $PATCHDIR
mkdir $PATCHDIR

# record the name of all patches to handle patches in sequence
PATCH_FILES=patches-file

# Generate the patches
# Need --no-renames as scripts/check-patchfmt requires it, and it's called by git commit hook
git format-patch $UVER..$OVER -o $PATCHDIR --no-numbered --no-renames --signoff | tee $PATCH_FILES
if [ $? != 0 ]; then
	echo "Error: either upstream version ($UVER) or openEuler version ($OVER) is not correct!"
	exit 1;
fi

# Update the last commit
echo $LAST_COMMIT > FILE_WITH_LAST_COMMIT_FILE

# insert metadata after "Subject: [PATCH]*" line
# if 4 parameters are passed to the function:
#	$1 - file name. $2 - message. $3 - OE_BUG_ID. $4 - OE commit
# if 3 parameters are passed to the function:
#	$1 - file name. $2 - commit. $3 - kernel version
# if 2 parameters are passed to the function:
#	$1 - file name. $2 - message
insert_meta() {
		LINE_AFTER_SUBJECT=$(grep -A 1 "^Subject" $f|tail -1|sed -e 's/ //g')
		# if LINE_AFTER_SUBJECT is not empty, then Subject line is wrapped
		if [ -z $LINE_AFTER_SUBJECT ]
		then
			if [ $# -eq 4 ]
			then
				sed -i -E -e "/^Subject: [PATCH]*/ a\Patch-mainline: $2\nReferences: bsn#$3\nopenEuler-commit: $4\n" $1
			elif [ $# -eq 3 ]
			then
				sed -i -E -e "/^Subject: [PATCH]*/ a\Git-commit: $2\nPatch-mainline: $3\nReferences: $OVER\n" $1
			elif [ $# -eq 2 ]
			then
				sed -i -E -e "/^Subject: [PATCH]*/ a\Patch-mainline: NO, $2\nReferences: $OVER\n" $1
			fi
		else
			#sed -i -E -e "6i\Git-commit: $COMMIT\nPatch-mainline: $KERNELVERSION\nReferences: $OVER\n" $f
			SUBJECT_LINENUM=$(sed -n -E '/^Subject/=' $f)
			NEXT_SUBJECT_LINENUM=$(($SUBJECT_LINENUM+1))
			if [ $# -eq 4 ]
			then
				sed -i -E -e "$NEXT_SUBJECT_LINENUM a\Patch-mainline: $2\nReferences: bsn#$3\nopenEuler-commit: $4\n" $1
			elif [ $# -eq 3 ]
			then
				sed -i -E -e "$NEXT_SUBJECT_LINENUM a\Git-commit: $2\nPatch-mainline: $3\nReferences: $OVER\n" $1
			elif [ $# -eq 2 ]
			then
				sed -i -E -e "$NEXT_SUBJECT_LINENUM a\Patch-mainline: NO, $2\nReferences: $OVER\n" $1
			fi
		fi
}

# $1 - COMMIT. $2 - f (file name + folder name)
mainline_commit_handle() {
		COMMIT=$1
		f=$2

		# in case the patch is from stable kernel though it claims "mainline inclusion" with
		# the commit which is actually SHA1 in stable kernel!!!
		COMMITLINE=$(head -30 $f | grep -A 2  "\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-" | grep -v revert | grep -E "[cC]ommit")
		COL_STYLE=$(echo $COMMITLINE | awk '{print NF}')
		if [ -n "$COMMITLINE" ] && [ $COL_STYLE -le 5 ]; then
			# get SHA1 after split one line to multiple lines
			UPDATE_COMMIT=$(echo $COMMITLINE | sed 's/ /\n/g' | grep '[a-f0-9]\{40\}')
			if [ -n "$COMMIT" ]; then
				COMMIT=$UPDATE_COMMIT
			fi
		fi

		if [ -z $COMMIT ]; then
			echo XXX no mainline commit!
			echo -e "\t$f" >> $SERIES
			return
		fi

		CURR_PWD=$PWD
		cd $MAINLINE_PWD
		# Sometimes the upstream commit ID in openEuler commits are in the short form,
		# expand it to the full 40-char form as it's required by the "Git-commit:" header
		if [ ${#COMMIT} -lt 40 ]; then
			echo -n "Commit $COMMIT is abbrevated, "
			COMMIT=$(git rev-parse $COMMIT)
			echo "expanded to full form $COMMIT"
		fi

		KERNELVERSION=$(git tag --sort=taggerdate --contain $COMMIT|head -1)
		if [ -z $KERNELVERSION ]; then
			echo "XXX $f Commit "$COMMIT" has empty KERNELVERSION!"
		fi
		cd $CURR_PWD

		echo $KERNELVERSION in mainline tree

		insert_meta $f $COMMIT $KERNELVERSION
		# get patch file's name without directory
		PURE_PATCH_NAME=$(echo $f | cut -d "/" -f 2-)
		# get digit number from PURE_PATCH_NAME, eg, 0001 from 0001-aaa.patch
		NUM=$(echo $PURE_PATCH_NAME | cut -d'-' -f1)
		# get other parts from PURE_PATCH_NAME except digit, eg aaa.patch from 0001-aaa.patch
		EXCEPTNUM=$(echo $PURE_PATCH_NAME | cut -d "-" -f 2-) #remove the patch num
		NEW_PATCH_NAME=$NUM-$KERNELVERSION-$EXCEPTNUM

		if [ ! -d $MAINLINEDIR ]; then
			mkdir $MAINLINEDIR
		fi
		echo $f in mainlinecommit_handle
		echo $NEW_PATCH_NAME
		mv $f $MAINLINEDIR/$NEW_PATCH_NAME
		echo $MAINLINEDIR/$NEW_PATCH_NAME
		echo -e "\t$MAINLINEDIR/$NEW_PATCH_NAME" >> $SERIES
}

rm $SERIES

# patches in patches.rpmify (kernel-source tree) are necessary
echo -e "\t########################################################"  >> $SERIES
echo -e "\t# Build fixes that apply to the vanilla kernel too." >> $SERIES
echo -e "\t# Patches in patches.rpmify are applied to both -vanilla" >> $SERIES
echo -e "\t# and patched flavors." >> $SERIES
echo -e "\t########################################################"  >> $SERIES

# tar-up.sh checks this part
echo -e >> $SERIES
echo -e "\t########################################################"  >> $SERIES
echo -e "\t# sorted patches" >> $SERIES
echo -e "\t########################################################"  >> $SERIES
echo -e "\t########################################################"  >> $SERIES
echo -e "\t# end of sorted patches" >> $SERIES
echo -e "\t########################################################"  >> $SERIES
echo -e >> $SERIES

cat $PATCH_FILES | while read line
do
	echo
	echo handle $line in $PATCH_FILES
	f=$line
#for f in $PATCHDIR/*.patch; do
	MAINLINE_INCLUSION=$(head -20 "$f" | \
			     grep -m 1 -E \
			     "(mainline inclusion)|(mainine inclusion)|ommit [0-9a-z]{10}|pstream comm")
	STABLE_INCLUSION=$(head -20 "$f" | grep  -m 1 -E "stable inclusion")
	EULER_INCLUSION=$(head -20 "$f" | grep  -m 1 -E "(openEuler inclusion)|(euler inclusion)|(euleros inclusion)")
	HULK_INCLUSION=$(head -20 "$f" | grep  -m 1 -E "hulk inclusion")
	DRIVER_INCLUSION=$(head -20 "$f" | grep  -m 1 -E "driver inclusion")
	MAILLIST_INCLUSION=$(head -20 "$f" | grep  -m 1 -E "maillist inclusion")
	VIRT_INCLUSION=$(head -20 "$f" | grep  -m 1 -E "virt inclusion")
	ZHAOXIN_INCLUSION=$(head -20 "$f" | grep  -m 1 -E "zhaoxin inclusion")
	RTOS_INCLUSION=$(head -20 "$f" | grep  -m 1 -E "rtos inclusion")
	ASCEND_INCLUSION=$(head -20 "$f" | grep  -m 1 -E "ascend inclusion")
	ANOLIS_INCLUSION=$(head -20 "$f" | grep  -m 1 -E "anolis inclusion")
	UNION_INCLUSION=$(head -20 "$f" | grep  -m 1 -E "union inclusion")

	if [ -n "$STABLE_INCLUSION" ]; then
		# most stable patches are from mainline kernel
		COMMITLINE=$(head -30 $f | grep -A 2  "\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-" | grep -v revert | grep -E "[cC]ommit")
		if [ -n "$COMMITLINE" ]; then
			# get SHA1 after split one line to multiple lines
			COMMIT=$(echo $COMMITLINE | sed 's/ /\n/g' | grep '[a-f0-9]\{40\}')
			if [ -n "$COMMIT" ]; then
				echo $COMMIT
				mainline_commit_handle $COMMIT $f
				continue
			fi
		fi

		echo $f STABLE_INCLUSION
		insert_meta $f 'STABLE INCLUSION'
		if [ ! -d $STABLEDIR ]; then
			mkdir $STABLEDIR
		fi
		mv $f $STABLEDIR
		f=$(echo $f|awk -F '/' '{print $2}')
		echo -e "\t$STABLEDIR/$f" >> $SERIES
	elif [ -n "$ANOLIS_INCLUSION" ]; then
		echo $f ANOLIS_INCLUSION
		OECOMMIT=$(head -1 $f | awk '{print $2}')
		insert_meta $f 'Not yet, from openEuler' $OE_BUG_ID $OECOMMIT
		if [ ! -d $ANOLISDIR ]; then
			mkdir $ANOLISDIR
		fi
		mv $f $ANOLISDIR
		f=$(echo $f|awk -F '/' '{print $2}')
		echo -e "\t$ANOLISDIR/$f" >> $SERIES
	elif [ -n "$UNION_INCLUSION" ]; then
		echo $f UNION_INCLUSION
		OECOMMIT=$(head -1 $f | awk '{print $2}')
		insert_meta $f 'Not yet, from openEuler' $OE_BUG_ID $OECOMMIT
		if [ ! -d $UNIONDIR ]; then
			mkdir $UNIONDIR
		fi
		mv $f $UNIONDIR
		f=$(echo $f|awk -F '/' '{print $2}')
		echo -e "\t$UNIONDIR/$f" >> $SERIES
	elif [ -n "$EULER_INCLUSION" ]; then
		echo $f EULER_INCLUSION
		OECOMMIT=$(head -1 $f | awk '{print $2}')
		insert_meta $f 'Not yet, from openEuler' $OE_BUG_ID $OECOMMIT
		if [ ! -d $EULERDIR ]; then
			mkdir $EULERDIR
		fi
		mv $f $EULERDIR
		f=$(echo $f|awk -F '/' '{print $2}')
		echo -e "\t$EULERDIR/$f" >> $SERIES
	elif [ -n "$HULK_INCLUSION" ]; then
		echo $f EULER_INCLUSION
		OECOMMIT=$(head -1 $f | awk '{print $2}')
		insert_meta $f 'Not yet, from openEuler' $OE_BUG_ID $OECOMMIT
		if [ ! -d $HULKDIR ]; then
			mkdir $HULKDIR
		fi
		mv $f $HULKDIR
		f=$(echo $f|awk -F '/' '{print $2}')
		echo -e "\t$HULKDIR/$f" >> $SERIES
	elif [ -n "$DRIVER_INCLUSION" ]; then
		echo $f DRIVER_INCLUSION
		OECOMMIT=$(head -1 $f | awk '{print $2}')
		insert_meta $f 'Not yet, from openEuler' $OE_BUG_ID $OECOMMIT
		if [ ! -d $DRIVERDIR ]; then
			mkdir $DRIVERDIR
		fi
		mv $f $DRIVERDIR
		f=$(echo $f|awk -F '/' '{print $2}')
		echo -e "\t$DRIVERDIR/$f" >> $SERIES
	elif [ -n "$MAILLIST_INCLUSION" ]; then
		echo $f MAILLIST_INCLUSION
		OECOMMIT=$(head -1 $f | awk '{print $2}')
		insert_meta $f 'Not yet, from openEuler' $OE_BUG_ID $OECOMMIT
		if [ ! -d $MAILLISTDIR ]; then
			mkdir $MAILLISTDIR
		fi
		mv $f $MAILLISTDIR
		f=$(echo $f|awk -F '/' '{print $2}')
		echo -e "\t$MAILLISTDIR/$f" >> $SERIES
	elif [ -n "$VIRT_INCLUSION" ]; then
		echo $f VIRT_INCLUSION
		OECOMMIT=$(head -1 $f | awk '{print $2}')
		insert_meta $f 'Not yet, from openEuler' $OE_BUG_ID $OECOMMIT
		if [ ! -d $VIRTDIR ]; then
			mkdir $VIRTDIR
		fi
		mv $f $VIRTDIR
		f=$(echo $f|awk -F '/' '{print $2}')
		echo -e "\t$VIRTDIR/$f" >> $SERIES
	elif [ -n "$ZHAOXIN_INCLUSION" ]; then
		echo $f ZHAOXIN_INCLUSION
		OECOMMIT=$(head -1 $f | awk '{print $2}')
		insert_meta $f 'Not yet, from openEuler' $OE_BUG_ID $OECOMMIT
		if [ ! -d $ZHAOXINDIR ]; then
			mkdir $ZHAOXINDIR
		fi
		mv $f $ZHAOXINDIR
		f=$(echo $f|awk -F '/' '{print $2}')
		echo -e "\t$ZHAOXINDIR/$f" >> $SERIES
	elif [ -n "$RTOS_INCLUSION" ]; then
		echo $f RTOS_INCLUSION
		OECOMMIT=$(head -1 $f | awk '{print $2}')
		insert_meta $f 'Not yet, from openEuler' $OE_BUG_ID $OECOMMIT
		if [ ! -d $RTOSDIR ]; then
			mkdir $RTOSDIR
		fi
		mv $f $RTOSDIR
		f=$(echo $f|awk -F '/' '{print $2}')
		echo -e "\t$RTOSDIR/$f" >> $SERIES
	elif [ -n "$ASCEND_INCLUSION" ]; then
		echo $f ASCEND_INCLUSION
		OECOMMIT=$(head -1 $f | awk '{print $2}')
		insert_meta $f 'Not yet, from openEuler' $OE_BUG_ID $OECOMMIT
		if [ ! -d $ASCENDDIR ]; then
			mkdir $ASCENDDIR
		fi
		mv $f $ASCENDDIR
		f=$(echo $f|awk -F '/' '{print $2}')
		echo -e "\t$ASCENDDIR/$f" >> $SERIES
	elif [ -n "$MAINLINE_INCLUSION" ]; then

		COMMIT=$(head -20 $f | grep -v Subject | grep -m 1 -E "^commit [0-9a-z]{10}" "$f" | cut -d' ' -f2)
		echo $f mainline
#		sometimes it is master since "from mainline-master"
		KERNELVERSION=$(head -15 $f | grep -v Subject | grep "from main" | cut -d - -f 2,3)
		if [ "$KERNELVERSION" == "master" ]; then
			echo $COMMIT 0000
			mainline_commit_handle $COMMIT $f
			continue
		fi

		# for style like "mainline inclusion"
		STYLE0=$(head -20 "$f" | grep -v Subject | \
			grep -m 1 -E "(nline inclusion)|(nline  inclusion)|(mainline-next inclusion)")
		if [ -n "$STYLE0" ]; then
			COMMITLINE=$(head -20 "$f" | grep -v Subject | \
				     grep -m 1 -E "(commit:)|(commit)" | awk '{print $2}')
			NOT_YET_READY=$(echo $COMMITLINE | grep not-yet-available)
			HTTP=$(echo $COMMITLINE | grep http)
			FROM_KERNEL=$(echo $COMMITLINE | grep "from kernel")
			if [ -n "$NOT_YET_READY" ] || [ -n "$HTTP" ]; then
				echo -e "\t$f" >> $SERIES
				insert_meta $f 'check it manually'
				echo $f is not in mainline tree yet!!!
				continue
			fi

			# cut the line so we can start from "ommit ..."
			COMMIT=$(echo ${COMMITLINE#*ommit}| cut -d' ' -f1)
			echo $COMMIT $f
			mainline_commit_handle $COMMIT $f
			continue
		fi

		# for style like "[ Upstream commit * ]" or "Upstream commit *" or "commit * upstream."
		STYLE1=$(head -120 "$f" | grep -v Subject | grep -m 1 -E "(pstream comm)|(ommit [0-9a-z]{10})")
		COL_STYLE=$(echo $STYLE1|awk '{print NF}')
		if [ $COL_STYLE != 5 ] && [ $COL_STYLE != 4 ] && [ $COL_STYLE != 3 ]; then
			echo $COL_STYLE
			echo need XXX to handle the un-categorized $f manually!!!
			echo -e "\t$f" >> $SERIES
			insert_meta $f 'check it manually'
			continue;
		fi

		# for style like "[ Upstream commit * ]" or [ commit * upstream ]" or "Upstream commit *"
		if [ -n "$STYLE1" ] && [ $COL_STYLE != 4 ]; then
			COMMITLINE=$(head -20 "$f" | grep "pstream comm")
			# cut the line so we can start from "ommit ..."
			#COMMIT=$(echo ${COMMITLINE#*ommit}| cut -d' ' -f1)
			if [ "$COL_STYLE" -eq "5" ]; then
				COMMIT=$(head -20 "$f" | grep "pstream comm" | cut -d' ' -f4)
				# try [ commit * upstream ]
				if [ -z "$COMMIT" ]; then
					COMMIT=$(head -20 "$f" | grep "commit" | grep "upstream" | cut -d' ' -f3)
				fi
			else
				COMMIT=$(head -20 "$f" | grep "pstream comm" | cut -d' ' -f2)
				if [ -z "$COMMIT" ]; then
					# for "commit * upstream."
					# Some line has "commit <short rev> upstream" form while some has 40-char full from,
					# so the regex here matches a rev from 7 to 40 long
					COMMIT=$(head -20 "$f" | grep -m 1 -E "ommit [0-9a-z]{7,40} upstream" | cut -d' ' -f2)
				fi
			fi

			echo $COMMIT 111
			if [ -n "$COMMIT" ]; then
				mainline_commit_handle $COMMIT $f
			else
				# [ commit 4f7b3e82589e0de723780198ec7983e427144c0a upstream ]
				echo -e "\t$f" >> $SERIES
				insert_meta $f 'check it manually'
				echo cannot find commit for $f do it manually
			fi
			continue
		fi

		# for style like "[ Upstream commit *"
		STYLE2=$(head -20 "$f" | grep -v Subject | grep -m 1 -E "ommit [0-9a-z]{10}")
		if [ -n "$STYLE2" ]; then
			COMMIT=$(echo $STYLE2 | cut -d' ' -f4)
			echo $COMMIT 222
			mainline_commit_handle $COMMIT $f
			continue
		fi

	        # don't check the "Subject" line
		COMMIT=$(head -20 $f | grep -v Subject | grep -m 1 -E "reverts commit [0-9a-z]{10}" "$f")
		echo $COMMIT
		# style like "This reverts commit a6a0d7f89b3ecd0fd96540222f3f2ff8397a5c9b."
		if [ -n "$COMMIT" ]; then
			echo $f is not mainline commit
			echo -e "\t$f" >> $SERIES
			insert_meta $f 'check it manually'
			continue
		fi

		insert_meta $f 'check it manually'
		echo XXX fuck another type for $f $COMMIT $KERNELVERSION!
		continue
	else
		insert_meta $f 'OTHERS'
		echo -e "\t$f" >> $SERIES
		echo need to handle the un-categorized $f manually!!!
	fi
done

echo -e >> $SERIES

# patches in patches.suse (kernel-source tree) are necessary
echo -e "\t########################################################" >> $SERIES
echo -e "\t# kbuild/module infrastructure fixes" >> $SERIES
echo -e "\t########################################################" >> $SERIES
