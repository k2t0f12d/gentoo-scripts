#!/usr/bin/env bash

#
# -- In chroot
#

# Update environment
env-update && . /etc/profile && export PS1="(chroot)$PS1"

# Set keymap
sed -i -e 's/keymap=.*/keymap="dvorak"/' /etc/conf.d/keymaps

# Set Mirrors for Portage sync
sed -i -e "/^LC_MESSAGE/a\\
GENTOO_MIRRORS=\"http://192.168.20.3/gentoo\"" /etc/portage/make.conf

# Set Portage License configuration
sed -i -e "\$aACCEPT_LICENSE=\"* -@EULA\"" /etc/portage/make.conf

# NOTE: Accept unstable Gentoo packages
sed -i -e "/^COMMON_FLAGS/i\\
ACCEPT_KEYWORDS=\"~amd64\"" /etc/portage/make.conf
sed -i -e "/^COMMON_FLAGS/i\\
ABI_X86=\"64 32\"" /etc/portage/make.conf

# Prepare portage configuration for automask additions
for i in use accept_keywords mask unmask license use; do mkdir -pv /etc/portage/package.${i}; touch /etc/portage/package.${i}/zzz_via_automask; done

# Setup gentoo repos configuration
mkdir /etc/portage/repos.conf
cat > /etc/portage/repos.conf/gentoo.conf <<EOF
[DEFAULT]
main-repo = gentoo

[gentoo]
location = /usr/portage
sync-type = rsync
auto-sync = yes

sync-uri = rsync://192.168.20.3/gentoo-portage

sync-rsync-vcs-ignore = true
EOF

# Setup Portage compile time configuration
echo 'export NUMCPUS=$(nproc)
export NUMCPUSPLUSONE=$(( NUMCPUS + 1 ))
export MAKEOPTS="-j${NUMCPUSPLUSONE} -l${NUMCPUS}"
export EMERGE_DEFAULT_OPTS="--jobs=${NUMCPUSPLUSONE} --load-average=${NUMCPUS}"' > ~/.bashrc
source ~/.bashrc
echo 'if [[ -f $HOME/.bashrc ]]; then source $HOME/.bashrc; fi' > ~/.bash_profile

# Update environment
env-update && . /etc/profile && export PS1="(chroot)$PS1"

# Sync Portage
emerge-webrsync
emerge --quiet --sync

# Set timezone
echo "Pacific/Auckland" > /etc/timezone
emerge -v --config sys-libs/timezone-data

## Install kernel headers for early bootstrapping
#emerge sys-kernel/gentoo-sources
#eselect kernel set 1
#pushd /usr/src/linux
#make clean
#make mrproper
#make -j${NUMCPUSPLUSONE} headers && make -j${NUMCPUSPLUSONE} headers_install
#popd

# GCC must be openmp capable
echo "sys-devel/gcc openmp" > /etc/portage/package.use/gcc

# Bootstrap basesystem toolchain
pushd /var/db/repos/gentoo/scripts
yes | ALLOWED_USE="openmp" ./bootstrap.sh && \
yes | ALLOWED_USE="openmp" ./bootstrap.sh
touch /tmp/prebuild_checkpoint
popd

# Rebuild world
emerge -e --with-bdeps=y @world
emerge --depclean

# Check that all binaries were replaced by emerge world
find / -type d -path /boot -prune -o -path /proc -prune -o -type f -executable -not -newer /tmp/prebuild_checkpoint -print0 2>/dev/null | xargs -0 file --no-pad --separator="@@@" | grep -iv '@@@.* text'
find / -type d -path /boot -prune -o -path /proc -prune -o -type f -not -executable -not -newer /tmp/prebuild_checkpoint -print0 2>/dev/null | xargs -0 file --no-pad --separator="@@@" | grep '@@@.*\( ELF\| ar archive\)'


# Disable predictable network interface names
# NOTE: This is also configured in the built-in Kernel comand line, but
#       better safe than sorry.
touch /etc/udev/rules.d/80-net-name-slot.rules



#
# -- ADDITIONAL TOOLS
#

 # * Messages for package app-portage/gentoolkit-0.5.0:

 # * 
 # * For further information on gentoolkit, please read the gentoolkit
 # * guide: https://wiki.gentoo.org/wiki/Gentoolkit
 # * 
 # * Another alternative to equery is app-portage/portage-utils
 # * 
 # * Additional tools that may be of interest:
 # * 
 # *     app-admin/eclean-kernel
 # *     app-portage/diffmask
 # *     app-portage/flaggie
 # *     app-portage/install-mask
 # *     app-portage/portpeek
 # *     app-portage/smart-live-rebuild

emerge sys-kernel/gentoo-sources app-crypt/efitools sys-boot/efibootmgr sys-libs/efivar app-portage/gentoolkit sys-block/parted sys-libs/gpm sys-fs/dosfstools app-emulation/qemu-guest-agent sys-power/acpid

# Start qemu-guent-agent and acpid for Hypervisor integration
rc-update add acpid default
rc-service acpid start
rc-update add qemu-guest-agent default
rc-service qemu-guest-agent start

#
# -- Building the kernel
#

eselect kernel set 1
pushd /usr/src/linux
make clean
make mrproper

# Generate initial kernel config file
make defconfig

# Kernel Config

# Set buildin config support exposed via /proc/config.gz
sed -i -e "s/^# CONFIG_IKCONFIG.*/CONFIG_IKCONFIG=y/" /usr/src/linux/.config
sed -i -e "/^CONFIG_IKCONFIG=/a\\
CONFIG_IKCONFIG_PROC=y" /usr/src/linux/.config

# Set kernel builtin command line
ROOT_PARTUUID=`blkid /dev/vda4 | tr -s " " "\n" | grep PARTUUID | sed -e 's/\"//g'`
sed -i -e "s/^# CONFIG_CMDLINE_BOOL.*/CONFIG_CMDLINE_BOOL=y/" /usr/src/linux/.config
sed -i -e"/^CONFIG_CMDLINE_BOOL/a\\
CONFIG_CMDLINE=\"root=${ROOT_PARTUUID} net.ifnames=0\"" /usr/src/linux/.config
sed -i -e"/^CONFIG_CMDLINE=/a\\
# CONFIG_CMDLINE_OVERRIDE is not set" /usr/src/linux/.config

# Set simple framebuffer support
sed -i -e "s/^# CONFIG_VT_HW_CONSOLE_BINDING.*/CONFIG_VT_HW_CONSOLE_BINDING=y/" /usr/src/linux/.config
sed -i -e "/^CONFIG_DRM_KMS_HELPER/a\\
CONFIG_DRM_FBDEV_EMULATION=y" /usr/src/linux/.config
sed -i -e "/^CONFIG_DRM_FBDEV_EMULATION/a\\
CONFIG_DRM_FBDEV_OVERALLOC=100" /usr/src/linux/.config

sed -i -e "/^CONFIG_FB_CMDLINE/a\\
CONFIG_FB_NOTIFY=y" /usr/src/linux/.config
sed -i -e "s/^# CONFIG_FB is not set/CONFIG_FB=y/" /usr/src/linux/.config
sed -i -e "/^CONFIG_FB=y/a\\
# CONFIG_FIRMWARE_EDID is not set\\
CONFIG_FB_CFB_FILLRECT=y\\
CONFIG_FB_CFB_COPYAREA=y\\
CONFIG_FB_CFB_IMAGEBLIT=y\\
CONFIG_FB_SYS_FILLRECT=y\\
CONFIG_FB_SYS_COPYAREA=y\\
CONFIG_FB_SYS_IMAGEBLIT=y\\
# CONFIG_FB_FOREIGN_ENDIAN is not set\\
CONFIG_FB_SYS_FOPS=y\\
CONFIG_FB_DEFERRED_IO=y\\
# CONFIG_FB_MODE_HELPERS is not set\\
# CONFIG_FB_TILEBLITTING is not set\\
\\
#\\
# Frame buffer hardware drivers\\
#\\
# CONFIG_FB_CIRRUS is not set\\
# CONFIG_FB_PM2 is not set\\
# CONFIG_FB_CYBER2000 is not set\\
# CONFIG_FB_ARC is not set\\
# CONFIG_FB_ASILIANT is not set\\
# CONFIG_FB_IMSTT is not set\\
# CONFIG_FB_VGA16 is not set\\
# CONFIG_FB_UVESA is not set\\
# CONFIG_FB_VESA is not set\\
# CONFIG_FB_EFI is not set\\
# CONFIG_FB_N411 is not set\\
# CONFIG_FB_HGA is not set\\
# CONFIG_FB_OPENCORES is not set\\
# CONFIG_FB_S1D13XXX is not set\\
# CONFIG_FB_NVIDIA is not set\\
# CONFIG_FB_RIVA is not set\\
# CONFIG_FB_I740 is not set\\
# CONFIG_FB_LE80578 is not set\\
# CONFIG_FB_MATROX is not set\\
# CONFIG_FB_RADEON is not set\\
# CONFIG_FB_ATY128 is not set\\
# CONFIG_FB_ATY is not set\\
# CONFIG_FB_S3 is not set\\
# CONFIG_FB_SAVAGE is not set\\
# CONFIG_FB_SIS is not set\\
# CONFIG_FB_NEOMAGIC is not set\\
# CONFIG_FB_KYRO is not set\\
# CONFIG_FB_3DFX is not set\\
# CONFIG_FB_VOODOO1 is not set\\
# CONFIG_FB_VT8623 is not set\\
# CONFIG_FB_TRIDENT is not set\\
# CONFIG_FB_ARK is not set\\
# CONFIG_FB_PM3 is not set\\
# CONFIG_FB_CARMINE is not set\\
# CONFIG_FB_SMSCUFX is not set\\
# CONFIG_FB_UDL is not set\\
# CONFIG_FB_IBM_GXT4500 is not set\\
# CONFIG_FB_VIRTUAL is not set\\
# CONFIG_FB_METRONOME is not set\\
# CONFIG_FB_MB862XX is not set\\
# CONFIG_FB_SM712 is not set" /usr/src/linux/.config

sed -i -e "/^# CONFIG_GART_IOMMU/a\\
CONFIG_BOOT_VESA_SUPPORT=y" /usr/src/linux/.config

sed -i -e "/^# CONFIG_FW_CFG_SYSFS/a\\
CONFIG_SYSFB=y" /usr/src/linux/.config

sed -i -e "s/^# CONFIG_DRM_SIMPLEDRM.*/CONFIG_DRM_SIMPLEDRM=y/" /usr/src/linux/.config

sed -i -e "s/^# CONFIG_FB_EFI.*/CONFIG_FB_EFI=y/" /usr/src/linux/.config

sed -i -e "/^CONFIG_DUMMY_CONSOLE_ROWS=25/a\\
CONFIG_FRAMEBUFFER_CONSOLE=y\\
# CONFIG_FRAMEBUFFER_CONSOLE_LEGACY_ACCELERATION is not set\\
CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y\\
# CONFIG_FRAMEBUFFER_CONSOLE_ROTATION is not set\\
# CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER is not set" /usr/src/linux/.config

sed -i -e "/^# end of Console display driver support/a\\
# CONFIG_LOGO is not set" /usr/src/linux/.config

sed -i -e "/^CONFIG_FONT_SUPPORT=y/a\\
# CONFIG_FONTS is not set\\
CONFIG_FONT_8x8=y" /usr/src/linux/.config

sed -i -e "/CONFIG_FONT_AUTOSELECT=y/d" /usr/src/linux/.config

# Build and install the kernel, set the EFI boot option
make -j${NUMCPUSPLUSONE} && make -j${NUMCPUSPLUSONE} modules_install
mkdir -pv /boot/EFI/boot
cp /usr/src/linux/arch/x86_64/boot/bzImage /boot/EFI/boot/BOOTX64.EFI
efibootmgr -c -d /dev/vda -p 2 -L boot -l '\EFI\BOOT\BOOTX64.EFI'

# Configure filesystem
cat >> /etc/fstab << EOF
LABEL=boot		/boot		vfat		noauto,noatime,discard	1 2
LABEL=root		/		ext4		noatime,discard		0 1
LABEL=swap		none		swap		sw,discard		0 0
EOF

# Generate ssh keys
ssh-keygen -f $HOME/.ssh/id_rsa -N '' -q

# Enable ssh server on boot
rc-update add sshd default

# Enable root password login
sed -i "/^#PermitRootLogin/a\\
PermitRootLogin yes" /etc/ssh/sshd_config
sed -i -e "s/PasswordAuthentication no/PasswordAuthentication yes/" /etc/ssh/sshd_config

sed -i -e 's/enforce=.*/enforce=none/' /etc/security/passwdqc.conf
echo -e "ub1qu1ty\nub1qu1ty\n" | passwd root

exit
