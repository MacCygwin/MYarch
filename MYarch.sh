#!/usr/bin/bash

set -e  # Exit on errors

# Variables for configuration
EFI_PART=""
ROOT_PART=""
HOSTNAME=""
USERNAME=""
PASSWORD=""
TIMEZONE=""
LOCALE=""

# Functions for each menu option
basic_info() {
    echo "=== Step 1: Basic Info ==="
    read -p "Enter the EFI partition (e.g., /dev/sda1): " EFI_PART
    read -p "Enter the root partition (e.g., /dev/sda2): " ROOT_PART
    read -p "Enter the hostname for your system: " HOSTNAME
    read -p "Enter the username for a regular user: " USERNAME
    read -sp "Enter the password for both root and $USERNAME: " PASSWORD
    echo  # For a clean newline after the password prompt
    read -p "Enter your timezone (e.g., America/New_York): " TIMEZONE
    read -p "Enter your locale (e.g., en_US.UTF-8): " LOCALE

    echo -e "\nBasic Info Collected:"
    echo "EFI Partition: $EFI_PART"
    echo "Root Partition: $ROOT_PART"
    echo "Hostname: $HOSTNAME"
    echo "Username: $USERNAME"
    echo "Password: (hidden)"
    echo "Timezone: $TIMEZONE"
    echo "Locale: $LOCALE"
    read -p "Press Enter to return to the main menu."
}

format_and_mount() {
    echo "=== Step 2: Formatting and Mounting Partitions ==="
    if [[ -z "$EFI_PART" || -z "$ROOT_PART" ]]; then
        echo "Partitions are not set! Please configure Basic Info first."
        read -p "Press Enter to return to the main menu."
        return
    fi

    echo "Formatting partitions..."
    mkfs.fat -F 32 "$EFI_PART"
    mkfs.btrfs "$ROOT_PART"

    echo "Mounting partitions..."
    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/boot
    mount "$EFI_PART" /mnt/boot
    echo "Partitions formatted and mounted successfully."
    read -p "Press Enter to return to the main menu."
}

install_base_system() {
    echo "=== Step 3: Installing Base System ==="
    pacstrap /mnt base linux linux-firmware btrfs-progs base-devel linux-headers
    echo "Base system installation complete."
    read -p "Press Enter to return to the main menu."
}

generate_fstab() {
    echo "=== Step 4: Generating fstab ==="
    genfstab -U /mnt >> /mnt/etc/fstab
    echo "fstab generated successfully."
    read -p "Press Enter to return to the main menu."
}

system_configuration() {
    echo "=== Step 5: System Configuration ==="
    if [[ -z "$TIMEZONE" || -z "$LOCALE" || -z "$HOSTNAME" || -z "$USERNAME" || -z "$PASSWORD" ]]; then
        echo "System configuration details are incomplete! Please complete Basic Info first."
        read -p "Press Enter to return to the main menu."
        return
    fi

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

# Install bootloader and enable services
pacman -S --noconfirm grub efibootmgr networkmanager sudo sof-firmware intel-ucode git wireless-tools nano
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable NetworkManager

# Allow users in the wheel group to execute sudo commands
sed -i 's/^# \(%wheel ALL=(ALL:ALL) ALL\)/\1/' /etc/sudoers
EOF

    echo "System configuration complete."
    read -p "Press Enter to return to the main menu."
}

# Main Menu
while true; do
    clear
    echo "=== Arch Linux Installation Menu ==="
    echo "1) Basic Info"
    echo "2) Formatting and Mounting Partitions"
    echo "3) Install Base System"
    echo "4) Generate fstab"
    echo "5) System Configuration"
    echo "6) Exit"
    echo "====================================="
    read -p "Choose an option: " choice

    case $choice in
        1) basic_info ;;
        2) format_and_mount ;;
        3) install_base_system ;;
        4) generate_fstab ;;
        5) system_configuration ;;
        6) echo "Exiting installation script. Goodbye!"; exit ;;
        *) echo "Invalid option. Please try again."; read -p "Press Enter to continue." ;;
    esac
done
