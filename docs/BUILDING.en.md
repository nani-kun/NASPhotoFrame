# Building and Installation

## 1. Prepare Theos

Install the required dependencies and clone Theos according to the official Theos instructions. For example:

```sh
git clone --recursive https://github.com/theos/theos.git /opt/theos
export THEOS=/opt/theos
```

This project has been verified with Theos commit `5280bd038207e14f8bd76f5417aa2fe641c03228`. Newer Theos versions may also work, but the legacy SDK, `armv7` linking, and package output must be revalidated.

## 2. Prepare the iPhoneOS 8.4 SDK

Current Xcode releases no longer include linkable 32-bit iOS 8 system libraries. Sign in to Apple Developer Downloads, obtain Xcode 6.4 yourself, and extract the original `iPhoneOS8.4.sdk`. Do not commit the Xcode disk image or SDK to the Git repository.

Place the SDK at:

```text
$THEOS/sdks/iPhoneOS8.4.sdk
```

Verify the path:

```sh
test -d "$THEOS/sdks/iPhoneOS8.4.sdk/System/Library/Frameworks"
```

## 3. Build the Debian Package

```sh
export THEOS=/path/to/theos
make clean package
```

The resulting package is written to `packages/`. This directory is excluded by `.gitignore`.

The project's key build targets are:

```make
ARCHS = armv7
TARGET = iphone:clang:8.4:8.0
```

## 4. Install on the Device

First create an SSH host alias for the device. Do not write a real address into the repository:

```sshconfig
Host nas-photo-frame-ipad
    HostName 192.168.1.100
    User root
    HostKeyAlgorithms +ssh-rsa
    PubkeyAcceptedAlgorithms +ssh-rsa
```

Old devices may offer only `ssh-rsa` host keys, which newer OpenSSH versions disable by default. Apply this compatibility configuration only to the isolated device; do not weaken SSH security globally.

Install with Theos:

```sh
export THEOS_DEVICE_IP=nas-photo-frame-ipad
export THEOS_DEVICE_PORT=22
make package install
```

Alternatively, transfer the `.deb` and install it on the device:

```sh
scp packages/com.wangxiaoxiang.nasphotoframe_*.deb nas-photo-frame-ipad:/tmp/
ssh nas-photo-frame-ipad 'dpkg -i /tmp/com.wangxiaoxiang.nasphotoframe_*.deb && uicache'
```

## 5. Verify the Installation

The application bundle and all three helper programs should be built for `armv7`, with iOS 8.0 as the minimum system version. After installation, run:

```sh
/usr/libexec/PFChargeLimiter status
/usr/libexec/PFDisplayScheduler status
/usr/libexec/PFDisplayScheduler power-events
```

Then open “NAS Photo Frame” from the Home Screen, test the NAS connection, and complete the first index.

## Troubleshooting

### iPhoneOS8.4.sdk Not Found

Check that `$THEOS` points to the correct directory and that the SDK folder is named exactly `iPhoneOS8.4.sdk`. Do not substitute a modern SDK that contains only symbols or lacks 32-bit libraries.

### Keychain Returns `errSecMissingEntitlement (-34018)`

Confirm that both the application and `PFRemoteControl` use `NASPhotoFrame.entitlements`, and that no packaging step removes their signatures.

### Linking Fails on a Newer macOS Version

The `Makefile` prefers `ld-classic` when it is available. If linking still fails, record the Xcode command-line tools version, Theos commit, and complete linker error before opening an issue.

### The Device Is Unstable After Installation

Uninstall the package first. The uninstall script attempts to restore normal charging. If you manually removed the charge daemon, also run:

```sh
/usr/libexec/PFChargeLimiter enable
```
