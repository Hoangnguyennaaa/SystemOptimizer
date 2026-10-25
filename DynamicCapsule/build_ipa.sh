#!/usr/bin/env bash
set -ex

echo "[*] Step 1: Getting iOS SDK Path..."
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
echo "SDK: $SDK_PATH"

echo "[*] Step 2: Compiling DynamicCapsule Swift App..."
xcrun -sdk iphoneos swiftc \
    -target arm64-apple-ios15.0 \
    -sdk "$SDK_PATH" \
    -module-name DynamicCapsule \
    -emit-executable \
    -parse-as-library \
    -framework SwiftUI \
    -framework UIKit \
    -framework Foundation \
    -framework Network \
    -O \
    App/DynamicCapsuleApp.swift \
    Managers/SystemMonitor.swift \
    Managers/OverlayWindowManager.swift \
    Views/IslandCapsuleView.swift \
    Views/SettingsView.swift \
    -o DynamicCapsule_bin

echo "[*] Step 3: Preparing Payload Bundle..."
rm -rf Payload DynamicCapsule.app
mkdir -p Payload/DynamicCapsule.app

cp DynamicCapsule_bin Payload/DynamicCapsule.app/DynamicCapsule
cp Info.plist Payload/DynamicCapsule.app/Info.plist
chmod 755 Payload/DynamicCapsule.app/DynamicCapsule

echo "[*] Step 4: Signing with TrollStore/Jailbreak Entitlements..."
ldid -SEntitlements.plist Payload/DynamicCapsule.app/DynamicCapsule

echo "[*] Step 5: Packaging into DynamicCapsule.ipa..."
zip -r9 DynamicCapsule.ipa Payload

rm -rf Payload DynamicCapsule_bin
echo "[+] Hoàn tất! File DynamicCapsule.ipa đã sẵn sàng."
