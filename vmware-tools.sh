#!/bin/sh

pacman -S wget unzip git linux-headers-$(uname -r)

for x in {0..6}; do mkdir -p /etc/init.d/rc$x.d; done
git clone https://github.com/rasa/vmware-tools-patches
cd vmware-tools-patches
./download.sh 7.1.1
./untar-and-patch.sh
cd vmware-tools-distrib
./vmware-install.pl
