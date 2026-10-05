SHELL := /var/jb/bin/sh
SDK ?= /var/jb/usr/share/SDKs/iPhoneOS.sdk
PREFIX ?= /var/jb
VERSION = 1.6.0
# The Control Center modules need the private ControlCenterUIKit stub and headers from Theos
CCSDK ?= /var/jb/theos/sdks/iPhoneOS16.5.sdk
CCINCLUDE ?= /var/jb/theos/vendor/include
CCMODULES = HIPChargeModule HIPChargeSimulateModule
CCFLAGS = -isysroot $(CCSDK) -I$(CCINCLUDE) -F$(CCSDK)/System/Library/PrivateFrameworks -arch arm64 -arch arm64e \
	-O2 -Wall -fobjc-arc -bundle -framework UIKit -framework Foundation -framework ControlCenterUIKit

hipchargd: main.c banner.m banner.h ipc.h ent.plist
	clang -isysroot $(SDK) -arch arm64 -miphoneos-version-min=15.0 -O2 -Wall -fobjc-arc \
		-framework CoreFoundation -framework SystemConfiguration -framework IOKit \
		-framework Foundation -framework UserNotifications \
		-o $@ main.c banner.m
	ldid -Sent.plist $@

# $(call ccbundles,<min iOS>,<Bundles dir>): build both module bundles into that directory
define ccbundles
	for m in $(CCMODULES); do \
		b=$(2)/$$m.bundle; mkdir -p $$b || exit 1; \
		case $$m in HIPChargeSimulateModule) d=-DHIPCHARGE_SIMULATE_MODULE; n="Simulate HIP";; *) d=; n=HIPCharge;; esac; \
		clang $(CCFLAGS) -miphoneos-version-min=$(1) $$d -o $$b/$$m ccmodule/HIPChargeModule.m || exit 1; \
		ldid -S $$b/$$m || exit 1; \
		sed -e "s/@NAME@/$$m/g" -e "s/@DISPLAY@/$$n/" -e "s/@VERSION@/$(VERSION)/" \
			-e "s/@ID@/$$(echo $$m | tr A-Z a-z)/" ccmodule/Info.plist > $$b/Info.plist || exit 1; \
		for i in ccmodule/$$m-SettingsIcon*.png; do cp $$i $$b/$${i#ccmodule/$$m-} || exit 1; done; \
	done
endef

deb: hipchargd ccmodule/HIPChargeModule.m ccmodule/Info.plist
	rm -rf pkg && mkdir -p pkg/DEBIAN pkg$(PREFIX)/usr/libexec pkg$(PREFIX)/Library/LaunchDaemons
	cp hipchargd pkg$(PREFIX)/usr/libexec/
	cp com.supremeinspirit.hipcharge.plist pkg$(PREFIX)/Library/LaunchDaemons/
	$(call ccbundles,15.0,pkg$(PREFIX)/Library/ControlCenter/Bundles)
	sed 's/@VERSION@/$(VERSION)/' control > pkg/DEBIAN/control
	chmod -R 755 pkg && cp postinst prerm pkg/DEBIAN/ && chmod 644 pkg/DEBIAN/control && chmod 755 pkg/DEBIAN/postinst pkg/DEBIAN/prerm
	find pkg -name Info.plist -o -name '*.png' | xargs chmod 644
	dpkg-deb -Zxz --root-owner-group -b pkg HIPCharge_$(VERSION)_rootless_iphoneos-arm64.deb

# Rootful iOS 12-14 package: banner-only daemon + HIPChargeTM tweak in thermalmonitord
LEGACY_CFLAGS = -isysroot $(SDK) -arch arm64 -miphoneos-version-min=12.0 -O2 -Wall -fobjc-arc

legacy/hipchargd: main.c banner.m banner.h ipc.h ent.plist
	mkdir -p legacy
	clang $(LEGACY_CFLAGS) -DHIPCHARGE_TWEAK \
		-framework CoreFoundation -framework IOKit -framework Foundation -framework UserNotifications \
		-o $@ main.c banner.m
	ldid -Sent.plist $@

# arm64e uses the iOS 14+ (versioned) ABI; A12+ devices on iOS 12-13 may reject that slice
legacy/HIPChargeTM.dylib: tweak/HIPChargeTM.m ipc.h
	mkdir -p legacy
	clang $(LEGACY_CFLAGS) -arch arm64e -dynamiclib -framework Foundation -o $@ $<
	ldid -S $@

legacy-deb: legacy/hipchargd legacy/HIPChargeTM.dylib ccmodule/HIPChargeModule.m ccmodule/Info.plist
	rm -rf legacy/pkg && mkdir -p legacy/pkg/DEBIAN legacy/pkg/usr/libexec legacy/pkg/Library/LaunchDaemons legacy/pkg/Library/MobileSubstrate/DynamicLibraries
	cp legacy/hipchargd legacy/pkg/usr/libexec/
	cp legacy/HIPChargeTM.dylib tweak/HIPChargeTM.plist legacy/pkg/Library/MobileSubstrate/DynamicLibraries/
	$(call ccbundles,12.0,legacy/pkg/Library/ControlCenter/Bundles)
	sed 's#/var/jb##g' com.supremeinspirit.hipcharge.plist > legacy/pkg/Library/LaunchDaemons/com.supremeinspirit.hipcharge.plist
	sed -e 's/@VERSION@/$(VERSION)/' -e 's/^Architecture: .*/Architecture: iphoneos-arm/' \
		-e 's/^Depends: .*/Depends: firmware (>= 12.0), firmware (<< 15.0), mobilesubstrate/' \
		-e 's/^Name: .*/Name: HIPCharge (Legacy)/' control > legacy/pkg/DEBIAN/control
	sed 's#/var/jb##g' postinst > legacy/pkg/DEBIAN/postinst
	sed 's#/var/jb##g' prerm > legacy/pkg/DEBIAN/prerm
	chmod -R 755 legacy/pkg && find legacy/pkg -name Info.plist -o -name '*.png' | xargs chmod 644 && chmod 644 legacy/pkg/DEBIAN/control legacy/pkg/Library/MobileSubstrate/DynamicLibraries/HIPChargeTM.plist legacy/pkg/Library/LaunchDaemons/com.supremeinspirit.hipcharge.plist
	dpkg-deb -Zxz --root-owner-group -b legacy/pkg HIPCharge_$(VERSION)_legacy-rootful_iphoneos-arm.deb

clean:
	rm -rf hipchargd pkg legacy *.deb
