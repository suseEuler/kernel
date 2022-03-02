#! /bin/bash

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
