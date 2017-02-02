#!/bin/bash


GUEST_ROOT_PARTITION="/dev/xvda2"
GUEST_KEYMAP="de"
GUEST_NTP_SERVER="192.53.103.108"
GUEST_DEFAULT_DNS="echo \"nameserver 192.168.2.2\" >/etc/resolv.conf"

GUEST1_NAME="guest1"
GUEST1_ETH_CONFIG="ifconfig eth0 192.168.2.125 netmask 255.255.255.0 broadcast 192.168.2.255 up"
GUEST1_DEFAULT_GW="route add default gw 192.168.2.2"

GUEST2_NAME="guest2"
GUEST2_ETH_CONFIG="ifconfig eth0 192.168.2.126 netmask 255.255.255.0 broadcast 192.168.2.255 up"
GUEST2_DEFAULT_GW="route add default gw 192.168.2.2"


GENTOO_LIVE_URL_INDEX="http://distfiles.gentoo.org/releases/amd64/autobuilds/current-install-amd64-minimal/"
SYSLINUX_URL_INDEX="https://www.kernel.org/pub/linux/utils/boot/syslinux"
BUSYBOX_URL_INDEX="https://busybox.net/downloads/"
DROPBEAR_URL_INDEX="http://matt.ucc.asn.au/dropbear/"


DOM0_WORKDIR="vmassemble"
DOWNLOADDIR="downloads"
REQUIREDPROGRAMS="wget rsync uname sed grep mount sudo unsquashfs rm gunzip cpio xz chmod chroot mksquashfs find mkisofs awk nasm kpartx git"
ISOMNT="isomnt"
ISONEW_DOM0="gentoo-live-dom0-`date +%Y%m%d`.iso"
SQUASHFSWORK="squashfswork"
SQUASHFSMNT="squashfsmnt"
SQUASHFILE="image.squashfs"
INITRDWORK="initrdwork"
INITRDORIGFILE="${DOM0_WORKDIR}/isolinux/gentoo.igz"
CLEAN_LIST="var/tmp/* 
var/run/*
var/lock/*
var/cache/*
var/db/*
tmp/*
var/log/*
root/.bash_history
usr/portage/*
etc/portage/*
usr/share/doc/*
usr/src/*"

DISTCACHE="portage-distcache"

GUESTDIR="./"
GUEST_WORKDIR=$PWD
GRUB_INSTALL=${GUEST_WORKDIR}/grub/gv2
GRUB_TEMP=${GUEST_WORKDIR}/grub/gtemp
GRUB_SOURCE=${GUEST_WORKDIR}/grub/grub-2.00

MIN_DISK_FREE=5800000
