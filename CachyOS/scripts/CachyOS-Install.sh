#!/bin/bash

# Connect to the Internet
echo "Checking internet connection"
ping -c 1 cachy.sunaarisu.de
if [ $? -eq 0 ]; then 
  echo "Connected"
else 
  printf "Try Wifi connection:\n\n"
  read -r -p "SSID: " wifissid
  read -r -p "Password: " wifipwd
  iwctl --passphrase $wifipwd station wlan0 connect $wifissid
  ping -c 1 archlinux.org
  if [ $? -eq 0 ]; then
    printf "\nConnected"
  else
    printf "\nConnection Error"
    exit 1
  fi
fi
clear

# Get needed variables and settings
# Disk selection
printf "Which disk should be partitioned?\n\n"
lsblk
printf "\n\n"
read -r -p "/dev/" partDisk
clear
# Encrypt disk
read -r -p "Should the root disk be encrypted? [y/N] " encrypt
clear
# Hostname
read -r -p "Hostname: " hn
clear
# User setup
read -r -p "Username: " user
read -r -p "Password: " user_pass
read -r -p "Use same Password for root? [y/N] " user_pass_same_as_root
if [[ "$user_pass_same_as_root" =~ ^([yY][eE][sS]|[yY])$ ]]
then 
  root_pass=$user_pass
else
  read -r -p "Root Password: " root_pass
fi

# Write all output to installer.log
exec 3>&1 4>&2
exec &> ./installer.log

# Update the system clock
timedatectl

# Partition the disks
sgdisk --zap-all /dev/${partDisk}
parted --script /dev/${partDisk} \
    mklabel gpt \
    mkpart primary fat32 1MiB 4099MiB \
    set 1 esp on \
    mkpart Linux btrfs 4100MiB 100%

# Format the Partitions
if [[ $partDisk == *"nvme"* ]]; then
  partDisk="${partDisk}p"
  zstd="1"
else
  zstd="2"
fi

mkfs.fat -F 32 /dev/${partDisk}1

if [[ "$encrypt" =~ ^([yY][eE][sS]|[yY])$ ]]
then
  cryptsetup luksFormat /dev/${partDisk}2
  cryptsetup open /dev/${partDisk}2 cryptroot
  mkfs.btrfs /dev/mapper/cryptroot
  rootDisk="/dev/mapper/cryptroot"  
else
  mkfs.btrfs /dev/${partDisk}2
  rootDisk="/dev/${partDisk}2"
fi
mount ${rootDisk} /mnt

# Create subvolumes
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var_log
btrfs subvolume create /mnt/@var_cache
btrfs subvolume create /mnt/@snapshots

# Mount the file system
umount /mnt
mount -o compress=zstd:${zstd},noatime,subvol=@ ${rootDisk} /mnt
mount --mkdir -o compress=zstd:${zstd},noatime,subvol=@home ${rootDisk} /mnt/home
mount --mkdir -o compress=zstd:${zstd},noatime,subvol=@var_log ${rootDisk} /mnt/var/log
mount --mkdir -o compress=zstd:${zstd},noatime,subvol=@var_cache ${rootDisk} /mnt/var/cache
mount --mkdir -o compress=zstd:${zstd},noatime,subvol=@snapshots ${rootDisk} /mnt/.snapshots
mount --mkdir /dev/${partDisk}1 /mnt/boot
mkdir -p /mnt/boot/EFI/BOOT/

# Install essential packages
pacman -Syyu --noconfirm
pacstrap -K /mnt base base-devel linux linux-firmware util-linux ufw pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber sof-firmware bluez bluez-utils btrfs-progs limine efibootmgr nvim networkmanager man btop fastfetch git tree sudo alacritty memtest86+-efi

# Generate fstab
genfstab /mnt > /mnt/etc/fstab
echo "/boot/EFI/limine /boot/EFI/BOOT none bind,defaults 0 0"

# Set hostname
echo $hn > /mnt/etc/hostname

# Setup Locale
arch-chroot /mnt /bin/bash <<END
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
hwclock --systohc
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf
echo KEYMAP=dvorak > /etc/vconsole.conf
END

# Setup User
arch-chroot /mnt /bin/bash <<END
useradd -m -g users -G wheel ${user}
echo -e "root:${root_pass}\n${user}:${user_pass}" | chpasswd
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
END

# Setup Swap
arch-chroot /mnt /bin/bash <<END
  btrfs subvolume create /swap
  btrfs filesystem mkswapfile --size $(awk '/MemTotal/ {print int(($2 / 1000 / 1000) + 1)}' /proc/meminfo)g --uuid clear /swap/swapfile
  swapon -p 0 /swap/swapfile
  echo "/swap/swapfile none swap defaults,pri=0 0 0" >> /etc/fstab
END

# Edit mkinitcpio
arch-chroot /mnt /bin/bash <<END
sed -i 's/MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
sed -i 's/BINARIES=()/BINARIES=(\/usr\/bin\/btrfs)/' /etc/mkinitcpio.conf
if [[ "$encrypt" =~ ^([yY][eE][sS]|[yY])$ ]]
then
  sed -i 's/HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems resume fsck)/' /etc/mkinitcpio.conf
else  
  sed -i 's/HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems resume fsck)/' /etc/mkinitcpio.conf
fi
mkinitcpio -P
END

# Setup limine bootloader
arch-chroot /mnt /bin/bash <<END
mkdir -p /boot/EFI/limine
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/limine/
efibootmgr --create --disk /dev/${partDisk} --part 1 \
      --label "CachyOS Linux Limine Bootloader" \
      --loader '\EFI\limine\BOOTX64.EFI' \
      --unicode

if [[ "$encrypt" =~ ^([yY][eE][sS]|[yY])$ ]]
then
  echo "timeout: 1
  default_entry: 2

  /+Arch Linux
  comment: $(cat /etc/machine-id)

      //Arch Linux
          protocol: linux
          path: boot():/vmlinuz-linux
          cmdline: quiet cryptdevice=UUID=$(cryptsetup luksUUID /dev/${partDisk}2):root root=/dev/mapper/cryptroot rw rootflags=subvol=@ rootfstype=btrfs
          module_path: boot():/initramfs-linux.img

      //Arch Linux (fallback)
          protocol: linux
          path: boot():/vmlinuz-linux
          cmdline: quiet cryptdevice=UUID=$(cryptsetup luksUUID /dev/${partDisk}2):root root=/dev/mapper/cryptroot rw rootflags=subvol=@ rootfstype=btrfs
          module_path: boot():/initramfs-linux-fallback.img
  
  /Helper Programs
      
      //Memtest86+
          protocol: efi
          path: boot():/memtest86+/memtest.efi" > /boot/EFI/limine/limine.conf
else
  echo "timeout: 1
  default_entry: 2

  /+Arch Linux
  comment: $(cat /etc/machine-id)
  
      //Arch Linux
          protocol: linux
          path: boot():/vmlinuz-linux
          cmdline: quiet root=UUID=$(blkid -o value -s UUID /dev/${partDisk}2) rw rootflags=subvol=@ rootfstype=btrfs
          module_path: boot():/initramfs-linux.img

      //Arch Linux (fallback)
          protocol: linux
          path: boot():/vmlinuz-linux
          cmdline: quiet root=UUID=$(blkid -o value -s UUID /dev/${partDisk}2) rw rootflags=subvol=@ rootfstype=btrfs
          module_path: boot():/initramfs-linux-fallback.img

  /Helper Programs
      
      //Memtest86+
          protocol: efi
          path: boot():/memtest86+/memtest.efi" > /boot/EFI/limine/limine.conf
fi
END

arch-chroot /mnt /bin/bash <<END
systemctl enable NetworkManager
systemctl enable bluetooth
END

# Ly Setup
arch-chroot /mnt /bin/bash <<END
pacman -S ly brightnessctl --noconfirm
systemctl enable ly@tty1.service
END

# QTile Setup
arch-chroot /mnt /bin/bash <<END
pacman -S qtile ttf-jetbrains-mono-nerd xorg-xwayland --noconfirm
END

# arch-chroot /mnt /bin/bash <<END
# # Keyboard config
# curl --create-dirs -LJO --output-dir /usr/share/X11/xkb/symbols/custom https://raw.githubusercontent.com/SunaaRisu/Arch-Linux-Install/refs/heads/main/Arch-Hyprland-WM/Laptop/kb/custom

# # Bash config
# curl --create-dirs -LJO --output-dir /home/sunaa/ https://raw.githubusercontent.com/SunaaRisu/Arch-Linux-Install/refs/heads/main/.bashrc
# END

# Install Paru
read -r -p "Install Paru? [y|N]" responseParu
arch-chroot /mnt /bin/bash <<END
if [[ "$responseParu" =~ ^([yY][eE][sS]|[yY])$ ]]
then
  mkdir aur
  cd aur
  git clone https://aur.archlinux.org/paru.git
  cd paru
  makepkg -si
  cd ../..
  rm -r aur
fi
END

# rofi Setup
arch-chroot /mnt /bin/bash <<END
pacman -S rofi --noconfirm
END

#   git clone https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme.git
#   ./Gruvbox-GTK-Theme/themes/install.sh
#   sudo rm -r Gruvbox-GTK-Theme
#   gsettings set org.gnome.desktop.interface gtk-theme Gruvbox-Dark
#   sed -i 's/gtk-icon-theme-name = Adwaita/gtk-icon-theme-name = Gruvbox-Dark' /usr/share/gtk-3.0/settings.ini
#   sed -i 's/gtk-theme-name = Adwaita/gtk-theme-name = Gruvbox-Dark' /usr/share/gtk-3.0/settings.ini
#   sed -i 's/gtk-icon-theme-name = Adwaita/gtk-icon-theme-name = Gruvbox-Dark' /usr/share/gtk-4.0/settings.ini
#   sed -i 's/gtk-theme-name = Adwaita/gtk-theme-name = Gruvbox-Dark' /usr/share/gtk-4.0/settings.ini

arch-chroot /mnt /bin/bash <<END
timedatectl
timedatectl set-ntp true
END

# stop the redirect to installer.log
exec 1>&3 2>&4
exec 3>&- 4>&-

clear
echo -e "Installation finished.\n\n\n"
arch-chroot /mnt fastfetch
echo -e "\n\n\n"
read -r -p "Press any key to reboot into CachyOS." key
umount -a
reboot
