#!/usr/bin/bash
# by wm/wiemag/dif, original date 2013-09-09
#
# ---==== INSTALL ARCH LINUX ON A HEADLESS SERVER ====-------------------------
# Remaster arch.iso image so that it starts automatically.
# Allow an ssh-administered ("blind") installation of a headless server.
#
# Assumptions about the computer system arch linux will be installed on:
# - it boots from a CD/DVD first
# - it is connected to the local network
# Currently, the official installation media start with the ssh daemon down.
#

# Checking if system needs to be rebooted -------
# Necessery if kernel has been updated.
u=$(uname -r); u=${u/-arch/.arch};
p=$(pacman -Q linux|cut -d" " -f2)
if [[ $u != $p ]]; then
	echo -e "Kernel installed: ${p}\nKernel running:   $u"
	echo -e "Mounting not possible.\nYour computer needs to be rebooted."
	exit
fi

# Checking missing dependencies -----------------
hash unsquashfs 2>/dev/null || { echo "The squashfs-tools package is needed."; exit;}
hash genisoimage 2>/dev/null || { 	echo -n "The cdrtools package is missing"; exit;}
hash awk 2>/dev/null || { echo -n "The gawk package is missing"; exit;}
hash fuseiso 2>/dev/null || { echo -n "The fuseiso package is missing"; exit;}
hash sha512sum 2>/dev/null || { echo -n "The coreutils package is missing"; exit;}
hash xorriso 2>/dev/null || { echo -n "The libisoburn package is missing"; exit;}

# Checking if run by root -----------------------
#[[ $EUID -ne 0 ]] && { echo "Run this script as the root." 2>&1; exit 1;}

# Declarations and initialisation ---------------
function syno() {
	echo -e "\narch-headless modifies the official arch linux installation"
	echo image to enable passwordless SSH\'ing into the system booted from
	echo -e "the installation media. See man pages (man arch-headless).\n"
}
function flags() {
	echo "  arch.iso  path to arch-install-media.iso"
	echo "            e.g. archlinux-2013.09.01-dual.iso"
	echo "            or /path/to/archlinux-2013.09.01-dual.iso"
	echo "  -f file|folder"
	echo "            copy file or folder contents into /usr/local/bin folder"
	echo -e "  -v        show the ${0##*/} version number\n"
}
function usage() {
	echo -e "\n\e[1march-headless [-a 64] [-l] [-f file|folder] [-b] [-x] arch.iso | -c | -h | -v\e[0m\n"
	(( $# )) && flags
}

function basepath () {
	local path p
	path=${1-.}
	[[ -z ${path%%/*} ]] || path="$(pwd)/$path"
	while [[ $path == */./* ]]; do path=${path//\/\.\///}; done
	path=${path//\/\//\/} 		# Remove //
	while [[ "$path" == *..* ]]; do
		p=${path%%\/\.\.*}; p=${p%/*}
		path=${p}${path#*\.\.}
	done
	path=${path%/*} 			# Remove last tier name
	[[ -z $path ]] && path='/'
	echo "$path"
}

function warn_incompatibility () {
	if [[ $1 != $(uname -m) ]]; then
		echo
		echo "+---------------------------------------------------+"
		echo "|  Remember your machine architecture               |"
		echo "|  is different from that of the ISO being created. |"
		echo "+---------------------------------------------------+"
	fi
}

ARCH="x86_64"
FILE="" 		# File or folder to be copied to /usr/local/bin/
ROOTFS_SFS='airootfs.sfs'		# in archiso/arch/
ROOTFSD=rootfs-$USER  			# temporary rootfs directory
AIDIR=$(pwd)/archiso-MOUNT 		 			# temporary directory
ISO_LABEL=''                  	# determined later based on syslinux
ISO_FNAME=''                    # ISO image file name; Set later in the script

# If -b is used, a /mnt/archiso-${USER}-params is created.

# Parse the command line ------------------------
while getopts  ":a:bclf:xhv" flag
do
    case "$flag" in
		h) syno; usage 1; exit;;
		v) echo -e "\n${0##*/} v.${VERSION}"; exit;;
		f) FILE="$OPTARG"; if [[ ! -e "$FILE" ]]; then
			echo Current directory: $(pwd)
			echo $FILE does not exist.
			read -p "Ignore this option and continue? (y/N) " Q
			[ ! "${Q,,}" = 'y' ] && exit
		   fi;;
	esac
done

# Here we go ------------------------------------
shift `expr $OPTIND - 1` 	# Remove the options parsed above.
ISO="$1"		# Path/name of the official arch installation iso image
((${#ISO})) || { usage 1; echo -e "\e[1mMissing parameter.\e[0m"; exit;}
if [[ -f "$ISO" ]]; then
  path=$(basepath $ISO) 		# Root (/) based path.
  ISO=${path}/${ISO##*/} 		# Full path file name.
else
  echo -e "\nFile \e[1m${ISO}\e[0m not found."
  exit
fi

# START -----------------------------------------

# Unpack the chosen architecture files from ISO to ./archiso/
if [[ -d "$AIDIR" ]]; then
  echo "${AIDIR} exist" 1>&2
  exit 1
else
  mkdir -p "$AIDIR"
fi

# ----------------
echo "Mount $ISO to ${AIDIR}"
fuseiso "$ISO" "$AIDIR" 2>/dev/null
(($?)) && { echo $ISO; echo $AIDIR; echo "Mount error"; exit 2;}

# ----------------
echo "Copying ${AIDIR}/* to ${path}/archiso"
rm -rf ${path}/archiso
mkdir -p ${path}/archiso
cp -apr $AIDIR/* "${path}/archiso"
fusermount -u $AIDIR 		# Not needed any longer
rm -r $AIDIR

# ----------------
echo "Modifying archiso/arch/boot/syslinux/archiso.cfg"
chmod u+w -R ${path}/archiso/syslinux
sed -i 's|^TIMEOUT.*|TIMEOUT 2|' ${path}/archiso/syslinux/archiso_sys.cfg
chmod u-w -R ${path}/archiso/syslinux
ISO_LABEL=$(sed -n 's|.*\sarchisolabel=\([^\s]*\)$|\1|p' ${path}/archiso/syslinux/archiso_sys-linux.cfg)
# ----------------
echo "Unsquashing archiso/arch/${ARCH}/${ROOTFS_SFS} to ${path}/${ROOTFSD}."
if [ -d "${path}/${ROOTFSD}" ]; then
  chmod u+w -R ${path}/${ROOTFSD}
  rm -rf ${path}/${ROOTFSD}
fi
unsquashfs -no -d ${path}/$ROOTFSD "${path}/archiso/arch/${ARCH}/${ROOTFS_SFS}"
(($?)) && exit 1

# ----------------
echo "Modifying files in /${path}/${ROOTFSD} to enable sshd.service at boot."
ln -s /usr/lib/systemd/system/sshd.service ${path}/${ROOTFSD}/etc/systemd/system/multi-user.target.wants/

# ----------------
echo "Allowing an empty password for ssh server."
sed -i 's/#PermitEmpty.*/PermitEmptyPasswords yes/;' ${path}/$ROOTFSD/etc/ssh/sshd_config
#   # Copy file or folder contents to ISO's /usr/local/bin folder.
#   if [[ -e "$FILE" ]]; then
#     echo -n "Copying ${FILE%/}"
#     [[ -f "$FILE" ]] && echo && \
#       sudo cp "$FILE" /mnt/$ROOTFSD/usr/local/bin/
#     [[ -d "$FILE"  ]] && echo '/*' && \
#       sudo cp "${FILE%/}"/* /mnt/$ROOTFSD/usr/local/bin/ 2>/dev/null
#     echo -e "\tinto ISO's /usr/local/bin/ folder.\n"
#   fi
#
#   if (($BREAK)); then
#     echo -ne "\e[32m"
#     echo "ARCH=$ARCH" | sudo tee /mnt/archiso-${USER}-params
#     echo "path=$path" | sudo tee -a /mnt/archiso-${USER}-params
#     echo "ISO=$ISO"  #| sudo tee -a /mnt/archiso-${USER}-params
#     echo -e "\e[1mScript halted.\e[0m"
#     echo You can re-run it without parameters to create an ISO,
#     echo or with the flag \'-c\' to abandon the task and clean up.
#     echo -e "Unsquashed and modified root file system on\e[1m /mnt/$ROOTFSD\e[0m"
#     warn_incompatibility $ARCH
#     exit
#   fi
# else	# Assume that BREAK was used in the previous run, and resume the script.
#      # Options are ignored if BREAK was used in previous run.
#   echo -e "\n\e[32mFile /mnt/$AIDIR-params found."
#   if (($CLEAN)); then
#     echo -e "The -c flag invoked.\e[0m\n"
#   else
#     echo "Resuming the halted script with previous parameters."
#     echo -e "Ignoring the current parameters.\e[0m"
#   fi
#   source /mnt/$AIDIR-params 	# Read parameters; Needed for cleanig, too.
#   sudo rm /mnt/archiso-${USER}-params
# fi
#
# if [[ $CLEAN -eq 0 ]]; then 	# Create a modified iso file

# ----------------
echo "Create new squashfs"
rm -f ${path}/${ROOTFS_SFS}
mksquashfs ${path}/$ROOTFSD ${path}/${ROOTFS_SFS}
(($?)) &&  exit 1

# ----------------
echo "Copy new squashfs"
chmod u+w -R ${path}/archiso/arch
mv -f ${path}/${ROOTFS_SFS} "${path}/archiso/arch/${ARCH}/${ROOTFS_SFS}"
CURDIR="$PWD"
cd "${path}/archiso/arch/${ARCH}/"
sha512sum ${ROOTFS_SFS} > ${ROOTFS_SFS%.*}.sha512
rm *.sig
chmod u-w -R ${path}/archiso/arch
cd "$CURDIR"

# -----------------------------------------
echo "Generating iso"
ISO_FNAME=$(basename ${ISO%.iso}_openssh.iso)
xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -joliet \
        -joliet-long \
        -rational-rock \
        -volid "${ISO_LABEL}" \
        -appid "ARCH LINUX LIVE/RESCUE CD" \
        -publisher "machsix <machsix@github.com>" \
        -preparer "prepared by github.com/machsix/arch-headless" \
        -eltorito-alt-boot \
        -eltorito-boot syslinux/isolinux.bin \
        -eltorito-catalog syslinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -no-emul-boot \
        -output "${path}/${ISO_FNAME}" \
        "${path}/archiso/"


# Cleanup
chmod u+w -R ${path}/${ROOTFSD}
rm -rf ${path}/${ROOTFSD}

chmod u+w -R ${path}/archiso
rm -rf ${path}/archiso
