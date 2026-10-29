#!/bin/bash
# Fallback builder when public CI signing fails. Run on your own Mac.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"
[[ "$(/usr/bin/uname -s)" == Darwin ]] || { echo '此步骤需要 Mac。'; exit 1; }
[[ -x /usr/bin/shortcuts ]] || { echo '找不到快捷指令命令。'; exit 1; }
PYTHON="$(command -v python3 || :)"
[[ -n "$PYTHON" ]] || { echo '未找到 Python 3；请先安装 Python 3。'; exit 1; }
mkdir -p build/unsigned build/signed
"$PYTHON" tools/charge_shortcuts.py --output build/unsigned
for name in 白天充电上限80 晚间充电上限100; do
  src="build/unsigned/${name}.unsigned.shortcut"
  dest="build/signed/${name}.shortcut"
  /usr/bin/shortcuts sign --mode people-who-know-me --input "$src" --output "$dest"
  [[ -s "$dest" ]] || { echo "签名失败：$name" >&2; exit 1; }
done
"$PYTHON" tools/package_release.py --repo "$ROOT" --signed build/signed --out dist
printf '\n本机打包完成：%s/dist/MacBatteryCharge-macOS-Installer.zip\n' "$ROOT"
echo '本机签名模式为 people-who-know-me，适合在本人 Mac 导入，不适合直接公开分发。'
