#!/usr/bin/env bash

set -e

print () {
    echo -e "\n\033[1m> $1\033[0m\n"
}

# Tests
ls /sys/firmware/efi/efivars
ping archlinux.org -c 1
timedatectl set-ntp true

# Set DISK
select ENTRY in $(ls /dev/disk/by-id/);
do
    DISK="/dev/disk/by-id/$ENTRY"
    echo "Installing on $ENTRY."
    break
done

read -p "> Do you want to wipe all datas on $ENTRY ?" -n 1 -r
echo # move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
    # Clear disk
    wipefs -af $DISK
    sgdisk -Zo $DISK
fi

# EFI part
print "Creating EFI part"
sgdisk -n1:1M:+512M -t1:EF00 $DISK
EFI=$DISK-part1

# SWAP part
print "Creating encrypted SWAP part"
sgdisk -n2:0:+8G -t2:8308 $DISK
SWAP=$DISK-part2

# LUKS part
print "Creating LUKS part"
sgdisk -n3:0:0 -t3:8309 $DISK
LUKS=$DISK-part3

# Inform kernel
partprobe $DISK

# Format boot part
sleep 1
print "Format EFI part"
mkfs.vfat $EFI

# Create plain encrypted SWAP
print "Create encrypted SWAP"
cryptsetup open --type plain $SWAP swap
SWAP=/dev/mapper/swap
mkswap $SWAP
swapon $SWAP

# Create LUKS
print "Create LUKS"
# https://savannah.gnu.org/bugs/?55093
cryptsetup -v --type luks1 --cipher aes-xts-plain64 --key-size 256 --hash sha256 --iter-time 2000 --use-urandom --verify-passphrase luksFormat $LUKS
cryptsetup luksOpen $LUKS universe
BTRFS=/dev/mapper/universe

# Format BTRFS part
print "Format BTRFS"
mkfs.btrfs -L "Universe" $BTRFS

# Create BTRFS subvolumes
print "Create subvolumes"
mount $BTFRS /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/var/cache/pacman/pkg
btrfs subvolume create /mnt/var/tmp
umount /mnt

# Mount filesystems
print "Mount parts"
mount -o subvol=@ $BTRFS /mnt
mkdir /mnt/home
mount -o subvol=@home $BTRFS /mnt/home
mkdir /mnt/.snapshots
mount -o subvol=@snapshots $BTRFS /mnt/.snapshots
mkdir /mnt/boot
mount $EFI /mnt/boot

# Finish
echo -e "\e[32mAll OK"