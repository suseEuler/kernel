# The version of the main tarball to use
SRCVERSION=5.10
# variant of the kernel-source package, either empty or "-rt"
VARIANT=
# enable kernel module compression
COMPRESS_MODULES="xz"
# Use new style livepatch package names
#LIVEPATCH=livepatch
# Compile binary devicetrees for Leap
BUILD_DTBS="Yes"
# buildservice projects to build the kernel against
OBS_PROJECT=openEuler.org:20.03:LTS:SP2
OBS_PROJECT_ARM=openEuler.org:20.03:LTS:SP2
# Bugzilla info
#BUGZILLA_SERVER="apibugzilla.suse.com"
#BUGZILLA_PRODUCT="SUSE Linux Enterprise Server 15 SP3"
# Check the sorted patches section of series.conf
SORT_SERIES=yes
