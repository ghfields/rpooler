#/bin/sh

# ubuntu live environment build script
# + ZFS
#

echo "This script is in development! please read source."
exit

set -e

export _PATH="$(pwd)"
export ARCH=amd64
export RELEASE='bionic'
export RELEASE_VERISON='18.04'
export IMAGE_NAME='x'
export RELEASE_ID='9D1A0061'

_install_depends() {
    sudo apt-get install debootstrap syslinux squashfs-tools genisoimage netpbm
}

_setup_chroot() {
    mkdir -v -p "$_PATH/build/chroot"
    sudo debootstrap --arch=$ARCH $RELEASE "$_PATH/build/chroot"
}

_bind_dev() {
    sudo mount --bind /dev "$_PATH/build/chroot/dev"
}

_unbind_dev() {
    sudo umount "$_PATH/build/chroot/dev"
}

_setup_inet() {
    sudo cp -v /etc/hosts "$_PATH/build/chroot/etc/hosts"
    sudo cp -v /etc/resolv.conf "$_PATH/build/chroot/etc/resolv.conf"
    sudo cp -v /etc/apt/sources.list "$_PATH/build/chroot/etc/apt/sources.list"
}

_bug_430224()
{   # service running in chroot issue-upstart
    ln -v -s /bin/true /sbin/initctl
}

_setup_env() {
    _bind_dev
    # backup initctl
    cp -v "$_PATH/build/chroot/sbin/initctl" "$_PATH/cfg/initctl.backup"
    
    # login to chroot environment
    sudo chroot chroot

    # mount sys paths
    mount none -v -t proc /proc
    mount none -v -t sysfs /sys
    mount none -v -t devpts /dev/pts

    # environment variables
    export HOME=/root
    export LC_ALL=C

    # apt
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys $RELEASE_ID
    apt-get update
    apt-get install --yes dbus
    dbus-uuidgen > /var/lib/dbus/machine-id
    dpkg-divert --local --rename --add /sbin/initctl

    _bug_430224

    apt-get install --yes ubuntu-standard casper lupin-casper
    apt-get install --yes discover laptop-detect os-prober
    apt-get install --yes linux-generic
    apt-get install --yes ubiquity-frontend-gtk
    
    # Cleanup
    rm /var/lib/dbus/machine-id

    # remove initctl diversion
    rm /sbin/initctl
    dpkg-divert --rename --remove /sbin/initctl
    
    if [ -f "/sbin/initctl" ]; then
        read -p "restore initctl."
        exit
    fi

    # remove old kernal
    ls -v /boot/vmlinuz-2.6.**-**-generic > old-kernal
    sum=$(cat old-kernal | grep '[^ ]' | wc -l)

    if [ $sum -gt 1 ]; then
        dpkg -l 'linux-*' | sed '/^ii/!d;/'"$(uname -r | sed "s/\(.*\)-\([^0-9]\+\)/\1/")"'/d;s/^[^ ]* [^ ]* \([^ ]*\).*/\1/;/[0-9]/!d' | xargs sudo apt-get -y purge
    fi

    rm -v old-kernal

    # cleanup and unmounts
    apt-get clean
    rm -rf /tmp/*

    rm /etc/resolv.conf

    umount -lf /proc
    umount -lf /sys
    umount -lf /dev/pts
    read -p "finished."
    exit
    read -p "exited."
}

_build_image() {
    mkdir -v -p "$_PATH/image/"{casper,isolinux,install}

    # kernal/initrd
    cp "$_PATH/build/chroot/boot/vmlinuz-2.6.**-**-generic" "$_PATH/image"/casper/vmlinuz
    cp "$_PATH/build/chroot/boot/initrd.img-2.6.**-**-generic" "$_PATH/image"/casper/initrd.lz

    # isolinux
    cp /usr/lib/ISOLINUX/isolinux.bin "$_PATH/image"/isolinux/
    cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "$_PATH/image"/isolinux/ 

    # memtest
    cp /boot/memtest86+.bin "$_PATH/image"/install/memtest

    # boot-time instructions
    cp -v "$_PATH/cfg/isolinux.txt" "$_PATH/image/isolinux/"

    # boot loader configuration
    cp -v "$_PATH/cfg/isolinux.cfg" "$_PATH/image/isolinux/"

    # compress chroot
    sudo mksquashfs chroot "$_PATH/image/casper/filesystem.squashfs"

    # filesize
    printf $(sudo du -sx --block-size=1 "$_PATH/build/chroot" | cut -f1) > "$_PATH/image/casper/filesystem.size"

    # create disk defines
    cp -v "$_PATH/cfg/README.diskdefines" "$_PATH/image/README.diskdefines"

    # cfg ubuntu remix
    touch "$_PATH/image/ubuntu"

    mkdir -v "$_PATH/image/.disk"
    touch "$_PATH/image/base_installable"
    echo "full_cd/single" > "$_PATH/image/cd_type"
    echo "Ubuntu Remix $RELEASE_VERSION" > "$_PATH/image/info"
    echo "$RELEASE_URL" > "$_PATH/image/release_notes_url"

    # calc md5
    sudo -s
    (find "$_PATH/image/" -type f -print0 | xargs -0 md5sum | grep -v "\./md5sum.txt" > "$_PATH/image/md5sum.txt")
    exit

    # create iso
    sudo mkisofs -r -V "$IMAGE_NAME" \
        -cache-inodes -J -l \
        -b "$_PATH/image/isolinux/isolinux.bin" \
        -c "$_PATH/image/isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -o "$_PATH/image/ubuntu-remix.iso "$_PATH/image"
}

if [ -d "$_PATH/build"]; then
    echo 'build exists.'
    exit
else
    _setup_chroot
    _bind_dev
    _setup_inet
    _setup_env
    _unbind_dev
fi

read -p "Build image"

if [ "$REPLY" == 'yes']; then
    _build_image
fi

