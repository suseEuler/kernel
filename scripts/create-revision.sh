#! /bin/bash

SCRATCH_AREA=`mktemp -d` source $(dirname $0)/sequence-patch.sh --fast
expand_path=""

get_expand_path()
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
         get_expand_path "$path"
         # At the end of tar-up.sh, $build_dir/$tsfile has been created.
         # There is no need to check $build_dir/$tsfile exist or not.
         echo "$type REVISION: $(find $expand_path -type f -print0 | xargs -0 sha1sum | sha1sum | cut -d " " -f 1)" >> $build_dir/$tsfile
     fi
done < ./revision.conf

# Clean up working dir.
rm -rf $SCRATCH_AREA
