ARCHS = armv7
# Original iPhoneOS 8.4 SDK extracted from Apple Xcode 6.4.
TARGET = iphone:clang:8.4:8.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = NASPhotoFrame
TOOL_NAME = PFChargeLimiter PFDisplayScheduler PFRemoteControl

NASPhotoFrame_INSTALL_PATH = /Applications
NASPhotoFrame_USE_MODULES = 0
NASPhotoFrame_FILES = $(wildcard Sources/*.m) $(wildcard ThirdParty/libsmb2/lib/*.c)
NASPhotoFrame_CFLAGS = -std=gnu11 -DHAVE_CONFIG_H -D_U_=__attribute__\(\(unused\)\) \
	-IThirdParty/libsmb2/include/apple -IThirdParty/libsmb2/include \
	-IThirdParty/libsmb2/include/smb2 -IThirdParty/libsmb2/lib -IThirdParty/libsmb2/libdcerpc
NASPhotoFrame_CFLAGS += -Wno-deprecated-declarations -Wno-unused-function -Wno-unused-variable
NASPhotoFrame_OBJCFLAGS = -fobjc-arc
THEOS_LEGACY_LINKER := $(shell xcrun -f ld-classic 2>/dev/null)
ifneq ($(THEOS_LEGACY_LINKER),)
NASPhotoFrame_LDFLAGS = -fuse-ld=$(THEOS_LEGACY_LINKER)
endif
NASPhotoFrame_FRAMEWORKS = UIKit Foundation Security ImageIO CoreGraphics QuartzCore SystemConfiguration CoreLocation
NASPhotoFrame_LIBRARIES = sqlite3
NASPhotoFrame_RESOURCE_DIRS = Resources
# A Theos-installed app needs an explicit Keychain access group.  Otherwise
# Security.framework returns errSecMissingEntitlement (-34018) when saving the
# SMB password on device.
NASPhotoFrame_CODESIGN_FLAGS = -SNASPhotoFrame.entitlements

# A root launch daemon keeps the charge policy active independently of the
# foreground photo-frame app.  The daemon targets the same iOS 8/armv7 runtime.
PFChargeLimiter_FILES = ChargeLimiter/PFChargeLimiter.m
PFChargeLimiter_USE_MODULES = 0
PFChargeLimiter_OBJCFLAGS = -fobjc-arc
PFChargeLimiter_FRAMEWORKS = Foundation IOKit
PFChargeLimiter_INSTALL_PATH = /usr/libexec
PFChargeLimiter_CODESIGN_FLAGS = -SChargeLimiter/PFChargeLimiter.entitlements

# Two calendar-triggered launchd jobs call this small root helper to lock the
# display at night and wake/unlock directly into the photo-frame app in the
# morning.  It uses the iOS 8 SpringBoardServices API already present on device.
PFDisplayScheduler_FILES = DisplayScheduler/PFDisplayScheduler.m
PFDisplayScheduler_USE_MODULES = 0
PFDisplayScheduler_OBJCFLAGS = -fobjc-arc
PFDisplayScheduler_FRAMEWORKS = Foundation IOKit
PFDisplayScheduler_PRIVATE_FRAMEWORKS = SpringBoardServices BackBoardServices
PFDisplayScheduler_INSTALL_PATH = /usr/libexec

# A small command-line bridge used by the LAN-only NAS management page.  It
# reads and updates the photo-frame preference domain and shares the app's
# Keychain access group so an explicitly supplied SMB password can be changed.
PFRemoteControl_FILES = RemoteControl/PFRemoteControl.m Sources/PFCredentialStore.m
PFRemoteControl_USE_MODULES = 0
PFRemoteControl_CFLAGS = -ISources
PFRemoteControl_OBJCFLAGS = -fobjc-arc
PFRemoteControl_FRAMEWORKS = Foundation Security
PFRemoteControl_LIBRARIES = sqlite3
PFRemoteControl_INSTALL_PATH = /usr/libexec
PFRemoteControl_CODESIGN_FLAGS = -SNASPhotoFrame.entitlements

include $(THEOS_MAKE_PATH)/application.mk
include $(THEOS_MAKE_PATH)/tool.mk

after-install::
	install.exec "killall -9 SpringBoard || true"
