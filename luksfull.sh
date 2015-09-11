#!/usr/bin/env bash

parted -s /dev/sda mklabel msdos
parted -s /dev/sda mkpart primary 2048s 100%
cryptsetup luksFormat /dev/sda1
cryptsetup luksOpen /dev/sda1 lvm
pvcreate /dev/mapper/lvm
vgcreate vg /dev/mapper/lvm
lvcreate -L 4G vg -n swap
lvcreate -L 36G vg -n root
lvcreate -l +100%FREE vg -n home
mkswap -L swap /dev/mapper/vg-swap
mkfs.ext4 /dev/mapper/vg-root
mkfs.ext4 /dev/mapper/vg-home
mount /dev/mapper/vg-root /mnt
mkdir /mnt/home
mount /dev/mapper/vg-home /mnt/home