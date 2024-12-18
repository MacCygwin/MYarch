#!/usr/bin/bash

set -e  # Exit on errors

# Check if the system is booted in UEFI mode
if [[ ! -d /sys/firmware/efi/efivars ]]; then
    echo "Error: This system is not booted in UEFI mode. Exiting."
    exit 1
fi

# Predefined partitions
EFI_PART="/dev/sda1"
ROOT_PART="/dev/sda2"

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

# Ensure partitions are set correctly
if [[ -z "$EFI_PART" || -z "$ROOT_PART" ]]; then
    echo "Error: Partitions are not configured correctly. Exiting."
    exit 1
fi

# Step 1: Format and Mount Partitions
echo "=== Step 1: Formatting and Mounting Partitions ==="
echo "Formatting partitions..."
mkfs.fat -F 32 "$EFI_PART"
mkfs.ext4 "$ROOT_PART"

echo "Mounting partitions..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI_PART" /mnt/boot/efi
echo "Partitions formatted and mounted successfully."

# Step 2: Install Base System
echo "=== Step 2: Installing Base System ==="
pacstrap /mnt base linux linux-firmware base-devel linux-headers grub efibootmgr networkmanager sudo sof-firmware intel-ucode git wireless_tools nano
echo "Base system installation complete."

# Step 3: Generate fstab
echo "=== Step 3: Generating fstab ==="
genfstab -U /mnt >> /mnt/etc/fstab
echo "fstab generated successfully."

# Step 4: Configure the System
echo "=== Step 4: Configuring the System ==="
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

# Step 5: Configure ZRAM
echo "=== Step 5: Configuring ZRAM ==="
arch-chroot /mnt /bin/bash <<EOF
# Install zram-generator
pacman -S --noconfirm zram-generator

# Configure zram
cat <<ZRAM_CONF > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
ZRAM_CONF

# Enable zram service
echo "Enabling ZRAM..."
systemctl enable systemd-zram-setup@zram0.service
EOF

echo "ZRAM configuration complete."

# Step 6: Final Instructions
echo "=== Installation Complete ==="
echo "Unmounting partitions..."
umount -R /mnt
echo "Reboot the system with: reboot"
