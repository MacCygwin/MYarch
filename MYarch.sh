#!/usr/bin/env bash

set -e  # Exit on errors

# Check if the system is booted in UEFI mode
if [[ ! -d /sys/firmware/efi/efivars ]]; then
    echo "Error: This system is not booted in UEFI mode. Exiting."
    exit 1
fi

# Step 1: Interactive partitioning
echo "Starting interactive partitioning with cfdisk."
echo "Make sure to create at least an EFI partition (type EFI System) and a root partition."
echo "Press Enter to launch cfdisk on /dev/sda."
read -r

cfdisk /dev/sda

# After partitioning, ask user to enter partition names
read -rp "Enter EFI partition (e.g. /dev/sda1): " EFI_PART
read -rp "Enter root partition (e.g. /dev/sda2): " ROOT_PART

# Validate partitions exist
if [[ ! -b "$EFI_PART" || ! -b "$ROOT_PART" ]]; then
    echo "One or both partitions do not exist. Exiting."
    exit 1
fi

# Predefined system configurations
HOSTNAME="archyo"
USERNAME="mycros"
TIMEZONE="Asia/Singapore"
LOCALE="en_SG.UTF-8"

# Prompt for password
echo "Enter the password to use for both root and the user account:"
read -sp "Password: " PASSWORD
echo
read -sp "Confirm Password: " PASSWORD_CONFIRM
echo

if [[ "$PASSWORD" != "$PASSWORD_CONFIRM" ]]; then
    echo "Passwords do not match. Exiting."
    exit 1
fi

# Step 2: Format and Mount Partitions
echo "=== Step 2: Formatting and Mounting Partitions ==="
echo "Formatting partitions..."
mkfs.fat -F 32 "$EFI_PART"
mkfs.ext4 "$ROOT_PART"

echo "Mounting partitions..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI_PART" /mnt/boot/efi
echo "Partitions formatted and mounted successfully."

# Step 3: Install Base System
echo "=== Step 3: Installing Base System ==="
pacstrap /mnt base linux linux-firmware base-devel linux-headers grub efibootmgr networkmanager sudo sof-firmware intel-ucode amd-ucode git wireless_tools nano zram-generator
echo "Base system installation complete."

# Step 4: Generate fstab
echo "=== Step 4: Generating fstab ==="
genfstab -U /mnt >> /mnt/etc/fstab
echo "fstab generated successfully."

# Step 5: Configure the System
echo "=== Step 5: Configuring the System ==="
arch-chroot /mnt /bin/bash <<EOF
# Set timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Configure locale
echo "$LOCALE UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# Configure hostname
echo "$HOSTNAME" > /etc/hostname

# Configure keyboard layout
echo "KEYMAP=us" > /etc/vconsole.conf

# Set root password
echo "root:$PASSWORD" | chpasswd

# Create user
useradd -m $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
usermod -aG wheel $USERNAME

# Install bootloader
echo "Installing bootloader..."
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

# Enable essential services
echo "Enabling services..."
systemctl enable NetworkManager

# Allow users in the wheel group to execute sudo commands
sed -i 's/^# \(%wheel ALL=(ALL:ALL) ALL\)/\1/' /etc/sudoers
EOF

echo "System configuration complete."

# Step 6: Configure ZRAM
echo "=== Step 6: Configuring ZRAM ==="
arch-chroot /mnt /bin/bash <<EOF
cat <<ZRAM_CONF > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
ZRAM_CONF

systemctl enable systemd-zram-setup@zram0.service
EOF

echo "ZRAM configuration complete."

# Step 7: Final Instructions
echo "=== Installation Complete ==="
echo "Unmounting partitions..."
umount -R /mnt
echo "You can now reboot the system with: reboot"
