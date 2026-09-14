#!/bin/bash

cryptsetup open /dev/nvme0n1p2 cryptroot
mount /dev/mapper/cryptroot /mnt
mount /dev/nvme0n1p1 /mnt/boot
arch-chroot /mnt pacman -S linux
umount -a
reboot
