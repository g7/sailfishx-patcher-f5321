#!/bin/bash
#
# patcher
#

set -e

export LANG=C

# Try to naively infer the base directory
PATCHER_DIR="$(dirname $0)"
[ "${PATCHER_DIR}" == "." ] && PATCHER_DIR="$PWD"

# The default BASE_TEMP_DIR is /tmp/sailfish-image-patcher
BASE_TEMP_DIR="/tmp/sailfish-image-patcher"

ARCH="$(uname -m)"

ATRUNCATE_PATH="${PATCHER_DIR}/atruncate.py"

#PATCH_KERNEL="yes"
#REPACK_SCRIPT="${PATCHER_DIR}/droid-config-f5121/kickstart/pack/f5121/hybris"
#PACKAGE="pattern:droid-compat-f5321"
#REPOSITORY_URI="http://repo.merproject.org/obs/home:/eugenio:/compat-f5321/sailfish_latest_armv7hl/"

info() {
	echo "I: $@"
}

warning() {
	echo "W: $@"
}

error() {
	echo "E: $@" >&2
	exit 1
}

check_application() {
	### Checks for the existence of an application
	###
	### param: $@: the file to check

	for application in $@; do
		if ! which $application &> /dev/null; then
			error "$application is missing. Please install the relative package and retry"
		fi
	done
}

help() {
	cat <<EOF
patcher - patches a Sailfish X image

Arguments:
    -a ADAPTATION                     the adaptation script to use (e.g. f5321 for X Compact)
    -b BASE_TEMP_DIR                  base temp dir, defaults to ${BASE_TEMP_DIR}
    -i INPUT_FILE                     the zipfile to patch
EOF
}

if [ "$UID" != 0 ]; then
	warning "You must be root to use this script! Trying with sudo..."
	exec sudo $0 $@
fi

# Get options
while getopts "a:b:i:h" option; do
	case "${option}" in
		a)
			# Adaptation
			ADAPTATION="${OPTARG}"
			;;
		b)
			# Base temp dir
			BASE_TEMP_DIR="${OPTARG}"
			;;
		i)
			# Input file
			INPUT_FILE="${OPTARG}"
			;;
		h)
			# Help
			help
			exit 0
			;;
		?)
			# Someting bad occurred
			error "Use -h to show the help message."
			;;
	esac
done

[ -n "${ADAPTATION}" ] || error "Adaptation is missing. See the help for details"
[ -n "${INPUT_FILE}" ] || error "Input file is missing. See the help for details"

# Source the adaptation file
[ -e "${PATCHER_DIR}/devices/${ADAPTATION}" ] || error "Adaptation source file is missing. Exiting..."

. ${PATCHER_DIR}/devices/${ADAPTATION}

if [ "$ARCH" != "armv7l" ] || [ "$ARCH" != "aarch64" ]; then
	WITH_QEMU_STATIC="yes"
	check_application qemu-arm-static
fi

check_application \
	simg2img \
	img2simg \
	rsync \
	pigz \
	losetup \
	pvcreate \
	vgcreate \
	e2fsck \
	resize2fs 

# Let's go!
WORKDIR=${BASE_TEMP_DIR}

cleanup() {
	info "Cleaning up..."

	for mpoint in "$(mount | awk '{ print $3 }' | grep ${WORKDIR} | sort -r)"; do
		if [ -n "${mpoint}" ]; then
			info "Umounting ${mpoint}..."
			umount ${mpoint}
		fi
	done
}

trap cleanup EXIT

if [ -e "${WORKDIR}" ]; then
	rm -rf "${WORKDIR}"
fi

mkdir -p "${WORKDIR}"

info "Unzipping the Sailfish X archive"
unzip \
	${INPUT_FILE} \
	-d ${WORKDIR} \
	-x */sailfish.img001

cd ${WORKDIR}/Sailfish*
mkdir -p patcher-tmp
mkdir -p patcher-tmp/work
mkdir -p patcher-tmp/work/fimage
mkdir -p patcher-tmp/work/tree
mkdir -p patcher-result

FIMAGE_MPOINT="$(mktemp -d -p ${BASE_TEMP_DIR})"
ROOT_MPOINT="$(mktemp -d -p ${BASE_TEMP_DIR})"

# Turn the fimage into a raw image
info "Converting the fimage sparse image to a raw image..."
simg2img fimage.img001 patcher-tmp/fimage.img
rm -f fimage.img001

# Mount the image and copy the contents to fimage
info "Copying the fimage contents"
mount -o loop patcher-tmp/fimage.img ${FIMAGE_MPOINT}
cp -Rav ${FIMAGE_MPOINT}/Sailfish*/*.gz patcher-tmp/work/fimage
umount ${FIMAGE_MPOINT}
rm -f patcher-tmp/fimage.img

info "Uncompressing the contents"
gunzip patcher-tmp/work/fimage/home.img.gz
gunzip patcher-tmp/work/fimage/root.img.gz

# Mount root.img and rsync its contents to work/
info "Copying the Sailfish root contents..."
mount -o loop patcher-tmp/work/fimage/root.img ${ROOT_MPOINT}

rsync --archive -H -A -X ${ROOT_MPOINT}/* patcher-tmp/work/tree

umount ${ROOT_MPOINT}

# Get ROOT_SIZE; this will be useful later...
ROOT_SIZE=$(du -sm patcher-tmp/work/fimage/root.img | awk '{ print $1 }')
rm -f patcher-tmp/work/fimage/root.img

# Copy qemu-arm-static if we should...
if [ "$WITH_QEMU_STATIC" == "yes" ]; then
	cp $(which qemu-arm-static) patcher-tmp/work/tree/usr/bin
fi

# Then create the script to execute inside the chroot
cat > patcher-tmp/work/tree/patch.sh <<EOF
#!/bin/bash

# Add repository
ssu ar tmp-compat-$ADAPTATION $REPOSITORY_URI
ssu ur

# Fetch zypper
ZYPPER_PACKAGES="augeas-libs readline zypper"
JOLLA_REPO=\$(ssu lr 2> /dev/null | grep -o "https://releases.jolla.com/releases/[0-9\.]*/jolla/.*")
if [ -z "\$JOLLA_REPO" ]; then
	echo "E: unable to get jolla repository"
	exit 1
fi
tmpdir=\$(mktemp -d)

# Try to obtain the primary.xml.gz file
curl -L \$JOLLA_REPO/repodata/primary.xml.gz > \$tmpdir/primary.xml.gz
gunzip \$tmpdir/primary.xml.gz

for pkg in \$ZYPPER_PACKAGES; do
	# This is pretty ugly
	pkg_path=\$(grep -oE "core\/.*\/\$pkg-[0-9\.\-\_]+.*\.rpm" \$tmpdir/primary.xml | grep -v "\/src\/")
	curl -L \$JOLLA_REPO/\$pkg_path > \$tmpdir/\$pkg.rpm
done

# This is pretty ugly
#cd /var/cache/zypp/packages
cd \$tmpdir
find . -iname \*.rpm | xargs rpm -ivh

# Refresh
zypper refresh tmp-compat-$ADAPTATION
zypper refresh jolla

# Install the compatibility layer
CACHE_DIR=\$(mktemp -d)
zypper -n --no-refresh --cache-dir \$CACHE_DIR install $PACKAGE

# Disable the temp
ssu dr tmp-compat-$ADAPTATION
ssu rr tmp-compat-$ADAPTATION
ssu er compat-$ADAPTATION
ssu ur

# Obtain a custom kernel image
if [ "$PATCH_KERNEL" == "yes" ]; then
	# Divert /usr/sbin/flash-partition as we're not going to flash
	# anything
	rpm-divert add \
		droid-compat-tmp \
		/usr/sbin/flash-partition \
		/usr/sbin/flash-partition.diverted \
		--action symlink \
		--replacement /bin/true

	rpm-divert apply --package droid-compat-tmp

	/var/lib/platform-updates/flash-bootimg.sh

	# The result should be in /tmp

	# Restore the diversion
	rpm-divert unapply --package droid-compat-tmp

	rpm-divert remove droid-compat-tmp /usr/sbin/flash-partition
fi

# Terminate what we started
kill -9 \$(ps aux | grep qemu-arm | grep -v "bash\|grep" | awk '{ print \$2 }' | sort -r) &> /dev/null

# Cleanup
rm -f /patch.sh
rm -f /var/run/connman/resolv.conf
rm -f /var/run/messagebus.pid
if [ "$WITH_QEMU_STATIC" == "yes" ]; then
	rm -f /usr/bin/qemu-arm-static
fi

# FIXME: leave zypper in for now

echo "DONE!"
EOF


# Prepare the work directory
info "Preparing for the patch..."
mount --bind /dev patcher-tmp/work/tree/dev
mount --bind /dev/pts patcher-tmp/work/tree/dev/pts
mount --bind /sys patcher-tmp/work/tree/sys
mount --bind /proc patcher-tmp/work/tree/proc

cp /etc/resolv.conf patcher-tmp/work/tree/var/run/connman/resolv.conf

# Finally patch
info "Patching the image..."
chroot patcher-tmp/work/tree /bin/bash /patch.sh

# Umount
umount patcher-tmp/work/tree/dev/pts
umount patcher-tmp/work/tree/dev
umount patcher-tmp/work/tree/sys
umount patcher-tmp/work/tree/proc

# The home image is untouched, move from the fimage directory
mv patcher-tmp/work/fimage/home.img patcher-tmp/work

# Copy the files from the $INPUT_DIR to the work directory
cp ./{*.dll,*.exe,flash*,*.img,*.urls,*.bat} patcher-tmp/work

# Copy the kernel if we should
if [ "$PATCH_KERNEL" == "yes" ]; then
	mv patcher-tmp/work/tree/tmp/hybris-boot-patched.img patcher-tmp/work/hybris-boot.img
fi

# Cleanup tmp/
rm -rf patcher-tmp/work/tree/tmp/*

# Extract UUIDs. We will use the originals to avoid modifying the fstab.
# The UUIDs are already shared between Sailfish images, so don't actually
# bother to change them.
ROOT_UUID=$(cat patcher-tmp/work/tree/etc/fstab | grep "/ " | awk '{ print $1 }' | cut -d"=" -f2)
FIMAGE_UUID=$(cat patcher-tmp/work/tree/etc/fstab | grep "/fimage " | awk '{ print $1 }' | cut -d"=" -f2)

# Re-create the root.img
info "Creating an empty root image"
SIZE=$(( ${ROOT_SIZE} + 20 )) # 20MB contingency
dd if=/dev/zero of=patcher-tmp/work/root.img bs=1M count=${SIZE}

mkfs.ext4 -U ${ROOT_UUID} patcher-tmp/work/root.img

# Mount and sync the image contents
mount -o loop patcher-tmp/work/root.img ${ROOT_MPOINT}

info "Syncing back the patched tree"
rsync --archive -H -A -X patcher-tmp/work/tree/* ${ROOT_MPOINT}

sync

umount ${ROOT_MPOINT}

info "Repacking"
repack

# Moving the image
mv patcher-tmp/work/Sailfish*.zip ${PATCHER_DIR}

info "Done! Enjoy!"
