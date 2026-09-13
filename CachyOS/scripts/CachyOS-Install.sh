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
clear -x

# Get needed variables and settings
# Disk selection
printf "Which disk should be partitioned?\n\n"
lsblk
printf "\n\n"
read -r -p "/dev/" partDisk
clear -x
# Encrypt disk
read -r -p "Should the root disk be encrypted? [y/N] " encrypt
clear -x
# Hostname
read -r -p "Hostname: " hn
clear -x

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
mount -o subvol=@ ${rootDisk} /mnt
mount --mkdir -o subvol=@home ${rootDisk} /mnt/home
mount --mkdir -o subvol=@var_log ${rootDisk} /mnt/var/log
mount --mkdir -o subvol=@var_cache ${rootDisk} /mnt/var/cache
mount --mkdir -o subvol=@snapshots ${rootDisk} /mnt/.snapshots
mount --mkdir /dev/${partDisk}1 /mnt/boot

# Install essential packages
pacman -Syyu
pacstrap -K /mnt base base-devel linux linux-firmware util-linux ufw pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber sof-firmware bluez bluez-utils btrfs-progs limine efibootmgr nvim networkmanager man btop fastfetch git tree sudo

# Generate fstab
genfstab /mnt > /mnt/etc/fstab

# Set hostname
echo $hn > /mnt/etc/hostname

# Changing root
arch-chroot /mnt /bin/bash <<END
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
hwclock --systohc
sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf
echo KEYMAP=dvorak > /etc/vconsole.conf




passwd
useradd -m -g users -G wheel sunaa
passwd sunaa
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Edit mkinitcpio
sed -i 's/MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
sed -i 's/BINARIES=()/BINARIES=(/usr/bin/btrfs)/' /etc/mkinitcpio.conf
if [[ "$encrypt" =~ ^([yY][eE][sS]|[yY])$ ]]
then
  sed -i 's/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems resume fsck)/' /etc/mkinitcpio.conf
else  
  sed -i 's/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems resume fsck)/' /etc/mkinitcpio.conf
fi
mkinitcpio -P

# Setup limine bootloader
mkdir -p /boot/EFI/limine
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/limine/
efibootmgr --create --disk /dev/${partDisk} --part 1 \
      --label "Arch Linux Limine Bootloader" \
      --loader '\EFI\limine\BOOTX64.EFI' \
      --unicode

if [[ "$encrypt" =~ ^([yY][eE][sS]|[yY])$ ]]
then
  echo "timeout: 3

  /Arch Linux
      protocol: linux
      path: boot():/vmlinuz-linux
      cmdline: quiet cryptdevice=UUID=$(cryptsetup luksUUID /dev/${partDisk}2):root root=/dev/mapper/cryptroot rw rootflags=subvol=@ rootfstype=btrfs
      module_path: boot():/initramfs-linux.img

  /Arch Linux (fallback)
      protocol: linux
      path: boot():/vmlinuz-linux
      cmdline: quiet cryptdevice=UUID=$(cryptsetup luksUUID /dev/${partDisk}2):root root=/dev/mapper/cryptroot rw rootflags=subvol=@ rootfstype=btrfs
      module_path: boot():/initramfs-linux-fallback.img
  
  /Memtest86+
    protocol: efi
    path: boot():/memtest86+/memtest.efi" > /boot/EFI/limine/limine.conf
else
  echo "timeout: 3

  /Arch Linux
      protocol: linux
      path: boot():/vmlinuz-linux
      cmdline: quiet root=$(blkid -o value -s UUID /dev/${partDisk}2) rw rootflags=subvol=@ rootfstype=btrfs
      module_path: boot():/initramfs-linux.img

  /Arch Linux (fallback)
      protocol: linux
      path: boot():/vmlinuz-linux
      cmdline: quiet root=$(blkid -o value -s UUID /dev/${partDisk}2) rw rootflags=subvol=@ rootfstype=btrfs
      module_path: boot():/initramfs-linux-fallback.img
  
  /Memtest86+
    protocol: efi
    path: boot():/memtest86+/memtest.efi" > /boot/EFI/limine/limine.conf"
fi

systemctl enable NetworkManager

# # Greetd config
# pacman -S greetd

# sed -i 's/command = "agreety*/command = "agreety --cmd start-hyprland"

# systemctl enable greetd.service

# # Grub config
# sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=0/' /etc/default/grub
# grub-mkconfig -o /boot/grub/grub.cfg

# # Keyboard config
# curl --create-dirs -LJO --output-dir /usr/share/X11/xkb/symbols/custom https://raw.githubusercontent.com/SunaaRisu/Arch-Linux-Install/refs/heads/main/Arch-Hyprland-WM/Laptop/kb/custom

# # Bash config
# curl --create-dirs -LJO --output-dir /home/sunaa/ https://raw.githubusercontent.com/SunaaRisu/Arch-Linux-Install/refs/heads/main/.bashrc

# # Neovim config
# read -r -p "Config Neovim? [y|N]" response
# if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
# then
#   pacman -S npm cargo unzip
#   cp -r ./Arch-Linux-Install/nvim/ /home/sunaa/.config/
# else
# fi

# # Install Paru
# read -r -p "Install Paru? [y|N]" response
# if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
# then
#   mkdir aur
#   cd aur
#   git clone https://aur.archlinux.org/paru.git
#   cd paru
#   makepkg -si
#   cd ../..
#   rm -r aur
# fi

# # Hyprland config

# read -r -p "Install Hyprland? [y|N]" response
# if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
# then
#   sudo pacman -S hyprland waybar hyprpaper alacritty wofi dolphin ttf-font-awesome ttf-jetbrains-mono-nerd pulseaudio pavucontrol mako nwg-look git openssh
#   git clone https://github.com/SunaaRisu/Arch-Linux-Install.git
#   cp ./Arch-Linux-Install/Arch-Hyprland-WM/Laptop/hyprland.conf /home/sunaa/.config/hypr/hyprland.conf
#   cp ./Arch-Linux-Install/Arch-Hyprland-WM/Laptop/waybar/config /home/sunaa/.config/waybar/config
#   cp ./Arch-Linux-Install/Arch-Hyprland-WM/Laptop/waybar/style.css /home/sunaa/.config/waybar/style.css
  
#   git clone https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme.git
#   ./Gruvbox-GTK-Theme/themes/install.sh
#   sudo rm -r Gruvbox-GTK-Theme
#   gsettings set org.gnome.desktop.interface gtk-theme Gruvbox-Dark
#   sed -i 's/gtk-icon-theme-name = Adwaita/gtk-icon-theme-name = Gruvbox-Dark' /usr/share/gtk-3.0/settings.ini
#   sed -i 's/gtk-theme-name = Adwaita/gtk-theme-name = Gruvbox-Dark' /usr/share/gtk-3.0/settings.ini
#   sed -i 's/gtk-icon-theme-name = Adwaita/gtk-icon-theme-name = Gruvbox-Dark' /usr/share/gtk-4.0/settings.ini
#   sed -i 's/gtk-theme-name = Adwaita/gtk-theme-name = Gruvbox-Dark' /usr/share/gtk-4.0/settings.ini
  
#   cp -r ./Arch-Linux-Install/images/ /home/sunaa/.config/hypr/
#   cp Arch-Linux-Install/Arch-Hyprland-WM/Laptop/hyprpaper.conf /home/sunaa/.config/hypr/hyprpaper.conf
# fi

# exit
# umount -a
# reboot
END

clear -x
echo FERTIG