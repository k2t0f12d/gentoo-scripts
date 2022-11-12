#!/usr/bin/env bash

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
