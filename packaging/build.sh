#!/bin/bash
# 在 macOS 上跑测试、编出 arm64 与 Intel 两份，再打 PKG 和 DMG。只打包，不安装。
set -euo pipefail

cd "$(dirname "$0")/.."
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

VERSION="$(tr -d '[:space:]' < VERSION)"
ROOT="$(pwd)"

rm -rf build dist
mkdir -p build dist

swift test

# 性能预算：超了就失败。
swift build -c release --product MacBatteryCharge
"$(swift build -c release --show-bin-path)/MacBatteryCharge" --bench

ICONSET="$ROOT/build/AppIcon.iconset"
mkdir -p "$ICONSET"
for base in 16 32 128 256 512; do
    retina=$((base * 2))
    sips -z "$base" "$base" resources/AppIcon.png --out "$ICONSET/icon_${base}x${base}.png" >/dev/null
    sips -z "$retina" "$retina" resources/AppIcon.png --out "$ICONSET/icon_${base}x${base}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/build/AppIcon.icns"

build_app() {
    local arch="$1"
    local label="$2"
    local triple="${arch}-apple-macosx13.0"
    local app="$ROOT/build/$label/MacBatteryCharge.app"

    swift build -c release --triple "$triple"
    local bin
    bin="$(swift build -c release --triple "$triple" --show-bin-path)"

    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers"
    sed "s/__VERSION__/$VERSION/g" packaging/Info.plist > "$app/Contents/Info.plist"
    cp "$ROOT/build/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
    cp "$bin/MacBatteryCharge" "$app/Contents/MacOS/MacBatteryCharge"
    cp "$bin/MacBatteryChargeHelper" "$app/Contents/Helpers/MacBatteryChargeHelper"
    plutil -lint "$app/Contents/Info.plist" >/dev/null

    local got
    for binary in "$app/Contents/MacOS/MacBatteryCharge" "$app/Contents/Helpers/MacBatteryChargeHelper"; do
        got="$(lipo -archs "$binary")"
        if [[ "$got" != "$arch" ]]; then
            echo "架构不符：$binary 要 $arch，实际 $got"
            exit 1
        fi
    done
    # 里面的帮手先签，再签整个 app。
    codesign --force --sign - --identifier com.macbatterycharge.helper "$app/Contents/Helpers/MacBatteryChargeHelper"
    codesign --force --sign - "$app"

    # PKG 固定装到 /Applications。不允许“搬家”，否则系统会装到别处找到的旧副本上。
    local stage
    stage="$(mktemp -d)"
    cp -R "$app" "$stage/"
    local components="$ROOT/build/$label/components.plist"
    pkgbuild --analyze --root "$stage" "$components" >/dev/null
    plutil -replace 0.BundleIsRelocatable -bool NO "$components"
    pkgbuild \
        --root "$stage" \
        --component-plist "$components" \
        --scripts "$ROOT/packaging/scripts" \
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

build_app arm64 arm64
build_app x86_64 intel

echo "dist:"
ls -lh dist
