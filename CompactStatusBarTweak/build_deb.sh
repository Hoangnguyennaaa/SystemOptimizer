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

echo "[*] Step 2: Signing dylib with ldid..."
ldid -S CompactStatusBar.dylib

echo "[*] Step 3: Preparing Rootless package structure..."
rm -rf pkg_root
mkdir -p pkg_root/var/jb/Library/MobileSubstrate/DynamicLibraries
mkdir -p pkg_root/var/jb/Library/PreferenceLoader/Preferences
mkdir -p pkg_root/DEBIAN

# Tweak dylib + plist filter (SpringBoard & MobileSubstrate)
cp CompactStatusBar.dylib pkg_root/var/jb/Library/MobileSubstrate/DynamicLibraries/
cp CompactStatusBarTweak.plist pkg_root/var/jb/Library/MobileSubstrate/DynamicLibraries/CompactStatusBar.plist

# Direct native PreferenceLoader plist with all specifiers
cp Preferences/CompactStatusBar.plist pkg_root/var/jb/Library/PreferenceLoader/Preferences/

# Debian control
cp control pkg_root/DEBIAN/control

# Set exact Unix permissions
chmod -R 0755 pkg_root
chmod 0644 pkg_root/DEBIAN/control

echo "[*] Step 4: Packaging with dpkg-deb..."
dpkg-deb -Zgzip --root-owner-group -b pkg_root CompactStatusBar_rootless.deb

cp CompactStatusBar_rootless.deb ../CompactStatusBar_rootless.deb
rm -rf pkg_root CompactStatusBar.dylib
echo "[+] Hoàn tất! File CompactStatusBar_rootless.deb đã được tạo thành công."
