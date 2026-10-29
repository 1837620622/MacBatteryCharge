#!/bin/bash
set -euo pipefail
LABEL='com.macbatterycharge.schedule'
UID_NUM="$(/usr/bin/id -u)"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/MacBatteryCharge"
printf '== MacBatteryCharge 状态 ==\n'
if [[ -f "$PLIST" ]]; then
  /usr/bin/plutil -lint "$PLIST" || true
  /bin/launchctl print "gui/$UID_NUM/$LABEL" 2>&1 | /usr/bin/head -35 || true
else
  echo '未安装 LaunchAgent。'
fi
printf '\n== 快捷指令 ==\n'
/usr/bin/shortcuts list 2>/dev/null | /usr/bin/grep -Fx -e '白天充电上限80' -e '晚间充电上限100' || echo '未找到全部快捷指令。'
printf '\n== 近期运行日志 ==\n'
for log in "$LOG_DIR/output.log" "$LOG_DIR/error.log"; do
  if [[ -f "$log" ]]; then echo "[$log]"; /usr/bin/tail -20 "$log"; fi
done
printf '\n状态说明：日志成功 ≠ 已验证电池实际充电上限；请到系统设置 → 电池确认。\n'
