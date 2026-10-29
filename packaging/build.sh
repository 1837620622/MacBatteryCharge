#!/bin/bash
# 在 macOS 上跑测试、编出 arm64 与 Intel 两份，打成 PKG 和 DMG，最后检查图标和语言都真的在包里。只打包，不安装。
set -euo pipefail

cd "$(dirname "$0")/.."
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

VERSION="$(tr -d '[:space:]' < VERSION)"
ROOT="$(pwd)"
VOLUME_NAME="充电上限"
LANGS=(en zh-Hans zh-Hant)

rm -rf build dist
mkdir -p build dist

swift test

# 性能预算：超了就失败。
swift build -c release --product MacBatteryCharge
"$(swift build -c release --show-bin-path)/MacBatteryCharge" --bench

# 图标：1024 的源图缩成 Apple 要的 10 个尺寸，再由 iconutil 打成 icns。
ICONSET="$ROOT/build/AppIcon.iconset"
mkdir -p "$ICONSET"
for base in 16 32 128 256 512; do
    retina=$((base * 2))
    sips -z "$base" "$base" resources/AppIcon.png --out "$ICONSET/icon_${base}x${base}.png" >/dev/null
    sips -z "$retina" "$retina" resources/AppIcon.png --out "$ICONSET/icon_${base}x${base}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/build/AppIcon.icns"

# 安装器的资源：左边的图和每种语言的欢迎页、结束页。没有对应语言时用英文。
INSTALLER="$ROOT/build/installer"
rm -rf "$INSTALLER"
mkdir -p "$INSTALLER"
sips -z 128 128 resources/AppIcon.png --out "$INSTALLER/background.png" >/dev/null
sips -z 288 288 resources/AppIcon.png --out "$INSTALLER/icon-288.png" >/dev/null
for lang in "${LANGS[@]}"; do
    mkdir -p "$INSTALLER/$lang.lproj"
    cp packaging/installer/"$lang".lproj/*.html "$INSTALLER/$lang.lproj/"
done
cp packaging/installer/en.lproj/Welcome.html packaging/installer/en.lproj/Conclusion.html "$INSTALLER/"
# 页面里的图标直接嵌进 HTML，不依赖安装器怎么拷贝附带的图片。
for page in "$INSTALLER"/*.html "$INSTALLER"/*.lproj/*.html; do
    python3 packaging/embed-icon.py "$page" "$INSTALLER/icon-288.png"
done
rm -f "$INSTALLER/icon-288.png"

# DMG 卷图标要求根目录的 Finder 信息里有「自定义图标」这一位（和 SetFile -a C 写的是同一位）。
# FinderInfo 第 8、9 个字节的 0x0400 就是它。
custom_icon_flag() {
    python3 -c 'import sys; sys.stdout.write(" ".join(f"{b:02x}" for b in bytes([0]*8 + [4, 0] + [0]*22)))'
}

detach_with_retry() {
    local target="$1"
    for _ in 1 2 3 4 5; do
        if hdiutil detach -quiet "$target" 2>/dev/null; then return 0; fi
        sleep 2
    done
    hdiutil detach -quiet -force "$target"
}

build_app() {
    local arch="$1"
    local label="$2"
    local triple="${arch}-apple-macosx13.0"
    local app="$ROOT/build/$label/MacBatteryCharge.app"
    local work="$ROOT/build/$label/work"

    swift build -c release --triple "$triple"
    local bin
    bin="$(swift build -c release --triple "$triple" --show-bin-path)"

    rm -rf "$ROOT/build/$label"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers" "$work"
    sed "s/__VERSION__/$VERSION/g" packaging/Info.plist > "$app/Contents/Info.plist"
    cp "$ROOT/build/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
    # 各语言的应用名：访达和「关于」里显示的名字跟着系统语言走。
    for lang in "${LANGS[@]}"; do
        mkdir -p "$app/Contents/Resources/$lang.lproj"
        cp "packaging/strings/$lang.lproj/InfoPlist.strings" "$app/Contents/Resources/$lang.lproj/InfoPlist.strings"
        plutil -convert binary1 "$app/Contents/Resources/$lang.lproj/InfoPlist.strings"
    done
    cp "$bin/MacBatteryCharge" "$app/Contents/MacOS/MacBatteryCharge"
    cp "$bin/MacBatteryChargeHelper" "$app/Contents/Helpers/MacBatteryChargeHelper"
    plutil -lint "$app/Contents/Info.plist" >/dev/null

    local got
    for binary in "$app/Contents/MacOS/MacBatteryCharge" "$app/Contents/Helpers/MacBatteryChargeHelper"; do
        got="$(lipo -archs "$binary")"
        if [[ "$got" != "$arch" ]]; then
            echo "架构不符：$binary 要 ${arch}，实际 $got"
            exit 1
        fi
    done
    # 里面的帮手先签，再签整个 app。
    codesign --force --sign - --identifier com.macbatterycharge.helper "$app/Contents/Helpers/MacBatteryChargeHelper"
    codesign --force --sign - "$app"

    # PKG：组件包负责把 app 放进 /Applications（不允许“搬家”，否则系统会装到别处找到的旧副本上），
    # 再用分发包包一层，安装器里才有欢迎页、左边的应用图标和架构限制。
    local stage="$work/stage"
    mkdir -p "$stage"
    cp -R "$app" "$stage/"
    local components="$work/components.plist"
    pkgbuild --analyze --root "$stage" "$components" >/dev/null
    plutil -replace 0.BundleIsRelocatable -bool NO "$components"
    pkgbuild \
        --root "$stage" \
        --component-plist "$components" \
        --scripts "$ROOT/packaging/scripts" \
        --install-location /Applications \
        --identifier com.macbatterycharge.pkg \
        --version "$VERSION" \
        "$work/MacBatteryCharge-component.pkg"

    local host_arch="x86_64"
    [[ "$arch" == arm64 ]] && host_arch="arm64"
    sed -e "s/__VERSION__/$VERSION/g" -e "s/__ARCH__/$host_arch/g" packaging/distribution.xml > "$work/distribution.xml"
    xmllint --noout "$work/distribution.xml"
    local resources="$work/resources"
    mkdir -p "$resources"
    cp -R "$INSTALLER/." "$resources/"
    productbuild \
        --distribution "$work/distribution.xml" \
        --package-path "$work" \
        --resources "$resources" \
        "$ROOT/dist/MacBatteryCharge-${VERSION}-${label}.pkg"

    # DMG：app、「应用程序」的快捷方式和卷图标。先打成可写的，设好卷图标，再压缩成只读的。
    local dmgstage="$work/dmg"
    mkdir -p "$dmgstage"
    cp -R "$app" "$dmgstage/"
    ln -s /Applications "$dmgstage/Applications"
    cp "$ROOT/build/AppIcon.icns" "$dmgstage/.VolumeIcon.icns"
    local rw="$work/rw.dmg"
    hdiutil create -quiet -srcfolder "$dmgstage" -volname "$VOLUME_NAME" -fs HFS+ -format UDRW -ov "$rw"
    local mnt="$work/mnt"
    mkdir -p "$mnt"
    hdiutil attach -quiet -readwrite -noverify -noautoopen -nobrowse -mountpoint "$mnt" "$rw"
    xattr -wx com.apple.FinderInfo "$(custom_icon_flag)" "$mnt"
    sync
    detach_with_retry "$mnt"
    hdiutil convert -quiet "$rw" -format UDZO -imagekey zlib-level=9 -ov \
        -o "$ROOT/dist/MacBatteryCharge-${VERSION}-${label}.dmg"

    rm -rf "$work"
    echo "packed $label"
}

build_app arm64 arm64
build_app x86_64 intel

# 检查包里真的有图标、语言和安装器页面；缺了就失败，不发出去。
bash packaging/verify.sh dist

echo "dist:"
ls -lh dist
