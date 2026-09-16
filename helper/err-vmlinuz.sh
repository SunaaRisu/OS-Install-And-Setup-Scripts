#!/bin/bash

read -r -p "Which filesystem? [btrfs=1,ext4=2] (default: 1)" fs

if [ $fs -eq 2 ]
then
cryptsetup open /dev/nvme0n1p2 cryptroot
mount /dev/mapper/cryptroot /mnt
mount /dev/nvme0n1p1 /mnt/boot
else
zstd="1"
rootDisk="/dev/nvme0n1p2"
mount -o compress=zstd:${zstd},noatime,subvol=@ ${rootDisk} /mnt
mount --mkdir -o compress=zstd:${zstd},noatime,subvol=@home ${rootDisk} /mnt/home
mount --mkdir -o compress=zstd:${zstd},noatime,subvol=@var_log ${rootDisk} /mnt/var/log
mount --mkdir -o compress=zstd:${zstd},noatime,subvol=@var_cache ${rootDisk} /mnt/var/cache
mount --mkdir -o compress=zstd:${zstd},noatime,subvol=@snapshots ${rootDisk} /mnt/.snapshots
mount --mkdir /dev/nvme0n1p1 /mnt/boot
fi
arch-chroot /mnt pacman -S linux
umount -a
reboot
