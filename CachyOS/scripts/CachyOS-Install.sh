#!/bin/bash

# Connect to the Internet
ping -c 1 cachy.sunaarisu.de
if [ $? -eq 0 ]; then 
  echo "Connected"
else 
  echo "Try Wifi connection"
  read -r -p "SSID: " wifissid
  read -r -p "Password: " wifipwd
  iwctl --passphrase $wifipwd station wlan0 connect $wifissid
  ping -c 1 archlinux.org
  if [ $? -eq 0 ]; then
    echo "Connected"
  else
    echo "Connection Error"
    exit 1
  fi
fi

# Update the system clock
timedatectl

# Partition the disks
lsblk
echo "Which disk should be partitioned?"
read -r -p "/dev/" partDisk
cfdisk /dev/${partDisk}

# Format the Partitions
if [[ $partDisk == *"nvme"* ]]; then
  partDisk="${partDisk}p"
fi

mkswap /dev/${partDisk}2
mkfs.fat -F 32 /dev/${partDisk}1

read -r -p "Encrypt the disk? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
  cryptsetup luksFormat /dev/${partDisk}3
  cryptsetup open /dev/${partDisk}3 cryptroot
  mkfs.ext4 /dev/mapper/cryptroot

  mount /dev/mapper/cryptroot /mnt
else
  mkfs.ext4 /dev/${partDisk}3
  
  mount /dev/${partDisk}3 /mnt
fi

# Mount the file system
mount --mkdir /dev/${partDisk}1 /mnt/boot
swapon /dev/${partDisk}2

# Install essential packages
pacstrap -K /mnt base linux linux-firmware sof-firmware base-devel grub efibootmgr nvim networkmanager man btop fastfetch git tree sudo

# Generate fstab
genfstab /mnt > /mnt/etc/fstab

# Changing root
arch-chroot /mnt /bin/bash <<END
curl -LJO https://raw.githubusercontent.com/SunaaRisu/OS-Install-And-Setup-Scripts/refs/heads/main/cachyos/scripts/CachyOS-Config.sh
chmod +x CachyOS-Config.sh
./CachyOS-Config.sh
rm CachyOS-Config.sh
END
