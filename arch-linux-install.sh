#!/bin/sh
# Install ARCH Linux with encrypted file-system and UEFI
# The official installation guide (https://wiki.archlinux.org/index.php/Installation_Guide) contains a more verbose description.

# Download the archiso image from https://www.archlinux.org/
# Copy to a usb-drive
dd if=archlinux.img of=/dev/sdX bs=16M && sync # on linux

# Boot from the usb. If the usb fails to boot, make sure that secure boot is disabled in the BIOS configuration.

# Set swedish keymap
loadkeys sv-latin1

# This assumes a wifi only system...
wifi-menu

# Create partitions
cgdisk /dev/sdX
1 100MB EFI partition # Hex code ef00
2 250MB Boot partition # Hex code 8300
3 100% size partiton # (to be encrypted) Hex code 8300

mkfs.vfat -F32 /dev/sdX1
mkfs.ext2 /dev/sdX2

# Setup the encryption of the system
cryptsetup -c aes-xts-plain64 -y --use-random luksFormat /dev/sdX3
cryptsetup luksOpen /dev/sdX3 luks

# Create encrypted partitions
# This creates one partions for root, modify if /home or other partitions should be on separate partitions
pvcreate /dev/mapper/luks
vgcreate vg0 /dev/mapper/luks
lvcreate --size 8G vg0 --name swap
lvcreate -l +100%FREE vg0 --name root

# Create filesystems on encrypted partitions
mkfs.ext4 /dev/mapper/vg0-root
mkswap /dev/mapper/vg0-swap

# Mount the new system 
mount /dev/mapper/vg0-root /mnt # /mnt is the installed system
swapon /dev/mapper/vg0-swap # Not needed but a good thing to test
mkdir /mnt/boot
mount /dev/sdX2 /mnt/boot
mkdir /mnt/boot/efi
mount /dev/sdX1 /mnt/boot/efi

# Install the system also includes stuff needed for starting wifi when first booting into the newly installed system
# Unless vim and zsh are desired these can be removed from the command
pacstrap /mnt base base-devel grub-efi-x86_64 zsh vim git efibootmgr dialog wpa_supplicant

# 'install' fstab
genfstab -pU /mnt >> /mnt/etc/fstab
# Make /tmp a ramdisk (add the following line to /mnt/etc/fstab)
tmpfs	/tmp	tmpfs	defaults,noatime,mode=1777	0	0
# Change relatime on all non-boot partitions to noatime (reduces wear if using an SSD)

# Enter the new system
arch-chroot /mnt /bin/bash

# Setup system clock
ln -s /usr/share/zoneinfo/Europe/Stockholm /etc/localtime
hwclock --systohc --utc

# Set the hostname
echo MYHOSTNAME > /etc/hostname

# Update locale
echo LANG=en_US.UTF-8 > /etc/locale.conf
echo LANGUAGE=en_US > /etc/locale.conf
echo LC_ALL=C > /etc/locale.conf

# Set password for root
passwd

# Add real user remove -s flag if you don't whish to use zsh
# useradd -m -g users -G wheel,storage,power -s /bin/zsh MYUSERNAME
# passwd MYUSERNAME

# Configure mkinitcpio with modules needed for the initrd image
vim /etc/mkinitcpio.conf
# Add 'ext4' to MODULES
# Add 'encrypt' and 'lvm2' to HOOKS before filesystems

# Regenerate initrd image
mkinitcpio -p linux

# Setup grub
grub-install
In /etc/default/grub edit the line GRUB_CMDLINE_LINUX to GRUB_CMDLINE_LINUX="cryptdevice=/dev/sdX3:luks:allow-discards" then run:
grub-mkconfig -o /boot/grub/grub.cfg

# Exit new system and go into the cd shell
exit

# Unmount all partitions
umount -R /mnt
swapoff -a

# Reboot into the new system, don't forget to remove the cd/usb
reboot
