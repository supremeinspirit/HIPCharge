SHELL := /var/jb/bin/sh
SDK ?= /var/jb/usr/share/SDKs/iPhoneOS.sdk
PREFIX ?= /var/jb
VERSION = 1.4.0

hipchargd: main.c banner.m banner.h ent.plist
	clang -isysroot $(SDK) -arch arm64 -miphoneos-version-min=15.0 -O2 -Wall -fobjc-arc \
		-framework CoreFoundation -framework SystemConfiguration -framework IOKit \
		-framework Foundation -framework UserNotifications \
		-o $@ main.c banner.m
	ldid -Sent.plist $@

deb: hipchargd
	rm -rf pkg && mkdir -p pkg/DEBIAN pkg$(PREFIX)/usr/libexec pkg$(PREFIX)/Library/LaunchDaemons
	cp hipchargd pkg$(PREFIX)/usr/libexec/
	cp com.flo.hipcharge.plist pkg$(PREFIX)/Library/LaunchDaemons/
	sed 's/@VERSION@/$(VERSION)/' control > pkg/DEBIAN/control
	chmod -R 755 pkg && cp postinst prerm pkg/DEBIAN/ && chmod 644 pkg/DEBIAN/control && chmod 755 pkg/DEBIAN/postinst pkg/DEBIAN/prerm
	dpkg-deb -Zxz --root-owner-group -b pkg com.flo.hipcharge_$(VERSION)_iphoneos-arm64.deb

clean:
	rm -rf hipchargd pkg *.deb
