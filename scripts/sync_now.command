#!/bin/bash
set -euo pipefail
SCRIPT="$HOME/Library/Application Support/MacBatteryCharge/charge_sync.sh"
[[ -f "$SCRIPT" ]] || { echo '请先安装。' >&2; exit 1; }
/bin/bash "$SCRIPT"
echo '请打开系统设置 → 电池，查看充电上限是否已更新。'
