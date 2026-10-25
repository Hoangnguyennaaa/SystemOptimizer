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

echo "[*] Step 2: Signing with ldid..."
ldid -S CompactStatusBar.dylib

echo "[*] Step 3: Preparing Rootless package structure..."
rm -rf pkg_root
mkdir -p pkg_root/var/jb/usr/lib/TweakInject
mkdir -p pkg_root/DEBIAN

cp CompactStatusBar.dylib pkg_root/var/jb/usr/lib/TweakInject/
cp CompactStatusBarTweak.plist pkg_root/var/jb/usr/lib/TweakInject/CompactStatusBar.plist
cp control pkg_root/DEBIAN/control

echo "[*] Step 4: Packaging .deb..."
python3 - << 'EOF'
import tarfile, os, io

def make_deb():
    deb_binary = b"2.0\n"
    
    ctrl_buf = io.BytesIO()
    with tarfile.open(fileobj=ctrl_buf, mode="w:gz") as tar:
        tar.add("pkg_root/DEBIAN/control", arcname="./control")
    ctrl_bytes = ctrl_buf.getvalue()
    
    data_buf = io.BytesIO()
    with tarfile.open(fileobj=data_buf, mode="w:gz") as tar:
        for root, dirs, files in os.walk("pkg_root/var"):
            for f in files:
                p = os.path.join(root, f)
                rel = os.path.relpath(p, "pkg_root")
                tar.add(p, arcname="./" + rel.replace("\\", "/"))
    data_bytes = data_buf.getvalue()

    with open("CompactStatusBar_rootless.deb", "wb") as deb:
        deb.write(b"!<arch>\n")
        
        def write_member(name, content):
            header = f"{name:<16}{'0':<12}{'0':<6}{'0':<6}{'100644':<8}{len(content):<10}`\n".encode("ascii")
            deb.write(header)
            deb.write(content)
            if len(content) % 2 == 1:
                deb.write(b"\n")
                
        write_member("debian-binary", deb_binary)
        write_member("control.tar.gz", ctrl_bytes)
        write_member("data.tar.gz", data_bytes)
    print("Created CompactStatusBar_rootless.deb successfully!")

make_deb()
EOF

cp CompactStatusBar_rootless.deb ../CompactStatusBar_rootless.deb
ls -lh CompactStatusBar_rootless.deb
rm -rf pkg_root CompactStatusBar.dylib
echo "[+] Hoàn tất! File CompactStatusBar_rootless.deb đã được tạo."
