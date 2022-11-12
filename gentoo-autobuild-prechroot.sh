#!/usr/bin/env bash

# FILE: gentoo-autobuild-prechroot.sh
#
# Generate a gentoo basesystem.
#
# Copyright (c) 2020,2022 Bryan Michael Baldwin
#

# NOTE: All commands in this guide are assumed to be run as the root user!



#
# -- FUNCTIONS
#

function partition_gpt_volume() {
        root_vol=$1
        parted -a optimal ${root_vol} -- mklabel gpt
        parted -a optimal ${root_vol} -- mkpart pri 1M 3M
        parted -a optimal ${root_vol} -- mkpart pri 3M 131M
        parted -a optimal ${root_vol} -- mkpart pri 131M 643M
        parted -a optimal ${root_vol} -- mkpart pri 643M -1

        parted -a optimal ${root_vol} -- name 1 grub
        parted -a optimal ${root_vol} -- name 2 boot
        parted -a optimal ${root_vol} -- name 3 swap
        parted -a optimal ${root_vol} -- name 4 root

        parted -a optimal ${root_vol} -- set 1 bios_grub on
        parted -a optimal ${root_vol} -- set 2 boot on

        mkfs.vfat -F32 -n boot ${root_vol}2
        mkswap -L swap ${root_vol}3
        mkfs.ext4 -L root ${root_vol}4
}



#
# -- Start SSH
#
#    Used on running machine when orchestrated from a remote terminal
#
# 1. Enable the SSH service on the target machine
#rc-service sshd start
# 2. Generate keys for the root user
#ssh-keygen
#	a. Press [ENTER] three times to complete the keygen process
# 3. Set the root user passwd
#passwd
#	a. You will be prompted to enter the new password twice



#
# -- Prepare the disks
#
#    WARNING: The operations in this section will permanently erase *all* data
#

# Zero-fill all volumes to silence discovered old partition(s) and disk labels.
# Could be a better way to achieve this, not sure, should look for it.
for i in a b c d e; do dd if=/dev/zero of=/dev/vd${i} bs=100M status=progress; done



#
# -- Partition the disk(s)
#

partition_gpt_volume "/dev/vda"
for i in b c d e; do
        parted -a optimal /dev/vd${i} -- mklabel gpt
        parted -a optimal /dev/vd${i} -- mkpart pri 0% 100%
        case ${i} in
                b)
                        parted -a optimal /dev/vd${i} -- name 1 kernel
                        mkfs.ext4 -L kernel /dev/vd${i}1
                        ;;
                c)
                        parted -a optimal /dev/vd${i} -- name 1 distfiles
                        mkfs.ext4 -L distfiles /dev/vd${i}1
                        ;;
                d)
                        parted -a optimal /dev/vd${i} -- name 1 portage
                        mkfs.ext4 -L portage -i 4096 /dev/vd${i}1
                        ;;
                e)
                        parted -a optimal /dev/vd${i} -- name 1 temp
                        mkfs.ext4 -L temp /dev/vd${i}1
                        ;;
        esac
done



#
# -- Mount filesystems
#

mount /dev/vda4 /mnt/gentoo
mkdir -pv /mnt/gentoo/boot
mount /dev/vda2 /mnt/gentoo/boot
mkdir -pv /mnt/gentoo/usr/src
mount /dev/vdb1 /mnt/gentoo/usr/src
mkdir -pv /mnt/gentoo/var/cache/distfiles
mount /dev/vdc1 /mnt/gentoo/var/cache/distfiles
mkdir -pv /mnt/gentoo/var/db/repos
mount /dev/vdd1 /mnt/gentoo/var/db/repos
mkdir -pv /mnt/gentoo/var/tmp/portage
mount /dev/vde1 /mnt/gentoo/var/tmp/portage



#
# -- Install the stage 3 tarball
#

RELEASE_URL="http://192.168.20.3/gentoo/releases/amd64/autobuilds"
STAGE3_URI=`wget --quiet -O- ${RELEASE_URL}/latest-stage3-amd64-openrc.txt | grep -vi '^#' | cut -d' ' -f1`
wget -O- ${RELEASE_URL}/${STAGE3_URI} | tar xpfJ - -C /mnt/gentoo



#
# -- Pre chroot
#

cd /mnt/gentoo
mount -t proc none proc
mount --rbind /dev dev
mount --rbind /sys sys
mount --make-rslave dev
mount --make-rslave sys
rsync -rav /etc/resolv.conf etc/
chroot /mnt/gentoo /bin/bash

