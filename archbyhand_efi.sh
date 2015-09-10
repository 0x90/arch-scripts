#!/bin/bash

# prereqs:
# --------------------
# mount /dev/sdb1 /src

# ------------------------------------------------------------------------
# NOTE: THIS IS JUST A ROUGH SAMPLE. SEE THE CRYPT VERSION OF THIS 
# SCRIPT FOR A MORE DETAILED EXAMPLE WITH BETTER COMMENTS
# ------------------------------------------------------------------------

set -o nounset
#set -o errexit

INSTALL_TARGET="/install"
HR="--------------------------------------------------------------------------------"
PACMAN="pacman --noconfirm --config /tmp/pacman.conf"
TARGET_PACMAN="pacman --noconfirm --config /tmp/pacman.conf -r ${INSTALL_TARGET}"
FILE_URL="file:///packages/core-$(uname -m)/pkg"
FTP_URL='ftp://mirrors.kernel.org/archlinux/$repo/os/$arch'
HTTP_URL='http://mirrors.kernel.org/archlinux/$repo/os/$arch'

# ------------------------------------------------------------------------
# Initialize
# ------------------------------------------------------------------------

# Warn
# ------------------------------------------------------------------------
timer=9
timer=1
echo -n "This procedure will completely format /dev/sda. Please cancel with ctrl-c to cancel within $timer seconds..."
while [[ $timer -gt 0 ]]
do
	sleep 1
	let timer-=1
	echo -en "$timer seconds..."
done

echo "STARTING"

# Get Network
# ------------------------------------------------------------------------
echo -n "Waiting for network address.."
#dhclient eth0
dhcpcd -p eth0
echo -n "Network address acquired."

# Mount packages squashfs images
# ------------------------------------------------------------------------
umount "/packages/core-$(uname -m)"
umount "/packages/core-any"
rm -rf "/packages/core-$(uname -m)"
rm -rf "/packages/core-any"

mkdir -p "/packages/core-$(uname -m)"
mkdir -p "/packages/core-any"

modprobe -q loop
modprobe -q squashfs
mount -o ro,loop -t squashfs "/src/packages/archboot_packages_$(uname -m).squashfs" "/packages/core-$(uname -m)"
mount -o ro,loop -t squashfs "/src/packages/archboot_packages_any.squashfs" "/packages/core-any"

# Create temporary pacman.conf file
# ------------------------------------------------------------------------
cat << PACMANEOF > /tmp/pacman.conf
[options]
Architecture = auto
CacheDir = ${INSTALL_TARGET}/var/cache/pacman/pkg
CacheDir = /packages/core-$(uname -m)/pkg
CacheDir = /packages/core-any/pkg

[core]
Server = ${FILE_URL}
Server = ${FTP_URL}
Server = ${HTTP_URL}

[extra]
Server = ${FILE_URL}
Server = ${FTP_URL}
Server = ${HTTP_URL}
PACMANEOF

# Prepare pacman
# ------------------------------------------------------------------------
[[ ! -d "${INSTALL_TARGET}/var/cache/pacman/pkg" ]] && mkdir -m 755 -p "${INSTALL_TARGET}/var/cache/pacman/pkg"
[[ ! -d "${INSTALL_TARGET}/var/lib/pacman" ]] && mkdir -m 755 -p "${INSTALL_TARGET}/var/lib/pacman"
${PACMAN} -Sy
${TARGET_PACMAN} -Sy

# Install prereqs from network (not on archboot media)
# ------------------------------------------------------------------------
echo -e "\nInstalling prereqs...\n$HR"
sed -i "s/^#S/S/" /etc/pacman.d/mirrorlist
${PACMAN} --noconfirm -Sy gptfdisk btrfs-progs-unstable

# ------------------------------------------------------------------------
# Configure Host
# ------------------------------------------------------------------------

echo -e "\nFormatting disk...\n$HR"

# disk prep
sgdisk -Z /dev/sda # zap all on disk
sgdisk -a 2048 -o /dev/sda # new gpt disk 2048 alignment

# create partitions
sgdisk -n 1:0:+200M /dev/sda # partition 1 (UEFI BOOT), default start block, 200MB
sgdisk -n 2:0:+4G /dev/sda # partition 2 (SWAP), default start block, 200MB
#sgdisk -n 3:0:0 /dev/sda # partition 3, (LUKS), default start, remaining space
sgdisk -n 3:0:0 /dev/sda # partition 3, (Arch Linux), default start, remaining space

# set partition types
sgdisk -t 1:ef00 /dev/sda
sgdisk -t 2:8200 /dev/sda
sgdisk -t 3:8300 /dev/sda

# label partitions
sgdisk -c 1:"UEFI Boot" /dev/sda
sgdisk -c 2:"Swap" /dev/sda
sgdisk -c 3:"LUKS" /dev/sda

# make filesystems
echo -e "\nCreating Filesystems...\n$HR"
mkfs.vfat /dev/sda1
mkswap /dev/sda2
mkfs.ext4 /dev/sda3

# mount target
mkdir ${INSTALL_TARGET}
mount /dev/sda3 ${INSTALL_TARGET}
mkdir ${INSTALL_TARGET}/boot
mount -t vfat /dev/sda1 ${INSTALL_TARGET}/boot

# ------------------------------------------------------------------------
# Install Base
# ------------------------------------------------------------------------

mkdir -p ${INSTALL_TARGET}/var/lib/pacman
${TARGET_PACMAN} -Sy
${TARGET_PACMAN} -Su base

# ------------------------------------------------------------------------
# Prepare to chroot to target
# ------------------------------------------------------------------------

mv ${INSTALL_TARGET}/etc/resolv.conf ${INSTALL_TARGET}/etc/resolv.conf.orig
cp /etc/resolv.conf ${INSTALL_TARGET}/etc/resolv.conf
#mv ${INSTALL_TARGET}/etc/pacman.d/mirrorlist ${INSTALL_TARGET}/etc/pacman.d/mirrorlist.orig
#cp /etc/pacman.d/mirrorlist ${INSTALL_TARGET}/etc/pacman.d/mirrorlist
#mv ${INSTALL_TARGET}/etc/pacman.conf ${INSTALL_TARGET}/etc/pacman.conf.orig
#cp /etc/pacman.conf ${INSTALL_TARGET}/etc/pacman.conf
mkdir -p ${INSTALL_TARGET}/tmp
cp /tmp/pacman.conf ${INSTALL_TARGET}/tmp/pacman.conf
mount -t proc proc ${INSTALL_TARGET}/proc
mount -t sysfs sys ${INSTALL_TARGET}/sys
mount -o bind /dev ${INSTALL_TARGET}/dev
echo -e "${HR}\nINSTALL BASE COMPLETE\n${HR}"

# umount or things get confused. yes, really.
umount ${INSTALL_TARGET}/boot

# ------------------------------------------------------------------------
# Write Files
# ------------------------------------------------------------------------

# install_efi (to be run *after* chroot /install)
# ------------------------------------------------------------------------
touch ${INSTALL_TARGET}/install_efi
chmod a+x ${INSTALL_TARGET}/install_efi
cat > ${INSTALL_TARGET}/install_efi <<EFIEOF
# remount here or grub et al gets confused
mount -t vfat /dev/sda1 /boot

##mkdir -p /boot/efi
#mkdir -p /boot
#mount -t vfat /dev/sda1 /boot

mkinitcpio -p linux
sed -i "s/#\(en_US\.UTF-8.*$\)/\1/" /etc/locale.gen
locale-gen
modprobe efivars
modprobe dm-mod

#pacman --noconfirm -R grub
#pacman --noconfirm -S grub2-efi-x86_64
${PACMAN} -Sy
${PACMAN} -R grub
${PACMAN} -S grub2-efi-x86_64
grub_efi_x86_64-install --root-directory=/boot --boot-directory=/boot/efi --bootloader-id=grub --no-floppy --recheck
efibootmgr --create --gpt --disk /dev/sda --part 1 --write-signature --label "ARCH LINUX" --loader "\\\\EFI\\\\grub\\\\grub.efi"
grub-mkconfig -o /boot/efi/grub/grub.cfg

exit
EFIEOF

# fstab
# ------------------------------------------------------------------------
cat > ${INSTALL_TARGET}/etc/fstab <<FSEOF
# 
# /etc/fstab: static file system information
#
# <file system>	<dir>		<type>	<options>		<dump>	<pass>
tmpfs		/tmp		tmpfs	nodev,nosuid		0	0
/dev/sda1	/boot		vfat	defaults		0	0 
/dev/sda2	none 		swap	swap			0	0 
/dev/sda3	/ 		ext4	noatime,discard		0	1 
FSEOF

# ------------------------------------------------------------------------
# Install EFI
# ------------------------------------------------------------------------
chroot /install /install_efi
rm /install/install_efi
