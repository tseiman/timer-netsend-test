#!/bin/bash

echo
echo " *********************************************************************"
echo " *                                                                   *"
echo " *  CANNED XEN                                                       *"
echo " *  Hypervisor demonstration live CD creation script                 *"
echo " *  2017 T.Schmidt                                                   *"
echo " *                                                                   *"
echo " *  Please note - this is a script which will create a XEN live CD   *"
echo " *  including 2 demo minimal linux guests. For that it will run      *"
echo " *  various actions like mounting images, formatting those,          *"
echo " *  populating them with files, compiling tools & kernel etc. -      *"
echo " *  partially in chroot environment.                                 *"
echo " *                                                                   *"
echo " *  Following actions might be taken:                                *"
echo " *     - Downloading actual Gentoo minimal live CD                   *"
echo " *     - mounting proc, sys, dev etc. to chroot(s)                   *"
echo " *     - download various tools and compile those                    *"
echo " *     - copy a lot of files arround                                 *"
echo " *     - compile XEN and tools and add it to live cd                 *"
echo " *     - create 2 images for XEN HVA guests with a mini linux        *"
echo " *       and add those as well                                       *"
echo " *     - pack everything back to a bootable ISO image which you'll   *"
echo " *       find finally in this folder                                 *"
echo " *                                                                   *"
echo " *  to do all of that it will download arround 560MB from the        *"
echo " *  internet using various sources and run arround an hour           *"
echo " *  massively depending on which system it runs on.                  *"
echo " *                                                                   *"
echo " *    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!   *"
echo " *    !! Please note - don't interrupt the script while it is   !!   *"
echo " *    !! running - this might cause unforseen incidents e.g.    !!   *"
echo " *    !! commands which are not running in chroot anymore or    !!   *"
echo " *    !! not cleanly unmounted filesystems                      !!   *"
echo " *    !!                                                        !!   *"
echo " *    !! please be prepared to enter your sudo passsword        !!   *"
echo " *    !! several times,  beeing sudoer is basic requirement     !!   *"
echo " *    !!                                                        !!   *"
echo " *    !! THIS IS EXPERIMENTAL, USE ON OWN RISK                  !!   *"
echo " *    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!   *"
echo " *                                                                   *"
echo " *  In case you disagree with those points Hit CTRL-C now !          *"
echo " *  otherwise hit any other key to continue...                       *"
echo " *                                                                   *"
echo " *********************************************************************"
echo
read

LOCALDIR_SOURCE="${BASH_SOURCE[0]}"
while [ -h "${LOCALDIR_SOURCE}" ]; do # resolve $LOCALDIR_SOURCE until the file is no longer a symlink
  LOCALDIR_DIR="$( cd -P "$( dirname "${LOCALDIR_SOURCE}" )" && pwd )"
  LOCALDIR_SOURCE="$(readlink "${LOCALDIR_SOURCE}")"
  [[ ${LOCALDIR_SOURCE} != /* ]] && LOCALDIR_SOURCE="${LOCALDIR_DIR}/${LOCALDIR_SOURCE}" # if $LOCALDIR_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
LOCALDIR_DIR="$( cd -P "$( dirname "${LOCALDIR_SOURCE}" )" && pwd )"

. ${LOCALDIR_DIR}/config.sh
. ${LOCALDIR_DIR}/commons.sh


cd "${LOCALDIR_DIR}"


unmount_all() {
    if [ -d ${SQUASHFSWORK} ]; then
        cd ${SQUASHFSWORK}
        pw_request_hint
        sudo umount -l -n proc 2>&1>/dev/null
        sudo umount -l -n sys 2>&1>/dev/null
        sudo umount -l -n dev/pts 2>&1>/dev/null
        sudo umount -l -n dev 2>&1>/dev/null
#        PWD="`pwd`"
#        grep ${PWD}/sys/kernel/debug /proc/mounts | cut -f2 -d" " | sort -r |  sudo xargs umount -n -l 2>&1>/dev/null
#        grep ${PWD}/sys/kernel/security /proc/mounts | cut -f2 -d" " | sort -r |  sudo xargs umount -n -l 2>&1>/dev/null
#        grep ${PWD}/sys/fs/cgroup/systemd /proc/mounts | cut -f2 -d" " | sort -r |  sudo xargs umount -n -l 2>&1>/dev/null
#        grep ${PWD}/sys/fs/cgroup /proc/mounts | cut -f2 -d" " | sort -r |  sudo xargs umount -n -l 2>&1>/dev/null
#        grep ${PWD}/sys/fs/fuse/connections /proc/mounts | cut -f2 -d" " | sort -r |  sudo xargs umount -n -l 2>&1>/dev/null
#        grep ${PWD}/sys/fs/pstore /proc/mounts | cut -f2 -d" " | sort -r |  sudo xargs umount -n -l 2>&1>/dev/null
#        grep ${PWD}/sys /proc/mounts | cut -f2 -d" " | sort -r |  sudo xargs umount -n -l 2>&1>/dev/null
#        grep ${PWD}/dev/pts /proc/mounts | cut -f2 -d" " | sort -r |  sudo xargs umount -n -l 2>&1>/dev/null
#        grep ${PWD}/dev /proc/mounts | cut -f2 -d" " | sort -r |  sudo xargs umount -n -l 2>&1>/dev/null
#        grep ${PWD}/proc /proc/mounts | cut -f2 -d" " | sort -r |  sudo xargs umount -n -l 2>&1>/dev/null
        cd -
    fi
    return 0
}

if [ $# -ne 0 ]; then


    if [ $1 == "help" ]; then
	echo "createVM.sh [help|umount|clean|guestonly]"
	exit
    fi


    if [ $1 == "umount" ]; then
	unmount_all
	exit
    fi

    if [ $1 == "clean" ]; then
	$SETCOLOR_HEAD
	echo
	echo " !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	echo " !! This will delete all files and folders which have been downloaded,     !!"
	echo " !! compiled and assembled. Are your really sure you hit any key otherwise !!"
	echo " !! to Abort hit CTRL-C                                                    !!"
	echo " !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	$SETCOLOR_NORMAL
	read
	for I in {5..0}; do 
	    $SETCOLOR_STATUS_FAIL
	    echo -n " ${I}"
	    $SETCOLOR_NORMAL
	    sleep 1
	done
	echo
	pw_request_hint
	unmount_all 2>&1>/dev/null
	sudo rm -Rf boot
	sudo rm -Rf busybox-1.26.2
	sudo rm -Rf canned-xen-guest*.img
	sudo rm -Rf downloads
	sudo rm -Rf dropbear-2016.74
	sudo rm -Rf gentoo.i
	sudo rm -Rf gentoo-live-dom0-20170131.iso
	sudo rm -Rf grub
	sudo rm -Rf guest-boot
	sudo rm -Rf guest-root
	sudo rm -Rf guest-rootfs
	sudo rm -Rf initrdwork
	sudo rm -Rf isomnt
	sudo rm -Rf squashfsmnt
	sudo rm -Rf squashfswork
	sudo rm -Rf syslinux-6.03
	sudo rm -Rf vmassemble

	exit
    fi

fi


echo_announce "checking required executables available... "
for PROG in ${REQUIREDPROGRAMS}; do
    echo -n "checking for ${PROG}... "
    command -v $PROG >/dev/null 2>&1 || { echo -n >&2 "ERROR: \"${PROG}\" required but not found - exiting!"; echo_fail; exit; }
    echo_ok
done


echo_announce_n "checking disk space minimum ${MIN_DISK_FREE}kByte... "
DISK_FREE=$(df -Pk "${LOCALDIR_DIR}"  | tail -1 | awk '{print $4}')
my_sudo true
ALLREADY_ALLOCATED=$(sudo du -ks "${LOCALDIR_DIR}" | sed "s/\([0-9]*\).*/\1/")   # "
MIN_DISK_FREE_CALC=$(expr ${MIN_DISK_FREE} - ${ALLREADY_ALLOCATED})
if [ ${DISK_FREE} -lt ${MIN_DISK_FREE_CALC} ]; then
    echo -n "ERROR: the partition the script runs on has not enough diskspace (needs ${MIN_DISK_FREE}kByte but has ${DISK_FREE}kByte, already allocated by previous run, ready to be overwritten: ${ALLREADY_ALLOCATED}kByte ) "
    echo_fail
    exit
else
    echo_ok
fi


echo_announce_n "checking if system is 64bit... "
if [[ ! "`uname -m`" =~ .*x86_64.* ]]; then
    echo -n "ERROR: System is not 64Bit - but the VM will be 64 bit, no crosscompile supported, exiting now!"
    echo_fail
    exit
else
    echo_ok
fi


create_dir "${DOM0_WORKDIR}" "Working"
create_dir "${DOWNLOADDIR}" "Download"
create_dir "${ISOMNT}" "ISO mount"
create_dir "${SQUASHFSWORK}" "SquashFS work"
create_dir "${SQUASHFSMNT}" "SquashFS mount"
create_dir "${INITRDWORK}" "InitRD work"
create_dir "${DISTCACHE}" "Portage Distfile cache"



echo_announce  "getting ISO download file name from \"${GENTOO_LIVE_URL_INDEX}\"... "
if ! wget -o wget.log "${GENTOO_LIVE_URL_INDEX}?C=M;O=A;F=0;P=install-amd64*.iso"; then
    cat wget.log
    rm -f index.html*
    echo_fail
    exit
else
    rm wget.log
fi
GENTOO_MINIMAL_URL="`wget -qO- "${GENTOO_LIVE_URL_INDEX}?C=M;O=A;F=0;P=install-amd64*.iso" | grep 'a href=\"install-amd64-minimal' | sed 's/.*<a href="\(.*install-amd64-minimal.*iso\)".*/\1/gi'`"
if [ -z "${GENTOO_MINIMAL_URL}" ]; then 
    echo -n "ERROR: got empty GENTOO_MINIMAL_URL back, exiting ow, impossible to proceed"
    echo_fail
    exit
fi
echo -n "got \"${GENTOO_MINIMAL_URL}\"... "
echo_ok
rm -f index.html*


echo_announce   "downloading ISO Minimal live CD file from \"${GENTOO_LIVE_URL_INDEX}${GENTOO_MINIMAL_URL}\"... "
if [ -e "${DOWNLOADDIR}/${GENTOO_MINIMAL_URL##*/}" ]; then
    echo -n "skipping download, file \"${GENTOO_MINIMAL_URL##*/}\" exists already in \"${DOWNLOADDIR}\" folder."
else
    wget -P ${DOWNLOADDIR} "${GENTOO_LIVE_URL_INDEX}${GENTOO_MINIMAL_URL}"
fi
echo_ok


echo_announce "getting Stage 4 download file name from \"${GENTOO_LIVE_URL_INDEX}\"... "
if ! wget -o wget.log "${GENTOO_LIVE_URL_INDEX}?C=M;O=A;F=0;P=stage4-amd64-minimal-2*.bz2"; then
    cat wget.log
    rm -f index.html*
    echo_fail
    exit
else
    rm wget.log
fi
GENTOO_MINIMAL_STAGE_URL="`wget -qO- "${GENTOO_LIVE_URL_INDEX}?C=M;O=A;F=0;P=stage4-amd64-minimal-2*.bz2" | grep 'a href=\"stage4-amd64-minimal-2' | sed 's/.*<a href="\(.*stage4-amd64-minimal-[0-9]*.*bz2\)".*/\1/gi'`"
if [ -z "${GENTOO_MINIMAL_STAGE_URL}" ]; then 
    echo -n "ERROR: got empty GENTOO_MINIMAL_STAGE_URL back, exiting ow, impossible to proceed"
    echo_fail
    exit
fi
echo -n "got \"${GENTOO_MINIMAL_STAGE_URL}\"... "
echo_ok
rm -f index.html*


echo_announce  "downloading Stage 4  file from \"${GENTOO_LIVE_URL_INDEX}${GENTOO_MINIMAL_STAGE_URL}\"... "
if [ -e "${DOWNLOADDIR}/${GENTOO_MINIMAL_STAGE_URL##*/}" ]; then
    echo -n "skipping download, file \"${GENTOO_MINIMAL_STAGE_URL##*/}\" exists already in \"${DOWNLOADDIR}\" folder."
else
    wget -P ${DOWNLOADDIR} "${GENTOO_LIVE_URL_INDEX}${GENTOO_MINIMAL_STAGE_URL}"
fi
echo_ok


echo_announce   "getting syslinux download file name from \"${SYSLINUX_URL_INDEX}\"... "
if ! wget -o wget.log "${SYSLINUX_URL_INDEX}/?P=syslinux-*.tar.gz;F=0"; then
    cat wget.log
    rm -f index.html*
    echo_fail
    exit
else
    rm wget.log
fi
SYSLINUX_URL="`wget -qO- "${SYSLINUX_URL_INDEX}/?P=syslinux-*.tar.gz;F=0" | grep "href" |  sed 's/.*href=\"\(.*\)\".*/\1/' | sort  | awk '/./{line=$0} END{print line}'`"
if [ -z "${SYSLINUX_URL}" ]; then 
    echo -n "ERROR: got empty SYSLINUX_URL back, exiting ow, impossible to proceed"
    echo_fail
    exit
fi
echo -n "got \"${SYSLINUX_URL}\"..."
echo_ok
rm -f index.html*

echo_announce "downloading ISO Minimal live CD file from \"${SYSLINUX_URL_INDEX}/${SYSLINUX_URL}\"... "
if [ -e "${DOWNLOADDIR}/${SYSLINUX_URL##*/}" ]; then
    echo -n "skipping download, file \"${SYSLINUX_URL##*/}\" exists already in \"${DOWNLOADDIR}\" folder."
else
    wget -P ${DOWNLOADDIR} "${SYSLINUX_URL_INDEX}/${SYSLINUX_URL}"
fi
echo_ok

echo_announce  "extracting and building syslinux \"${SYSLINUX_URL}\"... "
# rm -fR syslinux-*
if [ ! -d syslinux-* ]; then
    tar xzvf ${DOWNLOADDIR}/${SYSLINUX_URL##*/}
fi
if [ ! -e syslinux-*/bios/core/isolinux.bin ] || \
   [ ! -e syslinux-*/bios/com32/elflink/ldlinux/ldlinux.c32 ] || \
   [ ! -e syslinux-*/bios/com32/lib/libcom32.c32 ] || \
   [ ! -e syslinux-*/bios/com32/libutil/libutil.c32 ] || \
   [ ! -e syslinux-*/bios/com32/mboot/mboot.c32 ] || \
   [ ! -e syslinux-*/bios/com32/menu/menu.c32 ]; then

    cd syslinux-*
    make -j4
    cd -
else
    echo -n "nothing to do for syslinux"
fi

echo_ok

echo_announce "mounting image to \"${DOWNLOADDIR}/${GENTOO_MINIMAL_URL##*/}\"  \"${ISOMNT}\"... "
pw_request_hint
sudo mount -o loop ${DOWNLOADDIR}/${GENTOO_MINIMAL_URL##*/} ${ISOMNT}
echo_ok

echo_announce  "copy files from  \"${ISOMNT}\" to \"${DOM0_WORKDIR}\"... "
pw_request_hint
sudo rsync --info=progress2 -a ${ISOMNT}/* ${DOM0_WORKDIR}
echo_ok


echo_announce_n  "extracting squashfs from \"${SQUASHFILE}\"... "
pw_request_hint
sudo unsquashfs -f -d ${SQUASHFSMNT} ${DOM0_WORKDIR}/${SQUASHFILE}
echo_ok

echo_announce_n  "copy squashfs from \"${SQUASHFSMNT}\" to \"${SQUASHFSWORK}\"... "
pw_request_hint
sudo rsync --info=progress2 -a  ${SQUASHFSMNT}/* ${SQUASHFSWORK}
echo_ok

echo_announce_n  "unmounting \"${ISOMNT}\"... "
pw_request_hint
sudo umount  ${ISOMNT}
echo_ok


echo_announce_n  "extracting \"${INITRDORIGFILE}\" to \"${INITRDWORK}\"... "
xz -d < ${INITRDORIGFILE} >gentoo.i
cd ${INITRDWORK}
cpio -idv <../gentoo.i
cd ..
rm -f gentoo.i
echo_ok



echo_announce_n  "adding stage 4 to workdir \"${SQUASHFSWORK}\"... "
cd ${SQUASHFSWORK}
pw_request_hint
sudo tar xjvf ../${DOWNLOADDIR}/${GENTOO_MINIMAL_STAGE_URL##*/}
cd -
echo_ok


echo_announce "copy portage distfiles if avialable ... "
if [ -d ${DISTCACHE}/ ]; then
    pw_request_hint
    sudo rsync --info=progress2 -a  ${DISTCACHE}/* ${SQUASHFSWORK}/usr/portage/distfiles/
    echo_ok
else
    echo "No distcache \"${DISTCACHE}\" available"
    echo_unknown
fi

echo_announce_n  "mount dev, sys and proc  ... "
cd ${SQUASHFSWORK}
pw_request_hint
sudo mount -t proc none proc
sudo mount --rbind /sys sys
sudo mount --rbind /dev dev
cd -
echo_ok


echo_announce_n  "adding /vms directory and guest images to \" ${SQUASHFSWORK}\"... "
pw_request_hint
sudo mkdir -p  ${SQUASHFSWORK}/var/vms
if [ ! -e "${GUESTDIR}/canned-xen-guest1.img" ] || [ ! -e "${GUESTDIR}/canned-xen-guest2.img" ]; then
    echo_announce "have to generate guest images first as not done yet !"
    cd ./${GUESTDIR}
    ./createGuest.sh
    cd -
fi
if [ ! -e "${GUESTDIR}/canned-xen-guest1.img" ] || [ ! -e "${GUESTDIR}/canned-xen-guest2.img" ]; then
    echo -n "somehow the guest image creation of \"${GUESTDIR}/canned-xen-guest*.img\" wasen't ok - EXITing now !"
    echo_fail
    exit
fi

if [ $# -ne 0 ]; then
    if [ $1 == "guestonly" ]; then
	unmount_all
	exit
    fi
fi

my_sudo rsync --info=progress2 -a  ${GUESTDIR}/canned-xen-guest*.img ${SQUASHFSWORK}/var/vms
echo_ok




echo_announce_n  "adding some configurations to chroot... "


echo $'
name = "guest1"
builder = "hvm"
memory = "256"
disk = [ \'file:/var/vms/canned-xen-guest1.img,hda,w\' ]
vif = [ \'type=ioemu, mac=00:16:3e:09:f0:12, bridge=br0\' ]
vnc=1
vncunused=1
keymap="de"
apic=1
acpi=1
pae=1
vcpus=1
serial = "pty" # enable serial console
on_reboot   = \'restart\'
' >guest1.cfg
#'
pw_request_hint
sudo mv guest1.cfg ${SQUASHFSWORK}/

echo $'
name = "guest2"
builder = "hvm"
memory = "256"
disk = [ \'file:/var/vms/canned-xen-guest2.img,hda,w\' ]
vif = [ \'type=ioemu, mac=00:16:3e:09:f0:14, bridge=br0\' ]
vnc=1
vncunused=2
keymap="de"
apic=1
acpi=1
pae=1
vcpus=1
serial = "pty" # enable serial console
on_reboot   = \'restart\'
' >guest2.cfg
#'
pw_request_hint
sudo mv guest2.cfg ${SQUASHFSWORK}/


echo $'
config_enp13s0="null"

date
bridge_br0="enp13s0"
brctl_setfd_br0=0
brctl_sethello_br0=0
brctl_stp_br0="off"

config_br0="192.168.2.124/24"
routes_br0="default via 192.168.2.2"

bridge_forward_delay_br0=0
bridge_hello_time_br0=1000
' >>net
#'
pw_request_hint
sudo mv net ${SQUASHFSWORK}/etc/conf.d/

echo_ok



echo_announce_n  "adding Kconfiglib script to change kernel config ... "

echo $'
import kconfiglib
import sys

conf = kconfiglib.Config(sys.argv[1])
conf.load_config(".config")
conf["BRIDGE"].set_user_value(\'m\')

conf.write_config(".config")

' >>changeconfig.py
#'
pw_request_hint
sudo mv changeconfig.py ${SQUASHFSWORK}/

echo_ok

echo_announce_n  "Adjusting  network symlinks"
cd ${SQUASHFSWORK}/etc/init.d
my_sudo ln -s net.lo net.br0
cd - >/dev/null
echo_ok


echo_announce_n  "fixing xen logging path"
my_sudo mkdir -p ${SQUASHFSWORK}/var/log/xen
echo_ok




echo_announce_n  "clonig Kconfig Library to \"${SQUASHFSWORK}/usr/src\"... "
cd ${SQUASHFSWORK}/usr/src
pw_request_hint
sudo git clone http://github.com/ulfalizer/Kconfiglib.git
cd -
echo_ok




echo '#!/bin/bash
source /etc/profile
echo "syncing with portage"
emerge-webrsync
emerge sys-kernel/gentoo-sources
cp changeconfig.py /usr/src/linux
mv /usr/src/Kconfiglib /usr/src/linux/
cd /usr/src/linux/Kconfiglib
python setup.py install
' >cfgchroot1.sh

echo '#!/bin/bash
cp /etc/kernels/kernel-config*gentoo /usr/src/linux/.config
cd /usr/src/linux/
make silentoldconfig
make scriptconfig SCRIPT=changeconfig.py
make  -j4
rm -Rf /lib/modules/*
make  modules_install
make  install
echo "emerge xen"
USE="hvm" emerge app-emulation/xen app-emulation/xen-tools net-misc/bridge-utils
echo "adding xen to runtime"
rc-update add xencommons default
rc-update add xenconsoled default
rc-update add xendomains default
rc-update add xenstored default
rc-update add xen-watchdog default
rc-update add sshd default
rc-update add ntp-client default
rc-update add ntpd default
rc-update add net.br0 default
rc-config delete pwgen
echo root:password | chpasswd
mv /guest1.cfg /etc/xen/
useradd -G wheel canned
echo canned:password | chpasswd
' >cfgchroot2.sh
pw_request_hint
sudo mv cfgchroot1.sh ${SQUASHFSWORK}/
sudo mv cfgchroot2.sh ${SQUASHFSWORK}/
sudo chmod +x ${SQUASHFSWORK}/cfgchroot1.sh
sudo chmod +x ${SQUASHFSWORK}/cfgchroot2.sh

echo 'nameserver 8.8.8.8
'>resolv.conf
pw_request_hint
sudo mv resolv.conf ${SQUASHFSWORK}/etc/

echo "hostname=\"canned-xen-dom0\"" >hostname
pw_request_hint
sudo mv hostname ${SQUASHFSWORK}/etc/conf.d


echo_ok






echo_announce_n "syncing portage and emerging kernel sources"
pw_request_hint
sudo chroot ${SQUASHFSWORK} /cfgchroot1.sh
echo_ok


echo_announce "patching kernel for automatic Kconfiglib configuration"
cd ${SQUASHFSWORK}/usr/src/linux
pw_request_hint
sudo git init
sudo git apply Kconfiglib/makefile.patch
##########################

if ! grep scriptconfig scripts/kconfig/Makefile >/dev/null; then
    echo_fail
    echo "git silentconfig patch was not applied - please check manually and hit any key to continue."
    read
else
    echo_ok
fi
cd - >/dev/null





echo_announce_n "running configuration script #2 in chroot"
pw_request_hint
sudo chroot ${SQUASHFSWORK} /cfgchroot2.sh
echo_ok



echo_announce_n "umount dev, sys and proc  ... "
unmount_all
sleep 1
if [ -e ${SQUASHFSWORK}/proc/mounts ]; then 
    echo_fail
    $SETCOLOR_STATUS_FAIL
    echo "Seems so that not all filesystems have been unmounted, please check manually and press enter once things are cleaned up." 
    $SETCOLOR_NORMAL
    read
else
    echo_ok
fi

##############################

echo_announce_n "updating \"${INITRDWORK}\" with new modules ... "
	pw_request_hint
	sudo rm -Rf ${INITRDWORK}/lib/modules/* 
	sudo rsync --info=progress2 -a  ${SQUASHFSWORK}/lib/modules/* ${INITRDWORK}/lib/modules/
echo_ok

echo_announce_n "updating \"${DOM0_WORKDIR}/isolinux\" with new KERNEL ... "
	pw_request_hint
	sudo rm -f ${DOM0_WORKDIR}/isolinux/gentoo
	sudo cp -a ${SQUASHFSWORK}/usr/src/linux/arch/x86/boot/bzImage ${DOM0_WORKDIR}/isolinux/gentoo
echo_ok



echo_announce_n "updating isolinux ... "

for FILE in `ls -1 ${SQUASHFSWORK}/boot/xen*.gz`; do 
    if [ ! -L ${FILE} ]; then 
	sudo rsync --info=progress2 -a  ${FILE} ${DOM0_WORKDIR}/isolinux/xen.gz
    fi
done


echo 'default gentoo-xen
timeout 150
ontimeout localhost
prompt 1
display boot.msg
F1 kernels.msg
F2 F2.msg
F3 F3.msg
F4 F4.msg
F5 F5.msg
F6 F6.msg
F7 F7.msg

label gentoo
  kernel gentoo
  append root=/dev/ram0 init=/linuxrc  dokeymap looptype=squashfs loop=/image.squashfs  cdroot initrd=gentoo.igz vga=791

label gentoo-nofb
  kernel gentoo
  append root=/dev/ram0 init=/linuxrc  dokeymap looptype=squashfs loop=/image.squashfs  cdroot initrd=gentoo.igz

label gentoo-xen
  kernel mboot.c32
  append xen.gz dom0_mem=2048M --- gentoo root=/dev/ram0 init=/linuxrc  dokeymap looptype=squashfs loop=/image.squashfs  cdroot initrd=gentoo.igz --- gentoo.igz


label localhost
  localboot -1
  MENU HIDE
' >isolinux.cfg
pw_request_hint
sudo mv isolinux.cfg ${DOM0_WORKDIR}/isolinux/
sudo rsync --info=progress2 -a  syslinux-*/bios/core/isolinux.bin ${DOM0_WORKDIR}/isolinux/
sudo rsync --info=progress2 -a  syslinux-*/bios/com32/elflink/ldlinux/ldlinux.c32 ${DOM0_WORKDIR}/isolinux/
sudo rsync --info=progress2 -a  syslinux-*/bios/com32/lib/libcom32.c32 ${DOM0_WORKDIR}/isolinux/
sudo rsync --info=progress2 -a  syslinux-*/bios/com32/libutil/libutil.c32 ${DOM0_WORKDIR}/isolinux/
sudo rsync --info=progress2 -a  syslinux-*/bios/com32/mboot/mboot.c32 ${DOM0_WORKDIR}/isolinux/
sudo rsync --info=progress2 -a  syslinux-*/bios/com32/menu/menu.c32 ${DOM0_WORKDIR}/isolinux/
echo_ok

echo_announce "caching distfiles for next run ... "
    rsync --info=progress2 -a  ${SQUASHFSWORK}/usr/portage/distfiles/* ${DISTCACHE}/
echo_ok


echo_announce_n "cleaning unnessesary files... "
pw_request_hint
for FILE in $CLEAN_LIST; do
sudo rm -Rf ${SQUASHFSWORK}/${FILE}
done
echo_ok


echo_announce_n "generating new squashfs... "
pw_request_hint
sudo rm -f ${DOM0_WORKDIR}/${SQUASHFILE}
sudo mksquashfs ${SQUASHFSWORK}/  ${DOM0_WORKDIR}/${SQUASHFILE}
echo_ok

echo_announce_n "generating new initrd... "
cd ${INITRDWORK}
pwd
find . | cpio --quiet --dereference -o -H newc >../gentoo.i
my_sudo xz -C crc32 -z -c ../gentoo.i >../${INITRDORIGFILE}
cd -
echo_ok

echo_announce_n "generating final ISO image \"${ISONEW_DOM0}\" ... "
cd ${DOM0_WORKDIR}
mkisofs -R -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -c isolinux/boot.cat -iso-level 3 -o ../${ISONEW_DOM0} .
cd -
echo_ok



# GENTOO_LIVE_URL_INDEX


