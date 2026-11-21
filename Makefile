# Jellyfin for Apple TV 3 (8.4, jailbroken with blackb0x).  armv7, iOS 8 SDK
# stubs from theos/sdks (iPhoneOS9.3, simulator archs stripped so Xcode's
# linker accepts them): `make sdk` fetches it once.
SDK     := $(CURDIR)/sdk/iPhoneOS9.3.sdk
SDKURL  := https://github.com/theos/sdks/releases/download/master-146e41f/iPhoneOS9.3.sdk.tar.xz
TARGET  := -target armv7-apple-ios8.0 -isysroot $(SDK)
# No objc_alloc/objc_opt_* shortcuts: those runtime calls appeared in iOS 12.
# -marm: today's linker no longer sets the Thumb bit on armv7 function
# pointers (entry point, constructors, ObjC method lists), so Thumb code dies
# with "Illegal instruction" on the device.  ARM-mode code has no such bit.
CFLAGS  := $(TARGET) -marm -O2 -Wall -fno-objc-arc -fno-objc-convert-messages-to-runtime-calls -Isrc
LDFLAGS := $(TARGET) -bundle -framework UIKit -framework Foundation -framework QuartzCore \
           -framework CoreGraphics -framework AVFoundation -framework CoreMedia -framework CFNetwork -lobjc
BUNDLE  := build/Jellyfin.frappliance
# src/*.m: the BackRow glue, manual retain/release.  src/app/*.m: the app, ARC.
SRCS    := $(wildcard src/*.m)
APPSRCS := $(wildcard src/app/*.m)
OBJS    := $(SRCS:src/%.m=build/obj/%.o) $(APPSRCS:src/app/%.m=build/obj/app/%.o)
AFC2    := tools/afc2

all: $(BUNDLE)

# The SDK's .tbd stubs list i386/x86_64 too, and today's ld then takes them for
# the simulator; armv7-only stubs link as device code.
sdk:
	mkdir -p sdk && curl -L $(SDKURL) | tar -xJ -C sdk
	find $(SDK) -type f -name '*.tbd' -exec sed -i '' -E 's/, *i386//g; s/, *x86_64//g; s/\[ *i386, */[ /g; s/\[ *x86_64, */[ /g' {} +

build/obj/app/%.o: src/app/%.m $(wildcard src/*.h) $(wildcard src/app/*.h)
	@mkdir -p $(dir $@)
	xcrun clang $(CFLAGS) -fobjc-arc -Isrc/app -c $< -o $@

# After the app rule: make 3.81 takes the first matching pattern.
build/obj/%.o: src/%.m $(wildcard src/*.h) $(wildcard src/app/*.h)
	@mkdir -p $(dir $@)
	xcrun clang $(CFLAGS) -Isrc/app -c $< -o $@

ICONSVG := resources/brand/icon-transparent.svg
build/menucache/%@720.png build/menucache/%@1080.png: $(ICONSVG) tools/make_icons.swift
	@mkdir -p build/menucache
	swift tools/make_icons.swift $(ICONSVG) build/menucache 188 108 $*@720.png
	swift tools/make_icons.swift $(ICONSVG) build/menucache 284 161 $*@1080.png

$(BUNDLE): $(OBJS) Info.plist $(wildcard resources/*)
	@mkdir -p $@
	xcrun clang $(LDFLAGS) $(OBJS) -o $@/Jellyfin 2> build/link.log; st=$$?; grep -v liblaunch build/link.log; exit $$st
	cp Info.plist $@/
	cp resources/*.png $@/
	# The kernel kills unsigned code; any ad-hoc signature is accepted.
	ldid -S $@/Jellyfin

# Copy to the Apple TV over USB (afc2, installed by blackb0x).  The bundle
# lives in /Applications/Jellyfin.frappliance, and AppleTV.app/Appliances holds
# a symlink to it, as Kodi's does (beigelist crashes on a real folder there; the
# link is made once over SSH, AFC cannot create it).
#
# Every file is deleted and written fresh: iOS caches a file's code signature
# the first time it is mapped, and new contents in the same file are killed.
APPDIR := /Applications/Jellyfin.frappliance
MENUCACHE := /var/mobile/Library/Caches/AppleTV/MainMenu
$(AFC2): tools/afc2.c
	clang -O2 -o $@ $< $$(pkg-config --cflags --libs libimobiledevice-1.0)

deploy: $(BUNDLE) build/menucache/com.apple.frontrow.appliance.jellyfin@720.png $(AFC2)
	-$(AFC2) mkdir $(APPDIR) 2>/dev/null
	for f in $(BUNDLE)/*.png $(BUNDLE)/Info.plist $(BUNDLE)/Jellyfin; do \
	  $(AFC2) rm $(APPDIR)/$$(basename $$f) 2>/dev/null; \
	  $(AFC2) put $$f $(APPDIR)/$$(basename $$f) || exit 1; done
	-$(AFC2) mkdir $(APPDIR)/English.lproj 2>/dev/null
	-$(AFC2) rm $(APPDIR)/English.lproj/InfoPlist.strings 2>/dev/null
	$(AFC2) put resources/English.lproj/InfoPlist.strings $(APPDIR)/English.lproj/InfoPlist.strings
	# The main menu shows icons from its own cache, <bundle id>@720/@1080.png.
	for r in 720 1080; do f=com.apple.frontrow.appliance.jellyfin@$$r.png; \
	  $(AFC2) rm $(MENUCACHE)/$$f 2>/dev/null; $(AFC2) put build/menucache/$$f $(MENUCACHE)/$$f || exit 1; done

# Never reboot the Apple TV over USB: with the cable attached it stops in
# Recovery Mode.  Ask the running app to quit instead; it is relaunched.
reload:
	echo reload > build/cmd.txt && afcclient put build/cmd.txt /jf_cmd.txt

# Remote control over USB: `make open`, `make key K="down right select"`.
open:
	echo open > build/cmd.txt && afcclient put build/cmd.txt /jf_cmd.txt
key:
	echo "key $(K)" > build/cmd.txt && afcclient put build/cmd.txt /jf_cmd.txt

# Screenshot of the app's screen, saved to build/shot.png.
shot:
	rm -f build/shot.png; afcclient rm /jf_shot.png >/dev/null 2>&1 || true
	echo shot > build/cmd.txt && afcclient put build/cmd.txt /jf_cmd.txt
	until afcclient ls / | grep -q jf_shot.png; do sleep 1; done; sleep 2
	afcclient get /jf_shot.png build/shot.png >/dev/null
	sips -f vertical build/shot.png >/dev/null   # see JFRootView: the capture misses BackRow's flip
	@ls -l build/shot.png

clean:
	rm -rf build

# The screenshots the app saved while it was used on the TV (newest last).
shots:
	@mkdir -p build/shots
	for i in 0 1 2 3 4 5 6 7 8 9; do afcclient get /jf_auto_$$i.png build/shots/auto_$$i.png >/dev/null 2>&1; done
	afcclient get /jf_auto_last.txt build/shots/last.txt >/dev/null 2>&1; cat build/shots/last.txt
	afcclient get /jf_log.txt build/jf_log.txt >/dev/null 2>&1; tail -30 build/jf_log.txt

.PHONY: all sdk deploy reload open key shot shots clean

# ---- screenshots ------------------------------------------------------------------------
# The app's UI code in the iOS Simulator (tools/shots), against Jellyfin's
# public demo server, so no personal library ends up in the pictures.
SIMSDK   = $(shell xcrun --sdk iphonesimulator --show-sdk-path)
SIMAPP  := build/shots/Shots.app
SIMDEV  ?= iPad Pro 11-inch (M5)
DEMO    := https://demo.jellyfin.org/stable
SHOTDIR := $(CURDIR)/docs/screenshots

$(SIMAPP): tools/shots/main.m $(APPSRCS) $(wildcard src/app/*.h) src/JFRootView.h
	@mkdir -p $@
	xcrun clang -target arm64-apple-ios15.0-simulator -isysroot $(SIMSDK) -fobjc-arc -O1 -w \
	  -Isrc -Isrc/app tools/shots/main.m $(APPSRCS) -o $@/Shots \
	  -framework UIKit -framework Foundation -framework CoreGraphics -framework AVFoundation -framework CoreMedia -framework QuartzCore
	plutil -create xml1 $@/Info.plist
	plutil -insert CFBundleIdentifier -string org.jellyfin.atv3.shots $@/Info.plist
	plutil -insert CFBundleExecutable -string Shots $@/Info.plist
	plutil -insert CFBundleName -string Shots $@/Info.plist
	plutil -insert CFBundleVersion -string 1 $@/Info.plist
	plutil -insert CFBundleShortVersionString -string 1.0 $@/Info.plist
	plutil -insert UIApplicationSceneManifest -json '{"UIApplicationSupportsMultipleScenes":false,"UISceneConfigurations":{"UIWindowSceneSessionRoleApplication":[{"UISceneConfigurationName":"Default","UISceneDelegateClassName":"ShotsScene"}]}}' $@/Info.plist
	codesign -f -s - $@

# Run one step list in the simulator: make shots-run STEPS="server ...; open; ..."
shots-run: $(SIMAPP)
	@mkdir -p $(SHOTDIR)
	xcrun simctl boot "$(SIMDEV)" 2>/dev/null || true
	xcrun simctl install "$(SIMDEV)" $(SIMAPP)
	SIMCTL_CHILD_JF_STEPS="$(STEPS)" SIMCTL_CHILD_JF_OUT="$(SHOTDIR)" \
	  xcrun simctl launch --console-pty --terminate-running-process "$(SIMDEV)" org.jellyfin.atv3.shots | grep --line-buffered '\[shots\]'

# All README screenshots (docs/screenshots/*.jpg), from the public demo server.
screenshots: $(SIMAPP)
	xcrun simctl boot "$(SIMDEV)" 2>/dev/null || true
	xcrun simctl install "$(SIMDEV)" $(SIMAPP)
	tools/shots/run.sh "server $(DEMO); open; wait 5; shot signin; quit" signin
	tools/shots/run.sh "server $(DEMO); login demo; open; wait 9; shot home; key down; wait 2; key select; wait 6; shot library; key right; wait 1; key select; wait 6; shot movie; quit" movie
	tools/shots/run.sh "server $(DEMO); login demo; open; wait 9; key down; wait 1; key right right right; wait 1; key select; wait 6; key select; wait 8; key down; wait 4; shot series; quit" series

.PHONY: screenshots shots-run
