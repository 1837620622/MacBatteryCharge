#!/bin/bash
# 检查 dist 里的 PKG 和 DMG：图标、欢迎页、三种语言、架构限制都在。缺了就失败，不发版。
# 用法：bash packaging/verify.sh dist
set -euo pipefail

dist="${1:-dist}"
fail() {
    echo "✗ $*" >&2
    exit 1
}

shopt -s nullglob
packages=("$dist"/*.pkg)
images=("$dist"/*.dmg)
[[ ${#packages[@]} -gt 0 ]] || fail "dist 里没有 PKG"
[[ ${#images[@]} -gt 0 ]] || fail "dist 里没有 DMG"

for pkg in "${packages[@]}"; do
    name="$(basename "$pkg")"
    tmp="$(mktemp -d)"
    pkgutil --expand-full "$pkg" "$tmp/x" >/dev/null

    dist_xml="$tmp/x/Distribution"
    [[ -f "$dist_xml" ]] || fail "${name}：不是分发包，没有安装器页面"
    grep -q 'background.png' "$dist_xml" || fail "${name}：安装器没有左边的图"
    grep -q 'alignment="bottomleft"' "$dist_xml" || fail "${name}：左边的图没放在左下角，会压住步骤列表"
    grep -q 'Welcome.html' "$dist_xml" || fail "${name}：安装器没有欢迎页"
    grep -q 'rootVolumeOnly' "$dist_xml" || fail "${name}：没有限制装在系统盘"
    grep -q 'hostArchitectures' "$dist_xml" || fail "${name}：没有写架构限制"
    # 资源目录每次都列出来，CI 日志里能看到包里实际有什么。
    show_resources() { find "$tmp/x/Resources" | sort; }
    show_resources
    # 顶层和每个语言目录都要有欢迎页、结束页，还有欢迎页引用的 background.png。
    for file in Welcome.html Conclusion.html background.png \
        en.lproj/Welcome.html en.lproj/Conclusion.html en.lproj/background.png \
        zh_CN.lproj/Welcome.html zh_CN.lproj/Conclusion.html zh_CN.lproj/background.png \
        zh_TW.lproj/Welcome.html zh_TW.lproj/Conclusion.html zh_TW.lproj/background.png; do
        [[ -f "$tmp/x/Resources/$file" ]] || { show_resources; fail "${name}：缺 Resources/$file"; }
    done
    for page in Welcome.html en.lproj/Welcome.html zh_CN.lproj/Welcome.html zh_TW.lproj/Welcome.html; do
        grep -q 'src="background.png"' "$tmp/x/Resources/$page" || { show_resources; fail "${name}：$page 没有引用图标"; }
    done
    grep -q '充电上限' "$tmp/x/Resources/zh_CN.lproj/Welcome.html" || fail "${name}：中文欢迎页不是中文"
    grep -q 'Charge Limit' "$tmp/x/Resources/en.lproj/Welcome.html" || fail "${name}：英文欢迎页不是英文"

    app_info="$(find "$tmp/x" -path '*/MacBatteryCharge.app/Contents/Info.plist' -print -quit)"
    [[ -n "$app_info" ]] || fail "${name}：包里没有 MacBatteryCharge.app"
    app="$(dirname "$(dirname "$app_info")")"
    [[ -f "$app/Contents/Resources/AppIcon.icns" ]] || fail "${name}：应用里没有 AppIcon.icns"
    for lang in en zh-Hans zh-Hant; do
        [[ -f "$app/Contents/Resources/$lang.lproj/InfoPlist.strings" ]] || fail "${name}：应用缺 $lang 的名字"
    done
    echo "✓ ${name}：安装器页面、应用图标和三种语言都在"
    rm -rf "$tmp"
done

for image in "${images[@]}"; do
    name="$(basename "$image")"
    mnt="$(mktemp -d)"
    hdiutil attach -quiet -readonly -noverify -noautoopen -nobrowse -mountpoint "$mnt" "$image"
    # 挂好之后一律卸掉，哪怕后面的检查失败。
    check_image() {
        [[ -f "$mnt/.VolumeIcon.icns" ]] || { echo "✗ ${name}：卷图标不在"; return 1; }
        local flags
        flags="$(xattr -px com.apple.FinderInfo "$mnt" 2>/dev/null | tr -d ' \n')"
        # 第 8、9 个字节（十六进制第 16 到 19 位）里的 0400 就是「自定义图标」。
        [[ "${flags:16:4}" == "0400" ]] || { echo "✗ ${name}：卷的自定义图标标记没设上（FinderInfo=${flags}）"; return 1; }
        [[ -f "$mnt/MacBatteryCharge.app/Contents/Resources/AppIcon.icns" ]] || { echo "✗ ${name}：DMG 里的应用没有图标"; return 1; }
        [[ -L "$mnt/Applications" ]] || { echo "✗ ${name}：没有「应用程序」快捷方式"; return 1; }
        return 0
    }
    status=0
    check_image || status=1
    hdiutil detach -quiet "$mnt" 2>/dev/null || hdiutil detach -quiet -force "$mnt"
    rmdir "$mnt" 2>/dev/null || true
    [[ $status -eq 0 ]] || fail "$name 检查没过"
    echo "✓ ${name}：卷图标、应用图标和快捷方式都在"
done
