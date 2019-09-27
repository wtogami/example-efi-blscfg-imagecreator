### WARNING: appliance-tools-009.0-6 or later is required for 4MB offset prior to first partition

%include include/aarch64-base.ksi

# Install repos
repo --name="fedora" --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-31&arch=$basearch
repo --name="updates" --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=updates-released-f31&arch=$basearch
%include include/repo-example.ksi

# SELinux configuration
selinux --enforcing
# System bootloader configuration (disabled due to vendor u-boot)
bootloader --location=none --disabled

# Disk partitioning
#   aligns / to 16MB for sdhc preferred_erase_size (also 4MB for eMMC)
#   add previous partitions in increments of 16MB to keep aligned
#   TODO: configure filesystem to group writes in erase blocks
part /boot/efi --fstype="vfat" --size=107
part /boot     --fstype="ext4" --size=303
part /         --fstype="ext4" --size=2000

%include include/debug-ssh-pubkeys.ksi
%include include/debug-and-build-packages.ksi

%packages
solidrun-imx8-uboot
%end

### Symlink /boot/dtb to latest kernel's dtb-*
%include include/kernel-installd-10-devicetree.install.ksi

%post --erroronfail
### Install custom DTB now during kickstart because kernel-install already finished
CHIPSETDIR="freescale"
CUSTOMDTB="imx8mq-hummingboard-pulse.dtb"
for dir in $(find /boot -type d -name 'dtb-*'); do
  install -p -m 0644 /boot/$CUSTOMDTB $dir/$CHIPSETDIR/$CUSTOMDTB
  # Symlink now because kernel-install already finished
  ln -sf ${dir#/boot/} /boot/dtb
done

### Write /lib/kernel/install.d installer for custom DTB
cat << EOF > /lib/kernel/install.d/11-customdtb.install
#!/usr/bin/bash

COMMAND="\$1"
KERNEL_VERSION="\$2"
CHIPSETDIR="$CHIPSETDIR"
CUSTOMDTB="$CUSTOMDTB"

ret=0
case "\$COMMAND" in
  add)
    install -p -m 0644 /boot/\$CUSTOMDTB /lib/modules/\$KERNEL_VERSION/dtb/\$CHIPSETDIR/\$CUSTOMDTB
    ret=\$?
    ;;
  remove)
    rm -f /lib/modules/\$KERNEL_VERSION/dtb/\$CHIPSETDIR/\$CUSTOMDTB
    ret=\$?
    ;;
esac
exit \$ret
EOF
chmod 755 /lib/kernel/install.d/11-customdtb.install

### script - fixup-bls-entry-name
cat << EOF > /usr/bin/fixup-bls-entry-name
#!/bin/bash

# https://bugzilla.redhat.com/show_bug.cgi?id=1753154
# /boot/loader/entries/*.conf can be incorrect because machine-id is
#   set only after first boot when installed from an image.
# This script renames *.conf files to match /etc/machine-id.

MACHINEID=\$(cat /etc/machine-id)
cd /boot/loader/entries
for filename in \$(find -type f -name '*.conf'); do
  FILEID=\$(echo "\$filename" | sed -r 's/^\.\/([0-9a-f]{32})-.+.conf\$/\1/')
  REMAIN=\$(echo "\$filename" | sed -r 's/^\.\/[0-9a-f]{32}-(.+.conf)\$/\1/')
  if [ "\$MACHINEID" != "\$FILEID" ]; then
    echo "Renaming \${FILEID}-\${REMAIN} to \${MACHINEID}-\${REMAIN} to workaround rhbz #1753154"
    mv \${FILEID}-\${REMAIN} \${MACHINEID}-\${REMAIN}
  fi
done
EOF
chmod 755 /usr/bin/fixup-bls-entry-name

### script - growlastpartition
cat << EOF > /usr/bin/growlastpartition
#!/bin/bash
echo
echo "This utility finds the last partition of the system disk, then uses growpart and resize2fs to grow it to use the entire disk."
echo

# Which DISK?
ROOTFSDEV=\$(cat /proc/self/mounts | grep -E '^/dev/[a-z0-9]+ / ' | awk '{print \$1}')
if echo "\$ROOTFSDEV" | grep -qE 'p[0-9]\$'; then
  NUMPREFIX="p"
  DISK=\$(echo "\$ROOTFSDEV" | sed -r 's/^(\/dev\/[a-z0-9]+)p[0-9]\$/\1/')
else
  unset NUMPREFIX
  DISK=\$(echo "\$ROOTFSDEV" | sed -r 's/^(\/dev\/[a-z]+)[0-9]\$/\1/')
fi

# Which partition is last?
for part in \$(sfdisk -d \$DISK | grep -E '^/dev.+type=83\$' | awk '{print \$1}'); do
  LASTPART="\$part"
done
PARTNUMBER=\$(echo "\$LASTPART" | sed -r 's/^\/dev\/[a-z0-9]+([0-9])\$/\1/')

set -x
growpart  \${DISK} \${PARTNUMBER}
resize2fs \${DISK}\${NUMPREFIX}\${PARTNUMBER}
EOF
chmod 755 /usr/bin/growlastpartition

### run-once@.service
cat << EOF > '/etc/systemd/system/run-once@.service'
[Unit]
DefaultDependencies=no
After=local-fs.target systemd-machine-id-commit.service
Before=sysinit.target shutdown.target
Conflicts=shutdown.target

[Service]
Type=oneshot
ExecStart=-/usr/bin/%i
ExecStartPost=-/usr/bin/systemctl disable run-once@%i.service
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=sysinit.target
EOF
chmod 644 '/etc/systemd/system/run-once@.service'

### run-once during boot: fixup BLS entry names to workaround https://bugzilla.redhat.com/show_bug.cgi?id=1753154
systemctl enable run-once@fixup-bls-entry-name.service
### run-once during boot: grow last partition
systemctl enable run-once@growlastpartition.service

### Write /etc/sysconfig/kernel
cat << EOF > /etc/sysconfig/kernel
# Written by image installer
# UPDATEDEFAULT specifies if new-kernel-pkg should make new kernels the default
UPDATEDEFAULT=yes

# DEFAULTKERNEL specifies the default kernel package type
DEFAULTKERNEL=kernel-core
EOF
chmod 644 /etc/sysconfig/kernel

### Write grub defaults for imx8, turn off OS probing as it is always wrong for image creation
cat << EOF > /etc/default/grub
GRUB_TIMEOUT=2
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="console=ttymxc0,115200 earlycon=ec_imx6q,0x30860000,115200"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
GRUB_DISABLE_OS_PROBER=true
EOF
chmod 644 /etc/default/grub
%end

### EVERYTHING BELOW HERE REQUIRES /dev --bind mounted

%post --nochroot --erroronfail
/usr/bin/mount --bind /dev $INSTALL_ROOT/dev
cd $INSTALL_ROOT
# Write generic grub2-efi.cfg using options from /etc/default/grub
#   grub2-probe needs to scan all devices and /dev/disk/by-*/
# Partition uuid's are written to EFI/fedora/grub.cfg
# Menu is populated during boot time via blcfg from /boot/loader/entries/*
/usr/sbin/chroot . /usr/sbin/grub2-mkconfig -o /etc/grub2-efi.cfg
/usr/bin/umount $INSTALL_ROOT/dev

RAWLOOPDEV=$(cat /proc/self/mounts |/usr/bin/grep '^\/dev\/mapper\/loop[0-9]p[0-9] '"$INSTALL_ROOT " | /usr/bin/sed -r 's/^\/dev\/mapper\/(loop[0-9])p.*/\1/')
echo "Set EFI and legacy boot flags on first partition"
/usr/sbin/parted -s /dev/$RAWLOOPDEV set 1 esp
/usr/sbin/parted -s /dev/$RAWLOOPDEV set 1 boot
echo "Installing u-boot in /dev/$RAWLOOPDEV"
UBOOTIMAGE=/usr/share/uboot/solidrun-imx8/flash.bin
dd if=$INSTALL_ROOT/$UBOOTIMAGE of=/dev/$RAWLOOPDEV bs=1024 seek=33 conv=fsync
%end

