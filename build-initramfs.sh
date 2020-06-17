#!/bin/sh

# To create a 32-bit image I used an AWS instance.

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

mkdir --parents ./initramfs/{bin,dev,etc,lib,lib64,mnt/root,proc,root,sbin,sys} 
cp --archive /dev/{null,console,tty,sda1} ./initramfs/dev/

yum install -y busybox
cp --archive $(which busybox) ./initramfs/bin/busybox

cp /lib/ld-linux.so.2 ./initramfs/lib/
ldd $(which sh) $(which busybox) | grep "=> /" | awk '{print $3}' | xargs -I '{}' cp -v '{}' ./initramfs/lib/

cat >./initramfs/init <<'EOF'
#!/bin/busybox sh

# Mount the /proc and /sys filesystems.
mount -t proc none /proc
mount -t sysfs none /sys

# Do your stuff here.
echo "This script just mounts and boots the rootfs, nothing else!"

# Mount the root filesystem.
mount -o ro /dev/sda1 /mnt/root

# Clean up.
umount /proc
umount /sys

exec /bin/sh
EOF

chmod +x ./initramfs/init

find ./initramfs -print0 | cpio --null --create --verbose --format=newc > custom-initramfs

echo "Now just copy it to the bootloader directory, and set size to: $(stat --format "%s" custom-initramfs)"
