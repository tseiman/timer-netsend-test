#!/bin/bash

WORKDIR=$PWD
GRUB_INSTALL=${WORKDIR}/grub/gv2
GRUB_TEMP=${WORKDIR}/grub/gtemp
GRUB_SOURCE=${WORKDIR}/grub/grub-2.00

getLatestFileFromUrl() {
    URL=$1
    SEARCH=$2
    GREPSEARCH=$3
    FILENAME="`wget -qO- "${URL}?C=M;O=A;F=0;P=${SEARCH}" | grep "href"| grep "${GREPSEARCH}" | grep -v "snapshot" | sed 's/.*href=\"\(.*\)\".*/\1/' | sort -t - -V -k 2,2 | awk '/./{line=$0} END{print line}'`"
    echo "$FILENAME"
}

download() {
    NAME=$1
    URL=$2
    FILE=$3
    DESTDIR=$4
    SEARCH=$5
    UNTARCMD=$6
    UNTARFILE=$7
    
    echo "downloading ${NAME} from \"${URL}${FILE}\"... "
    if [ -e "${FILE##*/}" ]; then
	echo "skipping download, file \"${FILE##*/}\" exists already in \"${DESTDIR}\" folder."
    else
	wget -P downloads/ "${URL}${FILE}"
    fi
    if ! ls ${SEARCH} 1> /dev/null 2>&1; then
	echo "${NAME} untar"
	tar ${UNTARCMD} downloads/${UNTARFILE}
    else
	echo "${NAME} has been already untared"
    fi
}


echo "cleaning up old guest-rootfs if exists"

rm -Rf guest-rootfs
echo "setting up new guest-rootfs"
mkdir guest-rootfs
mkdir guest-rootfs/boot

echo "copy data from canned-xen/initrd"
cp -a initrdwork/* guest-rootfs/

echo -n "downloading grub2... "
if [ ! -e "grub-2.00.tar.xz" ]; then
    echo
    wget -P downloads/ -c ftp://ftp.gnu.org/gnu/grub/grub-2.00.tar.xz
    echo "OK."
else
    echo "Skipping cause exists already."
fi



if [ ! -d "${GRUB_SOURCE}" ]; then
    echo "Setup local grub installation directory"
    mkdir grub
    cd grub
    tar xvJf ../downloads/grub-2.00.tar.xz 
    mkdir {gtemp,gbuild,gv2}
    cd -
else
    echo "no need to modify grub sources"
fi



BUSYBOX_URL_INDEX="https://busybox.net/downloads/"
echo "getting busybox download file name from \"${BUSYBOX_URL_INDEX}\"... "
BUSYBOX_URL="`getLatestFileFromUrl "${BUSYBOX_URL_INDEX}" "busybox-*.tar.bz2" "busybox-"`"
echo "got \"${BUSYBOX_URL}\"... OK"
download "Busybox" "${BUSYBOX_URL_INDEX}" "${BUSYBOX_URL}" "downloads/" "busybox-*/*" "xjvf" "busybox-*.tar.bz2"

if  ! ls downloads/busybox-*/busybox 1> /dev/null 2>&1; then
    echo "busybox compile"
    cd busybox-*
    rm -f .config
    make clean
    make defconfig
    make -j4 LDFLAGS=-static
    cd -
else 
    echo "busybox has been already compiled"
fi



DROPBEAR_URL_INDEX="http://matt.ucc.asn.au/dropbear/"
echo "getting ssh dropbear download file name from \"${DROPBEAR_URL_INDEX}\"... "
DROPBEAR_URL="`getLatestFileFromUrl "${DROPBEAR_URL_INDEX}" "dropbear-*.tar.bz2" "tar.bz2"`"
echo "got \"${DROPBEAR_URL}\"... OK"
download "Dropbear" "${DROPBEAR_URL_INDEX}" "${DROPBEAR_URL}" "downloads/" "dropbear-*/*" "xjvf" "dropbear-*.tar.bz2"



if  ! ls downloads/dropbear-*/dropbearmulti 1> /dev/null 2>&1; then
    echo "dropbear compile"
    cd dropbear-*
    ./configure
    make -j4 STATIC=1 MULTI=1
    cd -
else 
    echo "dropbear has been already compiled"
fi





if [ ! -e "${GRUB_INSTALL}/usr/sbin/grub-install" ]; then
    echo "compiling grub"

    cd ${GRUB_SOURCE}
############################################
# BEGIN PATCH ##############################

    echo \
'--- grub-core/gnulib/stdio.in.h	2010-12-01 15:45:43.000000000 +0100
+++ grub-core/gnulib/stdio.in.h~	2017-01-23 02:02:23.312836418 +0100
@@ -140,9 +140,10 @@
 /* It is very rare that the developer ever has full control of stdin,
    so any use of gets warrants an unconditional warning.  Assume it is
    always declared, since it is required by C89.  */
+#if defined gets
 #undef gets
 _GL_WARN_ON_USE (gets, "gets is a security hole - use fgets instead");
-
+#endif
 #if @GNULIB_FOPEN@
 # if @REPLACE_FOPEN@
 #  if !(defined __cplusplus && defined GNULIB_NAMESPACE)
' >gets.patch
# END PATCH ################################
############################################
    pwd
    patch -p1 <gets.patch grub-core/gnulib/stdio.in.h
    cd -


    cd $GRUB_TEMP
    ${GRUB_SOURCE}/configure --prefix=${GRUB_INSTALL}/usr --enable-device-mapper
    make -j4
    make install
    cd -

else
    echo "skip compiling grub - exists already"
fi

echo "creating disk image"
dd if=/dev/zero of=canned-xen-guest1.img bs=1M count=75

echo "partitioning disk image"
# this is cool stuff which was documented under http://superuser.com/questions/332252/ - answer 24 !
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' <<EOF | fdisk canned-xen-guest1.img
o # clear partition table
n # new partition
p # primary
1 # first (boot)
  # default startt at begin of image
+20M # boot partition
n # new 
p # primary
2 # second  (root)
  # default start directly after the first
  # take full space
a # make partition bootable
1 # boot partition = 1
p # print partition table
w # write partition table
q # we're done
EOF

echo "mounting disk images"
LISTED_PARTITIONS=("`sudo kpartx -l canned-xen-guest1.img | sed 's/^\(.*\)$/"\1";/'`")
LISTED_PARTITION_BOOT="`echo ${LISTED_PARTITIONS} | awk -F '"' '{print $2}' | sed 's/\(loop.*\) :.*/\1/'`"
LISTED_PARTITION_ROOT="`echo ${LISTED_PARTITIONS} | awk -F '"' '{print $4}' | sed 's/\(loop.*\) :.*/\1/'`"
LISTED_PARTITION_DEV="` echo ${LISTED_PARTITIONS} | awk -F '"' '{print $6}' | sed 's/.*\(\/dev\/.*\)/\1/'`"
#'

 echo "boot: $LISTED_PARTITION_BOOT"
 echo "root: $LISTED_PARTITION_ROOT"
 echo "dev: $LISTED_PARTITION_DEV"

sudo kpartx -a canned-xen-guest1.img

echo "formatting partions"
sudo mkfs.ext2 /dev/mapper/${LISTED_PARTITION_BOOT}
sudo mkfs.ext4 /dev/mapper/${LISTED_PARTITION_ROOT}
mkdir guest-boot
mkdir guest-root
echo "mounting partions"
sudo mount -text2 /dev/mapper/${LISTED_PARTITION_BOOT} guest-boot
sudo mount /dev/mapper/${LISTED_PARTITION_ROOT} guest-root


echo "creating install script"
echo $"#!/bin/ash
rm -f /sbin/init
/bin/busybox --install -s
echo "executing install.sh in chroot"
" >install.sh
sudo mv install.sh guest-rootfs/
sudo chmod +x guest-rootfs/install.sh
echo "chroot into guest-rootfs"
sudo chroot guest-rootfs/ /install.sh
sudo rm -f guest-rootfs/install.sh


echo "creating fstab"
echo $"
/dev/xvda2     /           ext4    defaults	0 0
proc           /proc        proc     nosuid,noexec,nodev 0     0
sysfs          /sys         sysfs    nosuid,noexec,nodev 0     0
devpts         /dev/pts     devpts   gid=5,mode=620      0     0
tmpfs          /run         tmpfs    defaults            0     0
devtmpfs       /dev         devtmpfs mode=0755,nosuid    0     0
" >fstab
sudo mv fstab guest-rootfs/etc/

echo "creating /etc/shells"
echo $"/bin/sh
/bin/ash
" >shells
mv shells guest-rootfs/etc/




echo "creating rcS"
echo $'#!/bin/sh

. /etc/initrd.defaults
. /etc/initrd.scripts
unset QUIET

# good_msg()
# bad_msg() 
# warn_msg() 


good_msg "mounting all filesystems" 0
/bin/mount -a
mount -o remount,rw /dev/xvda2 /  >/dev/null 2>&1

good_msg "populating mtab" 0
cat /proc/mounts >/etc/mtab

good_msg "Prevent superfluous printks from being printed to the console" 0
echo 1 > /proc/sys/kernel/printk

good_msg "setup network eth0" 0
ifconfig eth0 192.168.2.125 netmask 255.255.255.0 broadcast 192.168.2.255 up
route add default gw 192.168.2.2
echo "nameserver 192.168.2.2" >/etc/resolv.conf

good_msg "setup network lo" 0
ifconfig lo 127.0.0.1 up
# route add 127.0.0.1

if [ ! -f /etc/dropbear/dropbear_rsa_host_key ]; then
    warn_msg "dropbear RSA key needs to be generated"
    cd /etc/dropbear
    dropbearkey -t rsa -f dropbear_rsa_host_key
    cd -
fi
if [ ! -f /etc/dropbear/dropbear_dss_host_key ]; then
    warn_msg "dropbear DSS key needs to be generated"
    cd /etc/dropbear
    dropbearkey -t dss -f dropbear_dss_host_key
    cd -
fi

good_msg "start ssh service" 0
/bin/busybox inetd /etc/inetd.conf

good_msg "setting up keymaps" 0
/bin/busybox loadkmap </lib/keymaps/de.map

' >rcS
mkdir -p guest-rootfs/etc/init.d
chmod +x rcS
sudo mv rcS guest-rootfs/etc/init.d/


echo "creating /etc/profile"
echo $'
echo
echo -n "Processing /etc/profile... "
# no-op
echo "Done"
echo
' >profile
sudo mv profile guest-rootfs/etc/

echo "creating /etc/inetd.conf"
echo $'
ssh     stream  tcp     nowait  root    /sbin/dropbear dropbear -i
' >inetd.conf
sudo mv inetd.conf guest-rootfs/etc/




echo "creating inittab"

#console::askfirst:-/bin/ash
#tty1::askfirst:-/bin/ash
#tty2::askfirst:-/bin/ash
#tty3::askfirst:-/bin/ash
#tty4::askfirst:-/bin/ash
#tty4::respawn:/sbin/getty 38400 tty5
#tty5::respawn:/sbin/getty 38400 tty6
#::restart:/sbin/init
#::ctrlaltdel:/sbin/reboot
#::shutdown:/bin/umount -a -r
#::shutdown:/sbin/swapoff -a
# null::sysinit:/etc/init.d/rcS
#console::respawn:/bin/ash

# ::sysinit:/bin/ash

echo $"
::sysinit:/etc/init.d/rcS
::askfirst:-/bin/ash
::ctrlaltdel:/bin/umount -a -r
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/umount -a -r
::shutdown:/sbin/swapoff -a
" >inittab
mv inittab guest-rootfs/etc/


echo "creating root users"
mkdir guest-rootfs/root
echo "root:WL3YPq72lgy0Q:0:0:Root User,,,:/root:/bin/ash" >guest-rootfs/etc/passwd
echo "root:x:0:" >guest-rootfs/etc/group
cp -a /etc/services guest-rootfs/etc/

echo "copy busybox binaries"
cp -a busybox-*/busybox guest-rootfs/bin/

echo "copy libnss libs"
cp -a squashfswork/lib64/libnss_compat* guest-rootfs/lib/
cp -a squashfswork/lib64/libnss_db* guest-rootfs/lib/
cp -a squashfswork/lib64/libnss_dns* guest-rootfs/lib/
cp -a squashfswork/lib64/libnss_files* guest-rootfs/lib/

echo "adjusting symlinks"
cd guest-rootfs/sbin/
rm -f init
ln -s ../bin/busybox init
# ln -s ../bin/busybox setsid
cd -



echo "copy dropbear ssh binaries"
cp -a dropbear-*/dropbear guest-rootfs/sbin/
cp -a dropbear-*/dropbearmulti guest-rootfs/sbin/
cd guest-rootfs/sbin/
ln -s dropbearmulti dropbearkey
ln -s dropbearmulti dbclient
ln -s dropbearmulti dropbear
ln -s dropbearmulti ../bin/scp
cd -
mkdir guest-rootfs/etc/dropbear

echo "copy guest-rootfs to root"
sudo cp -a guest-rootfs/* guest-root/
sudo mkdir guest-boot/grub

#'set default="0"
#set timeout="0"
#menuentry "Buildroot" {
#    insmod xzio
#    insmod part_msdos
#    insmod ext2
#    linux (hd0,msdos1)/gentoo.igz root=/dev/sda2 rw console=tty0 console=ttyS0
#}
#' >grub.cfg


echo "configuring grub"
echo \
'set default="0"
set timeout="10"
menuentry "Gentoo Guest" {
    insmod xzio
    insmod part_msdos
    insmod ext2
    set root=(hd0,msdos1)
    linux /gentoo root=/dev/xvda2 rw init=/sbin/init
    initrd /gentoo.igz
}
' >grub.cfg
sudo mv grub.cfg guest-boot/grub


echo "installing grub into image, ioctrl errors are ok"
sudo ${GRUB_INSTALL}/usr/sbin/grub-install --no-floppy --modules="biosdisk part_msdos xzio ext2 configfile normal multiboot" --root-directory=${WORKDIR}/ ${LISTED_PARTITION_DEV}
# sudo ${GRUB_INSTALL}/usr/sbin/grub-install --no-floppy  ${LISTED_PARTITION_DEV}

echo "copy kernel and initrd"
sudo rsync --info=progress2 -a vmassemble/isolinux/gentoo* guest-boot/
sudo rsync --info=progress2 -a vmassemble/isolinux/boot* guest-boot/
sudo rsync --info=progress2 -a vmassemble/isolinux/*.map guest-boot/
sudo rm -f guest-rootfs/boot/gentoo*
sudo rm -f guest-rootfs/boot/boot*
sudo rm -f guest-rootfs/boot/*.map

echo "mounted partitions:"
sudo kpartx -l canned-xen-guest1.img
#echo ready
#read
echo "unmounting partitions from image"
sudo umount /dev/mapper/${LISTED_PARTITION_BOOT}
sudo umount /dev/mapper/${LISTED_PARTITION_ROOT}
sudo kpartx -d canned-xen-guest1.img





#sudo rsync --info=progress2 -a ../canned-xen/vmassemble/isolinux/gentoo* guest-rootfs/boot/
#sudo rsync --info=progress2 -a ../canned-xen/vmassemble/isolinux/boot* guest-rootfs/boot/
#sudo rsync --info=progress2 -a ../canned-xen/vmassemble/isolinux/*.map guest-rootfs/boot/


#read
#sudo umount "mntimg1"

