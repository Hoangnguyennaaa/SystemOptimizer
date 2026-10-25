#!/usr/bin/env bash
set -e

echo "[*] Step 1: Compiling RootHelper (C binary)..."
xcrun -sdk iphoneos clang -arch arm64 -miphoneos-version-min=15.0 \
    RootHelper/main.c -o RootHelper_bin

echo "[*] Step 2: Compiling SwiftUI App with swiftc (target iOS 15.0)..."
xcrun -sdk iphoneos swiftc \
    -target arm64-apple-ios15.0 \
    -sdk $(xcrun --sdk iphoneos --show-sdk-path) \
    -parse-as-library \
    -O \
    SystemOptimizer/App/SystemOptimizerApp.swift \
    SystemOptimizer/Models/DaemonItem.swift \
    SystemOptimizer/Services/DaemonManager.swift \
    SystemOptimizer/Views/ContentView.swift \
    -o SystemOptimizer_bin

echo "[*] Step 3: Creating App Bundle structure..."
rm -rf Payload SystemOptimizer.app
mkdir -p Payload/SystemOptimizer.app

cp SystemOptimizer_bin Payload/SystemOptimizer.app/SystemOptimizer
cp RootHelper_bin Payload/SystemOptimizer.app/RootHelper
cp Info.plist Payload/SystemOptimizer.app/Info.plist

chmod 755 Payload/SystemOptimizer.app/SystemOptimizer
chmod 755 Payload/SystemOptimizer.app/RootHelper

echo "[*] Step 4: Signing binaries with ldid..."
ldid -SEntitlements/app.plist Payload/SystemOptimizer.app/SystemOptimizer
ldid -SEntitlements/roothelper.plist Payload/SystemOptimizer.app/RootHelper

echo "[*] Step 5: Packaging into SystemOptimizer.ipa..."
zip -r9 SystemOptimizer.ipa Payload

echo "[*] Cleaning temporary files..."
rm -rf Payload RootHelper_bin SystemOptimizer_bin

echo "[+] Thành công! File SystemOptimizer.ipa đã được tạo."
