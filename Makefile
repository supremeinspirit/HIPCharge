SHELL := /var/jb/bin/sh
SDK ?= /var/jb/usr/share/SDKs/iPhoneOS.sdk
PREFIX ?= /var/jb
VERSION = 1.5.0

hipchargd: main.c banner.m banner.h ent.plist
	clang -isysroot $(SDK) -arch arm64 -miphoneos-version-min=15.0 -O2 -Wall -fobjc-arc \
		-framework CoreFoundation -framework SystemConfiguration -framework IOKit \
		-framework Foundation -framework UserNotifications \
		-o $@ main.c banner.m
	ldid -Sent.plist $@

deb: hipchargd
	rm -rf pkg && mkdir -p pkg/DEBIAN pkg$(PREFIX)/usr/libexec pkg$(PREFIX)/Library/LaunchDaemons
	cp hipchargd pkg$(PREFIX)/usr/libexec/
	cp com.supremeinspirit.hipcharge.plist pkg$(PREFIX)/Library/LaunchDaemons/
	sed 's/@VERSION@/$(VERSION)/' control > pkg/DEBIAN/control
	chmod -R 755 pkg && cp postinst prerm pkg/DEBIAN/ && chmod 644 pkg/DEBIAN/control && chmod 755 pkg/DEBIAN/postinst pkg/DEBIAN/prerm
	dpkg-deb -Zxz --root-owner-group -b pkg HIPCharge_$(VERSION)_rootless_iphoneos-arm64.deb

# Rootful iOS 12-14 package: banner-only daemon + HIPChargeTM tweak in thermalmonitord
LEGACY_CFLAGS = -isysroot $(SDK) -arch arm64 -miphoneos-version-min=12.0 -O2 -Wall -fobjc-arc

legacy/hipchargd: main.c banner.m banner.h ent.plist
	mkdir -p legacy
	clang $(LEGACY_CFLAGS) -DHIPCHARGE_TWEAK \
		-framework CoreFoundation -framework IOKit -framework Foundation -framework UserNotifications \
		-o $@ main.c banner.m
	ldid -Sent.plist $@

# arm64e uses the iOS 14+ (versioned) ABI; A12+ devices on iOS 12-13 may reject that slice
legacy/HIPChargeTM.dylib: tweak/HIPChargeTM.m
	mkdir -p legacy
	clang $(LEGACY_CFLAGS) -arch arm64e -dynamiclib -framework Foundation -o $@ $<
	ldid -S $@

legacy-deb: legacy/hipchargd legacy/HIPChargeTM.dylib
	rm -rf legacy/pkg && mkdir -p legacy/pkg/DEBIAN legacy/pkg/usr/libexec legacy/pkg/Library/LaunchDaemons legacy/pkg/Library/MobileSubstrate/DynamicLibraries
	cp legacy/hipchargd legacy/pkg/usr/libexec/
	cp legacy/HIPChargeTM.dylib tweak/HIPChargeTM.plist legacy/pkg/Library/MobileSubstrate/DynamicLibraries/
	sed 's#/var/jb##g' com.supremeinspirit.hipcharge.plist > legacy/pkg/Library/LaunchDaemons/com.supremeinspirit.hipcharge.plist
	sed -e 's/@VERSION@/$(VERSION)/' -e 's/^Architecture: .*/Architecture: iphoneos-arm/' \
		-e 's/^Depends: .*/Depends: firmware (>= 12.0), firmware (<< 15.0), mobilesubstrate/' \
		-e 's/^Name: .*/Name: HIPCharge (Legacy)/' control > legacy/pkg/DEBIAN/control
	sed 's#/var/jb##g' postinst > legacy/pkg/DEBIAN/postinst
	sed 's#/var/jb##g' prerm > legacy/pkg/DEBIAN/prerm
	chmod -R 755 legacy/pkg && chmod 644 legacy/pkg/DEBIAN/control legacy/pkg/Library/MobileSubstrate/DynamicLibraries/HIPChargeTM.plist legacy/pkg/Library/LaunchDaemons/com.supremeinspirit.hipcharge.plist
	dpkg-deb -Zxz --root-owner-group -b legacy/pkg HIPCharge_$(VERSION)_legacy-rootful_iphoneos-arm.deb

clean:
	rm -rf hipchargd pkg legacy *.deb
