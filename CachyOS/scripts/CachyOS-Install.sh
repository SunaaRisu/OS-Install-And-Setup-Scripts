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


# Update the system clock
timedatectl

# Partition the disks
sgdisk --zap-all /dev/${partDisk}
parted --script /dev/${partDisk} \
    mklabel gpt \
    mkpart primary fat32 1MiB 4099MiB \
    set 1 esp on \
    mkpart primary "" 4100MiB 12299MiB \
    set 2 swap on \
    mkpart primary ext4 12300MiB 100%

# Format the Partitions
if [[ $partDisk == *"nvme"* ]]; then
  partDisk="${partDisk}p"
fi

mkswap /dev/${partDisk}2
mkfs.fat -F 32 /dev/${partDisk}1

if [[ "$encrypt" =~ ^([yY][eE][sS]|[yY])$ ]]
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
pacman -Syyu
pacstrap -K /mnt base base-devel linux linux-firmware btrfs-progs limine efibootmgr nvim networkmanager bash-completion man btop fastfetch git tree sudo

# Generate fstab
genfstab /mnt > /mnt/etc/fstab










exit 0




















# Changing root
arch-chroot /mnt /bin/bash <<END
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
hwclock --systohc
sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf
echo KEYMAP=dvorak > /etc/vconsole.conf
read -r -p "Hostname: " hn
echo $hn > /etc/hostname
passwd
useradd -m -g users -G wheel sunaa
passwd sunaa
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
read -r -p "Disk: /dev/" partDisk
read -r -p "Is the disk encryted? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
  sed -i 's/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
  mkinitcpio -P
  grub-install --efi-directory=/boot /dev/${partDisk}
  if [[ $partDisk == *"nvme"* ]]; then
    partDisk="${partDisk}p"
  fi
  blkid -o value -s UUID /dev/${partDisk}2 >> /etc/default/grub
  blkid -o value -s UUID /dev/mapper/cryptroot >> /etc/default/grub
  
  sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet cryptdevice=UUID=${uuidone}:cryptroot root=UUID=${uuidtwo}"/' /etc/default/grub
  nvim /etc/default/grub

  grub-mkconfig -o /boot/grub/grub.cfg
else  
  grub-install --efi-directory=/boot /dev/${partDisk}
  grub-mkconfig -o /boot/grub/grub.cfg
fi
systemctl enable NetworkManager

# Greetd config
pacman -S greetd

sed -i 's/command = "agreety*/command = "agreety --cmd start-hyprland"

systemctl enable greetd.service

# Grub config
sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=0/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Keyboard config
curl --create-dirs -LJO --output-dir /usr/share/X11/xkb/symbols/custom https://raw.githubusercontent.com/SunaaRisu/Arch-Linux-Install/refs/heads/main/Arch-Hyprland-WM/Laptop/kb/custom

# Bash config
curl --create-dirs -LJO --output-dir /home/sunaa/ https://raw.githubusercontent.com/SunaaRisu/Arch-Linux-Install/refs/heads/main/.bashrc

# Neovim config
read -r -p "Config Neovim? [y|N]" response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
  pacman -S npm cargo unzip
  cp -r ./Arch-Linux-Install/nvim/ /home/sunaa/.config/
else
fi

# Install Paru
read -r -p "Install Paru? [y|N]" response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
  mkdir aur
  cd aur
  git clone https://aur.archlinux.org/paru.git
  cd paru
  makepkg -si
  cd ../..
  rm -r aur
fi

# Hyprland config

read -r -p "Install Hyprland? [y|N]" response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
  sudo pacman -S hyprland waybar hyprpaper alacritty wofi dolphin ttf-font-awesome ttf-jetbrains-mono-nerd pulseaudio pavucontrol mako nwg-look git openssh
  git clone https://github.com/SunaaRisu/Arch-Linux-Install.git
  cp ./Arch-Linux-Install/Arch-Hyprland-WM/Laptop/hyprland.conf /home/sunaa/.config/hypr/hyprland.conf
  cp ./Arch-Linux-Install/Arch-Hyprland-WM/Laptop/waybar/config /home/sunaa/.config/waybar/config
  cp ./Arch-Linux-Install/Arch-Hyprland-WM/Laptop/waybar/style.css /home/sunaa/.config/waybar/style.css
  
  git clone https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme.git
  ./Gruvbox-GTK-Theme/themes/install.sh
  sudo rm -r Gruvbox-GTK-Theme
  gsettings set org.gnome.desktop.interface gtk-theme Gruvbox-Dark
  sed -i 's/gtk-icon-theme-name = Adwaita/gtk-icon-theme-name = Gruvbox-Dark' /usr/share/gtk-3.0/settings.ini
  sed -i 's/gtk-theme-name = Adwaita/gtk-theme-name = Gruvbox-Dark' /usr/share/gtk-3.0/settings.ini
  sed -i 's/gtk-icon-theme-name = Adwaita/gtk-icon-theme-name = Gruvbox-Dark' /usr/share/gtk-4.0/settings.ini
  sed -i 's/gtk-theme-name = Adwaita/gtk-theme-name = Gruvbox-Dark' /usr/share/gtk-4.0/settings.ini
  
  cp -r ./Arch-Linux-Install/images/ /home/sunaa/.config/hypr/
  cp Arch-Linux-Install/Arch-Hyprland-WM/Laptop/hyprpaper.conf /home/sunaa/.config/hypr/hyprpaper.conf
fi

exit
umount -a
reboot
END
