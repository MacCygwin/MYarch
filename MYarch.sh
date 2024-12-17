#!/bin/bash

set -e  # Exit on errors

# Variables for configuration
DISK=""
HOSTNAME=""
USERNAME=""
PASSWORD=""
TIMEZONE=""
LOCALE=""

# Helper Function for Input Prompts
prompt() {
    echo -n "$1: "
    read -r REPLY
    echo "$REPLY"
}

# Functions for each menu option
basic_info() {
    echo "=== Step 1: Basic Info ==="
    DISK=$(prompt "Enter the disk to install Arch Linux (e.g., /dev/sda)")
    HOSTNAME=$(prompt "Enter the hostname for your system")
    USERNAME=$(prompt "Enter the username for a regular user")
    PASSWORD=$(prompt "Enter the password for both root and $USERNAME")
    TIMEZONE=$(prompt "Enter your timezone (e.g., America/New_York)")
    LOCALE=$(prompt "Enter your locale (e.g., en_US.UTF-8)")

    echo -e "\nBasic Info Collected:"
    echo "Disk: $DISK"
    echo "Hostname: $HOSTNAME"
    echo "Username: $USERNAME"
    echo "Password: (hidden)"
    echo "Timezone: $TIMEZONE"
    echo "Locale: $LOCALE"
    read -p "Press Enter to return to the main menu."
}

partition_disk() {
    echo "=== Step 2: Disk Partitioning ==="
    if [[ -z "$DISK" ]]; then
        echo "Disk is not set! Please configure Basic Info first."
        read -p "Press Enter to return to the main menu."
        return
    fi

    echo "The selected disk is: $DISK"
    read -p "This will erase all data on $DISK. Proceed? [y/N]: " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Aborting partitioning. Returning to the main menu."
        return
    fi

    echo "Partitioning the disk using fdisk..."
    # Using fdisk to create partitions
    fdisk "$DISK" <<EOF
g  # Create a new GPT partition table
n  # Create new partition
1  # Partition number 1 (EFI)
   # First sector (default)
+512M  # Size of partition (512MB)
t  # Change partition type
1  # Set partition type to EFI (EFI system partition)
n  # Create new partition
2  # Partition number 2 (root)
   # First sector (default)
   # Last sector (default, takes up remaining space)
w  # Write changes and exit
EOF

    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"

    echo "Disk partitioning complete:"
    echo "EFI Partition: $EFI_PART"
    echo "Root Partition: $ROOT_PART"
    read -p "Press Enter to return to the main menu."
}

format_and_mount() {
    echo "=== Step 3: Formatting and Mounting Partitions ==="
    if [[ -z "$EFI_PART" || -z "$ROOT_PART" ]]; then
        echo "Partitions are not set! Please complete Disk Partitioning first."
        read -p "Press Enter to return to the main menu."
        return
    fi

    echo "Formatting partitions..."
    mkfs.fat -F32 "$EFI_PART"
    mkfs.btrfs "$ROOT_PART"

    echo "Mounting partitions..."
    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/boot
    mount "$EFI_PART" /mnt/boot
    echo "Partitions mounted successfully."
    read -p "Press Enter to return to the main menu."
}

install_base_system() {
    echo "=== Step 4: Installing Base System ==="
    pacstrap /mnt base linux linux-firmware btrfs-progs
    echo "Base system installation complete."
    read -p "Press Enter to return to the main menu."
}

generate_fstab() {
    echo "=== Step 5: Generating fstab ==="
    genfstab -U /mnt >> /mnt/etc/fstab
    echo "fstab generated successfully."
    read -p "Press Enter to return to the main menu."
}

system_configuration() {
    echo "=== Step 6: System Configuration ==="
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
cat <<HOSTS > /etc/hosts
127.0.0.1    localhost
::1          localhost
127.0.1.1    $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Set root password
echo "root:$PASSWORD" | chpasswd

# Create user
useradd -m $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
usermod -aG wheel $USERNAME

# Install bootloader and enable services
pacman -S --noconfirm grub efibootmgr networkmanager sudo
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable NetworkManager
EOF

    echo "System configuration complete."
    read -p "Press Enter to return to the main menu."
}

# Main Menu
while true; do
    clear
    echo "=== Arch Linux Installation Menu ==="
    echo "1) Basic Info"
    echo "2) Disk Partitioning"
    echo "3) Formatting and Mounting Partitions"
    echo "4) Install Base System"
    echo "5) Generate fstab"
    echo "6) System Configuration"
    echo "7) Exit"
    echo "====================================="
    read -p "Choose an option: " choice

    case $choice in
        1) basic_info ;;
        2) partition_disk ;;
        3) format_and_mount ;;
        4) install_base_system ;;
        5) generate_fstab ;;
        6) system_configuration ;;
        7) echo "Exiting installation script. Goodbye!"; exit ;;
        *) echo "Invalid option. Please try again."; read -p "Press Enter to continue." ;;
    esac
done