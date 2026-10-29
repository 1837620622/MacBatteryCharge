#!/bin/bash
# 在 macOS 上编译测试、打出 arm64 与 Intel 的 PKG 和 DMG。不安装。
set -euo pipefail

cd "$(dirname "$0")/.."
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

VERSION="$(tr -d '[:space:]' < VERSION)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ROOT="$(pwd)"

rm -rf build dist
mkdir -p build dist

clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
    -isysroot "$SDK" -mmacosx-version-min=14.0 \
    -framework Foundation \
    src/Schedule.m src/ScheduleTest.m src/SystemPower.m src/Command.m src/LoginItem.m src/UpdateCheck.m \
    -o build/schedule_test
./build/schedule_test

ICONSET="$ROOT/build/AppIcon.iconset"
mkdir -p "$ICONSET"
make_icon() {
    local base="$1"
    local retina=$((base * 2))
    sips -z "$base" "$base" resources/AppIcon.png --out "$ICONSET/icon_${base}x${base}.png" >/dev/null
    sips -z "$retina" "$retina" resources/AppIcon.png --out "$ICONSET/icon_${base}x${base}@2x.png" >/dev/null
}
for base in 16 32 128 256 512; do
    make_icon "$base"
done
iconutil -c icns "$ICONSET" -o "$ROOT/build/AppIcon.icns"

build_app() {
    local clang_arch="$1"
    local target="$2"
    local label="$3"
    local app="$ROOT/build/$label/MacBatteryCharge.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    sed "s/__VERSION__/$VERSION/g" packaging/Info.plist > "$app/Contents/Info.plist"
    cp "$ROOT/build/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
    clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
        -target "$target" -isysroot "$SDK" -mmacosx-version-min=14.0 \
        -framework Cocoa \
        src/main.m src/AppController.m src/Schedule.m src/Command.m src/SystemPower.m \
        src/ChargeClient.m src/LoginItem.m src/UpdateCheck.m src/Settings.m \
        -o "$app/Contents/MacOS/MacBatteryCharge"
    local got
    got="$(lipo -archs "$app/Contents/MacOS/MacBatteryCharge")"
    if [[ "$got" != "$clang_arch" ]]; then
        echo "架构不符：要 $clang_arch，实际 $got"
        exit 1
    fi
    codesign --force --sign - "$app"

    local stage
    stage="$(mktemp -d)"
    cp -R "$app" "$stage/"
    pkgbuild \
        --root "$stage" \
        --install-location /Applications \
        --identifier com.macbatterycharge.pkg \
        --version "$VERSION" \
        "$ROOT/dist/MacBatteryCharge-${VERSION}-${label}.pkg"
    rm -rf "$stage"

    local dmgstage
    dmgstage="$(mktemp -d)"
    cp -R "$app" "$dmgstage/"
    ln -s /Applications "$dmgstage/Applications"
    hdiutil create \
        -volname "充电上限" \
        -srcfolder "$dmgstage" \
        -ov \
        -format UDZO \
        "$ROOT/dist/MacBatteryCharge-${VERSION}-${label}.dmg" >/dev/null
    rm -rf "$dmgstage"
    echo "packed $label"
}

build_app arm64 arm64-apple-macos14.0 arm64
build_app x86_64 x86_64-apple-macos14.0 intel

echo "dist:"
ls -lh dist
