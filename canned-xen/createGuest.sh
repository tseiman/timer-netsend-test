#!/bin/bash

LOCALDIR_SOURCE="${BASH_SOURCE[0]}"
while [ -h "${LOCALDIR_SOURCE}" ]; do # resolve $LOCALDIR_SOURCE until the file is no longer a symlink
  LOCALDIR_DIR="$( cd -P "$( dirname "${LOCALDIR_SOURCE}" )" && pwd )"
  LOCALDIR_SOURCE="$(readlink "${LOCALDIR_SOURCE}")"
  [[ ${LOCALDIR_SOURCE} != /* ]] && LOCALDIR_SOURCE="${LOCALDIR_DIR}/${LOCALDIR_SOURCE}" # if $LOCALDIR_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
LOCALDIR_DIR="$( cd -P "$( dirname "${LOCALDIR_SOURCE}" )" && pwd )"

. ${LOCALDIR_DIR}/config.sh
. ${LOCALDIR_DIR}/commons.sh

# echo_announce
# echo_announce_n
# echo_ok
# echo_fail
# echo_unknown

echo_announce_n "cleaning up old guest-rootfs if exists"
rm -Rf guest-rootfs
echo_ok

echo_announce_n "setting up new guest-rootfs"
mkdir guest-rootfs
mkdir guest-rootfs/boot
echo_ok

echo_announce "copy data from canned-xen/initrd"
rsync --info=progress2 -a initrdwork/* guest-rootfs/
echo_ok

echo_announce "downloading grub2... "
if [ ! -e "downloads/grub-2.00.tar.xz" ]; then
    echo
    wget -P downloads/ -c ftp://ftp.gnu.org/gnu/grub/grub-2.00.tar.xz
    echo_ok

else
    echo "Skipping cause exists already."
    echo_unknown
fi


echo_announce "Setup local grub installation directory"
if [ ! -d "${GRUB_SOURCE}" ]; then
    mkdir grub
    cd grub
    tar xvJf ../downloads/grub-2.00.tar.xz 
    mkdir {gtemp,gbuild,gv2}
    cd -
    echo_ok
else
    echo "no need to modify grub sources"
    echo_unknown
fi



echo_announce  "getting busybox download file name from \"${BUSYBOX_URL_INDEX}\"... "
BUSYBOX_URL="`getLatestFileFromUrl "${BUSYBOX_URL_INDEX}" "busybox-*.tar.bz2" "busybox-"`"
echo -n "got \"${BUSYBOX_URL}\"... "
echo_ok

download "Busybox" "${BUSYBOX_URL_INDEX}" "${BUSYBOX_URL}" "downloads/" "busybox-*/*" "xjvf" "busybox-*.tar.bz2"

if  ! ls busybox-*/busybox 1> /dev/null 2>&1; then
    echo_announce "busybox compile"
    cd busybox-*
    rm -f .config
    make clean
    make defconfig
    sed -e 's/.*CONFIG_STATIC.*/CONFIG_STATIC=y/' -i .config

    LDFLAGS="--static" make -j4 
    cd -
    echo_ok
else 
    echo "busybox has been already compiled"
    echo_unknown
fi



echo_announce  "getting ssh dropbear download file name from \"${DROPBEAR_URL_INDEX}\"... "
DROPBEAR_URL="`getLatestFileFromUrl "${DROPBEAR_URL_INDEX}" "dropbear-*.tar.bz2" "tar.bz2"`"
echo -n "got \"${DROPBEAR_URL}\"..."
echo_ok
download "Dropbear" "${DROPBEAR_URL_INDEX}" "${DROPBEAR_URL}" "downloads/" "dropbear-*/*" "xjvf" "dropbear-*.tar.bz2"

echo_announce "dropbear compile"
if  ! ls dropbear-*/dropbearmulti 1> /dev/null 2>&1; then
    cd dropbear-*
    ./configure
    make -j4 PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" STATIC=1 MULTI=1
    cd -
    echo_ok
else 
    echo "dropbear has been already compiled"
    echo_unknown
fi


echo_announce  "build stress ng"
if [ -d "../tools/stress-ng" ]; then
    if [ ! -e "../tools/stress-ng/stress-ng" ]; then
	cd ../tools/stress-ng/
	make -j4
	cd -
	echo_ok
    fi
else
    echo "Stress NG not available - will skip that, tool will not be part of guest images"
    echo_fail
fi

echo_announce  "build UDP load test"
if [ -d "../userspace" ]; then
    if [ ! -e "../userspace/timer-netsend-userspace-only" ]; then
	cd ../userspace
	LDFLAGS="-lpthread --static" make -j4
	cd -
	echo_ok
    else
	echo "timer-netsend-userspace-only exists already"
	echo_unknown
    fi
else
    echo "userspace test not available - will skip that, tool will not be part of guest images"
    echo_fail
fi


echo_announce "compiling grub"
if [ ! -e "${GRUB_INSTALL}/usr/sbin/grub-install" ]; then

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

    echo_ok

else
    echo "skip compiling grub - exists already"
    echo_unknown
fi

echo_announce "creating disk image"
dd if=/dev/zero of=canned-xen-guest1.img bs=1M count=75
echo_ok

echo_announce "partitioning disk image"
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
echo_ok

echo_announce "mounting disk images"
my_sudo true
LISTED_PARTITIONS=("`my_sudo kpartx -l canned-xen-guest1.img | sed 's/^\(.*\)$/"\1";/'`")
LISTED_PARTITION_BOOT="`echo ${LISTED_PARTITIONS} | awk -F '"' '{print $2}' | sed 's/\(loop.*\) :.*/\1/'`"
LISTED_PARTITION_ROOT="`echo ${LISTED_PARTITIONS} | awk -F '"' '{print $4}' | sed 's/\(loop.*\) :.*/\1/'`"
LISTED_PARTITION_DEV="` echo ${LISTED_PARTITIONS} | awk -F '"' '{print $6}' | sed 's/.*\(\/dev\/.*\)/\1/'`"
#'

echo "boot: $LISTED_PARTITION_BOOT"
echo "root: $LISTED_PARTITION_ROOT"
echo "dev: $LISTED_PARTITION_DEV"
my_sudo kpartx -a canned-xen-guest1.img
echo_ok

echo_announce "formatting partions"

my_sudo mkfs.ext2 /dev/mapper/${LISTED_PARTITION_BOOT}
my_sudo mkfs.ext4 /dev/mapper/${LISTED_PARTITION_ROOT}
mkdir boot
mkdir guest-root
echo_ok

echo_announce_n "mounting partions"

my_sudo mount -text2 /dev/mapper/${LISTED_PARTITION_BOOT} boot
my_sudo mount /dev/mapper/${LISTED_PARTITION_ROOT} guest-root
echo_ok


echo_announce_n "creating install script"
echo $"#!/bin/ash
# rm -f /sbin/init
/bin/busybox --install -s
echo "executing install.sh in chroot"
" >install.sh
mv install.sh guest-rootfs/
chmod +x guest-rootfs/install.sh
echo_ok

echo_announce "chroot into guest-rootfs"

my_sudo chroot guest-rootfs/ /install.sh
rm -f guest-rootfs/install.sh
echo_ok


echo_announce_n "creating fstab"
echo $"
'${GUEST_ROOT_PARTITION}'     /           ext4    defaults	0 0
proc           /proc        proc     nosuid,noexec,nodev 0     0
sysfs          /sys         sysfs    nosuid,noexec,nodev 0     0
devpts         /dev/pts     devpts   gid=5,mode=620      0     0
tmpfs          /run         tmpfs    defaults            0     0
devtmpfs       /dev         devtmpfs mode=0755,nosuid    0     0
" >fstab
mv fstab guest-rootfs/etc/
echo_ok

echo_announce_n "creating /etc/shells"
echo $"/bin/sh
/bin/ash
" >shells
mv shells guest-rootfs/etc/
echo_ok




echo_announce_n "creating guest1 rcS"
echo $'#!/bin/sh

. /etc/initrd.defaults
. /etc/initrd.scripts
unset QUIET

# good_msg()
# bad_msg() 
# warn_msg() 


good_msg "mounting all filesystems" 0
/bin/mount -a
mount -o remount,rw '${GUEST_ROOT_PARTITION}' /  >/dev/null 2>&1

good_msg "setting hostname to '${GUEST1_NAME}'"
/bin/hostname '${GUEST1_NAME}'

good_msg "populating mtab" 0
cat /proc/mounts >/etc/mtab

good_msg "Prevent superfluous printks from being printed to the console" 0
echo 1 > /proc/sys/kernel/printk

good_msg "setup network eth0" 0

'${GUEST1_ETH_CONFIG}'
'${GUEST1_DEFAULT_GW}'
'${GUEST_DEFAULT_DNS}'

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


good_msg "seting clock via rdate" 0
/usr/sbin/rdate -s '${GUEST_NTP_SERVER}'

good_msg "starting ntpd" 0
/usr/sbin/ntpd -p '${GUEST_NTP_SERVER}'

good_msg "setting up keymaps" 0
/bin/busybox loadkmap </lib/keymaps/'${GUEST_KEYMAP}'.map

' >rcS
mkdir -p guest-rootfs/etc/init.d
chmod +x rcS
mv rcS guest-rootfs/etc/init.d/
echo_ok


echo_announce_n "creating /etc/profile"
echo $'
echo
echo -n "Processing /etc/profile... "
export PS1="\\[\\033]0;\\u@\\h:\\w\\007\\]\\[\\033[01;33m\\]\\h\\[\\033[01;34m\\] \\W \\$ \\[\\033[00m\\]"
echo "Done"
echo
' >profile
mv profile guest-rootfs/etc/
echo_ok

echo_announce_n "creating /etc/inetd.conf"
echo $'
ssh     stream  tcp     nowait  root    /sbin/dropbear dropbear -i
' >inetd.conf
mv inetd.conf guest-rootfs/etc/
echo_ok


echo_announce_n "creating inittab"
echo $"
::sysinit:/etc/init.d/rcS
::askfirst:-/bin/ash
::ctrlaltdel:/bin/umount -a -r
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/umount -a -r
::shutdown:/sbin/swapoff -a
" >inittab
mv inittab guest-rootfs/etc/
echo_ok



echo_announce_n "creating root users"
mkdir guest-rootfs/root
echo "root:BE3og7CN4W/wI:0:0:Root User,,,:/root:/bin/ash" >guest-rootfs/etc/passwd
echo "root:x:0:" >guest-rootfs/etc/group
cp -a /etc/services guest-rootfs/etc/
echo_ok


echo_announce_n "copy busybox binaries"
if [ -e busybox-*/busybox ]; then
    cp -a busybox-*/busybox guest-rootfs/bin/
    echo_ok
else
    echo -n "   !!! NO BUSYBOX AVAILABLE !!! "
    echo_fail
fi



echo_announce_n "copy stress-ng binaries"
if [ -e ../tools/stress-ng/stress-ng ]; then
    cp -a ../tools/stress-ng/stress-ng guest-rootfs/bin/
    echo_ok
else
    echo -n "   !!! NO STRESS_NG AVAILABLE !!! "
    echo_fail
fi


echo_announce_n "create stress-ng control script"
echo $"#!/bin/ash

RUNTIME=20

NUM_CPUS=\`cat /proc/cpuinfo | grep  '^processor[[:space:]]*:[[:space:]]*[0-9]\+$' | wc -l\`
echo \"number of CPUs detected: \${NUM_CPUS}\"
trap \"killall stress-ng &>/dev/null; rm -f /tmp/cpu_stress_control; exit\" SIGHUP SIGINT SIGTERM


for I in \$(seq 0 10 100); do
    echo \"limiting to \$I% CPU \"
    echo \$I >/tmp/cpu_stress_control
    /bin/stress-ng --cpu \$NUM_CPUS   -l \$I -t \$RUNTIME
done

rm -f /tmp/cpu_stress_control
killall stress-ng &>/dev/null

" >cpu_stress_control.sh
chmod +x cpu_stress_control.sh
mv cpu_stress_control.sh guest-rootfs/bin/
echo_ok



echo_announce_n "copy load test binaries"
if [ -e ../userspace/timer-netsend-userspace-only ]; then
    cp -a ../userspace/timer-netsend-userspace-only guest-rootfs/bin/
    echo_ok

else
    echo -n "   !!! NO LOAD TEST AVAILABLE !!! "
    echo_fail

fi



echo_announce_n "copy libnss libs"
cp -a squashfswork/lib64/libnss_compat* guest-rootfs/lib/
cp -a squashfswork/lib64/libnss_db* guest-rootfs/lib/
cp -a squashfswork/lib64/libnss_dns* guest-rootfs/lib/
cp -a squashfswork/lib64/libnss_files* guest-rootfs/lib/
echo_ok


echo_announce_n "adjusting symlinks"
cd guest-rootfs/sbin/
rm -f init
ln -s ../bin/busybox init
cd - >/dev/null
cd guest-rootfs/bin/
rm -f scp
ln -s ../sbin/dropbearmulti scp
ln -s busybox seq
ln -s busybox wc
ln -s busybox top
cd - >/dev/null
echo_ok

echo_announce_n "copy dropbear ssh binaries"
if [ -e dropbear-*/dropbear ]; then
    cp -a dropbear-*/dropbear guest-rootfs/sbin/
    echo_ok
elif [ -e dropbear-*/dropbearmulti ]; then
    cp -a dropbear-*/dropbearmulti guest-rootfs/sbin/
    echo_ok
else
    echo -n "   !!! NO DROPBEAR AVAILABLE !!! "
    echo_fail
fi

echo_announce_n "adjust dropbear symlinks"
cd guest-rootfs/sbin/
ln -s dropbearmulti dropbearkey
ln -s dropbearmulti dbclient
ln -s dropbearmulti dropbear
rm -f ../bin/scp
ln -s dropbearmulti ../bin/scp
cd -  >/dev/null
mkdir guest-rootfs/etc/dropbear
echo_ok


echo_announce_n "copy guest-rootfs to root"
my_sudo rsync --info=progress2 -a guest-rootfs/* guest-root/
my_sudo mkdir -p boot/grub
echo_ok


#'set default="0"
#set timeout="0"
#menuentry "Buildroot" {
#    insmod xzio
#    insmod part_msdos
#    insmod ext2
#    linux (hd0,msdos1)/gentoo.igz root=/dev/sda2 rw console=tty0 console=ttyS0
#}
#' >grub.cfg


echo_announce_n "configuring grub"
echo \
'set default="0"
set timeout="10"
menuentry "Gentoo Guest" {
    insmod xzio
    insmod part_msdos
    insmod ext2
    set root=(hd0,msdos1)
    linux /gentoo root='${GUEST_ROOT_PARTITION}' rw init=/sbin/init
    initrd /gentoo.igz
}
' >grub.cfg
my_sudo mv grub.cfg boot/grub
echo_ok

echo_announce "installing grub into image"

my_sudo true
sudo ${GRUB_INSTALL}/usr/sbin/grub-install --no-floppy --modules="biosdisk part_msdos xzio ext2 configfile normal multiboot" --root-directory=${GUEST_WORKDIR}/ ${LISTED_PARTITION_DEV}  2>/dev/null
# my_sudo ${GRUB_INSTALL}/usr/sbin/grub-install --no-floppy  ${LISTED_PARTITION_DEV}
echo_ok

echo_announce_n "copy kernel and initrd"

my_sudo rsync --info=progress2 -a vmassemble/isolinux/gentoo* boot/
my_sudo rsync --info=progress2 -a vmassemble/isolinux/boot* boot/
my_sudo rsync --info=progress2 -a vmassemble/isolinux/*.map boot/
my_sudo rm -f guest-rootfs/boot/gentoo*
my_sudo rm -f guest-rootfs/boot/boot*
my_sudo rm -f guest-rootfs/boot/*.map
echo_ok

echo_announce "mounted partitions:"

my_sudo kpartx -l canned-xen-guest1.img
echo_ok

echo_announce "unmounting partitions from guest1 image"

my_sudo umount /dev/mapper/${LISTED_PARTITION_BOOT}
my_sudo umount /dev/mapper/${LISTED_PARTITION_ROOT}
my_sudo kpartx -d canned-xen-guest1.img
echo_ok


if [ $# -ne 0 ]; then
    if [ $1 == "g2disable" ]; then
	echo_announce_n "guest 2 disabled, not updating/creating image for guest 2"
	echo_unknown
	exit
    fi
fi



echo_announce "cloning guest1 to guest2"
rsync --info=progress2 -a canned-xen-guest1.img canned-xen-guest2.img
echo_ok

echo_announce "retreiving partition information for guest2"

LISTED_PARTITIONS=("`my_sudo kpartx -l canned-xen-guest2.img | sed 's/^\(.*\)$/"\1";/'`")
LISTED_PARTITION_BOOT="`echo ${LISTED_PARTITIONS} | awk -F '"' '{print $2}' | sed 's/\(loop.*\) :.*/\1/'`"
LISTED_PARTITION_ROOT="`echo ${LISTED_PARTITIONS} | awk -F '"' '{print $4}' | sed 's/\(loop.*\) :.*/\1/'`"
LISTED_PARTITION_DEV="` echo ${LISTED_PARTITIONS} | awk -F '"' '{print $6}' | sed 's/.*\(\/dev\/.*\)/\1/'`"
#'

echo "boot: $LISTED_PARTITION_BOOT"
echo "root: $LISTED_PARTITION_ROOT"
echo "dev: $LISTED_PARTITION_DEV"
my_sudo kpartx -a canned-xen-guest2.img
echo_ok

echo_announce_n "mounting root partion for modification"
my_sudo mount /dev/mapper/${LISTED_PARTITION_ROOT} guest-root
echo_ok


echo_announce_n "creating guest2 rcS"
echo $'#!/bin/sh

. /etc/initrd.defaults
. /etc/initrd.scripts
unset QUIET

# good_msg()
# bad_msg() 
# warn_msg() 


good_msg "mounting all filesystems" 0
/bin/mount -a
mount -o remount,rw '${GUEST_ROOT_PARTITION}' /  >/dev/null 2>&1

good_msg "setting hostname to '${GUEST2_NAME}'"
/bin/hostname '${GUEST2_NAME}'

good_msg "populating mtab" 0
cat /proc/mounts >/etc/mtab

good_msg "Prevent superfluous printks from being printed to the console" 0
echo 1 > /proc/sys/kernel/printk

good_msg "setup network eth0" 0

'${GUEST2_ETH_CONFIG}'
'${GUEST2_DEFAULT_GW}'
'${GUEST_DEFAULT_DNS}'

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


good_msg "seting clock via rdate" 0
/usr/sbin/rdate -s '${GUEST_NTP_SERVER}'

good_msg "starting ntpd" 0
/usr/sbin/ntpd -p '${GUEST_NTP_SERVER}'

good_msg "setting up keymaps" 0
/bin/busybox loadkmap </lib/keymaps/'${GUEST_KEYMAP}'.map

' >rcS
chmod +x rcS
my_sudo mv rcS guest-root/etc/init.d/
echo_ok

echo_announce "unmounting partitions from guest2 image"
my_sudo umount /dev/mapper/${LISTED_PARTITION_ROOT}
my_sudo kpartx -d canned-xen-guest2.img
echo_ok


# my_sudo rsync --info=progress2 -a ../canned-xen/vmassemble/isolinux/gentoo* guest-rootfs/boot/
# my_sudo rsync --info=progress2 -a ../canned-xen/vmassemble/isolinux/boot* guest-rootfs/boot/
#my_sudo rsync --info=progress2 -a ../canned-xen/vmassemble/isolinux/*.map guest-rootfs/boot/

