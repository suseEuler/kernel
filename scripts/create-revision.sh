#! /bin/bash
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

TSFILE=$1
if [ -z "$TSFILE" ]; then
    echo "[ Please input source-timestamp file path. ]"
    exit 1
fi

export SCRATCH_AREA=$(mktemp -d -p $PWD)
# To make sure ORIG_DIR and PATCH_DIR are under same directroy.
PATCH_DIR=$SCRATCH_AREA/current
if ! $(dirname $0)/sequence-patch.sh --fast --patch-dir=$PATCH_DIR; then
    echo "[ sequence-patch.sh --fast --patch-dir=$PATCH_DIR failed. ] "
    echo "[ Cleaning up tree: $SCRATCH_AREA ]"
    rm -rf $SCRATCH_AREA
    exit 1
fi

get_expanded_path()
{
    expand_path=""
    local paths=$1
    for l_path in $paths
    do
        full=$PATCH_DIR/$l_path
        expand_path="${expand_path} ${full}"
    done
}

while read type path; do
     if [[ $type != \#* ]] && [ -n "$type" ] && [ -n "$path" ]; then
         get_expanded_path "$path"
         # TSFILE is source-timestamp which created by tar-up.sh
         echo "$type REVISION: $(find $expand_path -type f -print0 | sort -z -u | xargs -0 cat | sha1sum | cut -d ' ' -f 1)" >> $TSFILE
     fi
done < ./revision.conf

echo "[ Cleaning up tree: $SCRATCH_AREA ]"
rm -rf $SCRATCH_AREA
