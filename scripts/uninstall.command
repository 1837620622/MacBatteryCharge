#!/bin/bash
set -euo pipefail
LABEL='com.macbatterycharge.schedule'
UID_NUM="$(/usr/bin/id -u)"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP_DIR="$HOME/Library/Application Support/MacBatteryCharge"
echo '卸载只删除定时任务和本工具的运行脚本。'
echo '不会删除你快捷指令应用中的两条快捷指令，也不会改变当前充电上限。'
printf '确认卸载？输入 YES：'
IFS= read -r confirm || exit 0
[[ "$confirm" == YES ]] || { echo '已取消。'; exit 0; }
/bin/launchctl bootout "gui/$UID_NUM/$LABEL" >/dev/null 2>&1 || true
if [[ -f "$PLIST" && ! -L "$PLIST" ]]; then /bin/rm -f "$PLIST"; fi
if [[ -d "$APP_DIR" && ! -L "$APP_DIR" ]]; then
  /bin/rm -f "$APP_DIR/charge_sync.sh" "$APP_DIR/profile.sh"
  /bin/rmdir "$APP_DIR" 2>/dev/null || true
fi
echo '定时任务已卸载。日志保留在 ~/Library/Logs/MacBatteryCharge。'
echo '如需恢复 100%，可手动运行「晚间充电上限100」。'
