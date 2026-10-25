#!/usr/bin/env bash
set -ex

echo "[*] Step 0: Checking SDK..."
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
echo "SDK Path: $SDK_PATH"

echo "[*] Step 1: Compiling RootHelper..."
xcrun -sdk iphoneos clang -arch arm64 \
    -isysroot "$SDK_PATH" \
    -miphoneos-version-min=15.0 \
    RootHelper/main.c -o RootHelper_bin

echo "[*] Step 2: Compiling SwiftUI App with swiftc..."
xcrun -sdk iphoneos swiftc \
    -target arm64-apple-ios15.0 \
    -sdk "$SDK_PATH" \
    -module-name SystemOptimizer \
    -emit-executable \
    -parse-as-library \
    -framework SwiftUI \
    -framework UIKit \
    -framework Foundation \
    -O \
    SystemOptimizer/App/SystemOptimizerApp.swift \
    SystemOptimizer/Models/DaemonItem.swift \
    SystemOptimizer/Services/DaemonManager.swift \
    SystemOptimizer/Views/ContentView.swift \
    -o SystemOptimizer_bin

echo "[*] Step 3: Preparing App Bundle..."
rm -rf Payload SystemOptimizer.app
mkdir -p Payload/SystemOptimizer.app

cp SystemOptimizer_bin Payload/SystemOptimizer.app/SystemOptimizer
cp RootHelper_bin Payload/SystemOptimizer.app/RootHelper
cp Info.plist Payload/SystemOptimizer.app/Info.plist

chmod 755 Payload/SystemOptimizer.app/SystemOptimizer
chmod 755 Payload/SystemOptimizer.app/RootHelper

echo "[*] Step 4: Signing with ldid..."
ldid -SEntitlements/app.plist Payload/SystemOptimizer.app/SystemOptimizer
ldid -SEntitlements/roothelper.plist Payload/SystemOptimizer.app/RootHelper

echo "[*] Step 5: Packaging into IPA..."
zip -r9 SystemOptimizer.ipa Payload

echo "[+] Done: SystemOptimizer.ipa successfully created!"
