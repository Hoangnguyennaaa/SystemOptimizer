#!/usr/bin/env bash
set -ex

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)

echo "[*] Step 1: Compiling CompactStatusBar.dylib..."
xcrun -sdk iphoneos clang -arch arm64 \
    -target arm64-apple-ios15.0 \
    -miphoneos-version-min=15.0 \
    -dynamiclib \
    -isysroot "$SDK_PATH" \
    -framework UIKit \
    -framework Foundation \
    -framework CoreGraphics \
    -framework QuartzCore \
    -fobjc-arc \
    Tweak.m -o CompactStatusBar.dylib

echo "[*] Step 2: Compiling CompactStatusBarPrefs bundle..."
xcrun -sdk iphoneos clang -arch arm64 \
    -target arm64-apple-ios15.0 \
    -miphoneos-version-min=15.0 \
    -bundle \
    -isysroot "$SDK_PATH" \
    -framework UIKit \
    -framework Foundation \
    -undefined dynamic_lookup \
    -fobjc-arc \
    Preferences/CompactStatusBarPrefsListController.m -o CompactStatusBarPrefs

echo "[*] Step 3: Signing with ldid..."
ldid -S CompactStatusBar.dylib
ldid -S CompactStatusBarPrefs

echo "[*] Step 4: Preparing Rootless package structure..."
rm -rf pkg_root
mkdir -p pkg_root/var/jb/usr/lib/TweakInject
mkdir -p pkg_root/var/jb/Library/PreferenceLoader/Preferences
mkdir -p pkg_root/var/jb/Library/PreferenceBundles/CompactStatusBarPrefs.bundle
mkdir -p pkg_root/DEBIAN

# Tweak dylib + plist filter
cp CompactStatusBar.dylib pkg_root/var/jb/usr/lib/TweakInject/
cp CompactStatusBarTweak.plist pkg_root/var/jb/usr/lib/TweakInject/CompactStatusBar.plist

# PreferenceLoader entry
cp Preferences/CompactStatusBar.plist pkg_root/var/jb/Library/PreferenceLoader/Preferences/

# PreferenceBundle
cp CompactStatusBarPrefs pkg_root/var/jb/Library/PreferenceBundles/CompactStatusBarPrefs.bundle/
cp Preferences/Info.plist pkg_root/var/jb/Library/PreferenceBundles/CompactStatusBarPrefs.bundle/
cp Preferences/Root.plist pkg_root/var/jb/Library/PreferenceBundles/CompactStatusBarPrefs.bundle/

# Debian control
cp control pkg_root/DEBIAN/control

# Set exact Unix permissions required by dpkg
chmod -R 0755 pkg_root
chmod 0644 pkg_root/DEBIAN/control

echo "[*] Step 5: Packaging with official dpkg-deb tool..."
dpkg-deb -Zgzip --root-owner-group -b pkg_root CompactStatusBar_rootless.deb

cp CompactStatusBar_rootless.deb ../CompactStatusBar_rootless.deb
rm -rf pkg_root CompactStatusBar.dylib CompactStatusBarPrefs
echo "[+] Hoàn tất! File CompactStatusBar_rootless.deb chuẩn Debian đã được tạo."
