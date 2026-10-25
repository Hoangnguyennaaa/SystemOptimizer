#!/usr/bin/env bash
set -ex

echo "[*] Step 1: Getting iOS SDK Path..."
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
echo "SDK: $SDK_PATH"

echo "[*] Step 2: Compiling CompactStatusBar Swift App..."
xcrun -sdk iphoneos swiftc \
    -target arm64-apple-ios15.0 \
    -sdk "$SDK_PATH" \
    -module-name CompactStatusBar \
    -emit-executable \
    -parse-as-library \
    -framework SwiftUI \
    -framework UIKit \
    -framework Foundation \
    -framework Network \
    -framework CoreTelephony \
    -O \
    App/CompactStatusBarApp.swift \
    Managers/SystemStatusManager.swift \
    Managers/StatusBarOverlayManager.swift \
    Views/CombinedStatusGaugeView.swift \
    Views/StatusHUDPopupView.swift \
    Views/SettingsView.swift \
    -o CompactStatusBar_bin

echo "[*] Step 3: Preparing Payload Bundle..."
rm -rf Payload CompactStatusBar.app
mkdir -p Payload/CompactStatusBar.app

cp CompactStatusBar_bin Payload/CompactStatusBar.app/CompactStatusBar
cp Info.plist Payload/CompactStatusBar.app/Info.plist
chmod 755 Payload/CompactStatusBar.app/CompactStatusBar

echo "[*] Step 4: Signing with TrollStore/Jailbreak Entitlements..."
ldid -SEntitlements.plist Payload/CompactStatusBar.app/CompactStatusBar

echo "[*] Step 5: Packaging into CompactStatusBar.ipa..."
zip -r9 CompactStatusBar.ipa Payload

rm -rf Payload CompactStatusBar_bin
echo "[+] Hoàn tất! File CompactStatusBar.ipa đã sẵn sàng."
