# Example Image Installer for aarch64 EFI blscfg with Fedora 31 or CentOS 8

# Build Procedure
1. https://alt.fedoraproject.org/cloud/ Install Fedora 30 aarch64. "arm64 AMIs" -> "Click to launch" has a convenient image to launch on AWS.
2. `dnf system-upgrade download --refresh --releasever=31`
3. `dnf system-upgrade reboot` upgrade to Fedora 31
4. `setenforce 0` to workaround https://bugzilla.redhat.com/show_bug.cgi?id=1736803
5. `git clone https://github.com/wtogami/example-efi-blscfg-imagecreator.git`
6. `cd example-efi-blscfg-imagecreator`
7. **IMPORTANT** Add your ssh pubkey to `include/debug-ssh-pubkeys.ksi` as this is your only way to login!
7. Follow examples below
```
# ./createimage.sh 

SYNOPSIS
   ./createimage.sh <KICKSTARTFILE>

EXAMPLES
   ./createimage.sh hbp-fedora31.ks
   ./createimage.sh hbp-el8.ks

```

