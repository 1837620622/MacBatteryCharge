#!/bin/bash
# One-time installer: import two Apple-signed shortcuts, then install LaunchAgent.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
LABEL='com.macbatterycharge.schedule'
APP_DIR="$HOME/Library/Application Support/MacBatteryCharge"
AGENT_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs/MacBatteryCharge"
PLIST="$AGENT_DIR/${LABEL}.plist"
UID_NUM="$(/usr/bin/id -u)"

fail() { echo "安装失败：$*" >&2; exit 1; }
info() { printf '\n%s\n' "$*"; }
contains_name() {
  /usr/bin/shortcuts list 2>/dev/null | /usr/bin/grep -Fxq "$1"
}
# Escape personal paths before embedding them in the launchd XML plist.
xml_escape() {
  local v="$1"
  v="${v//&/\&amp;}"; v="${v//</\&lt;}"; v="${v//>/\&gt;}"
  printf '%s' "$v"
}

[[ "$(/usr/bin/uname -s)" == Darwin ]] || fail '请在 Mac 上执行。'
[[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || :)" == 1 ]] || fail '仅适用于 Apple 芯片 Mac。'
[[ -x /usr/bin/shortcuts ]] || fail '找不到 Apple 快捷指令命令。'
ver="$(/usr/bin/sw_vers -productVersion)"
major="${ver%%.*}"; remainder="${ver#*.}"; minor="${remainder%%.*}"
[[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || fail "无法解析 macOS 版本：$ver"
(( major > 26 || (major == 26 && minor >= 4) )) || fail "需要 macOS 26.4 或更高版本，当前：$ver"
[[ -d "$HERE/shortcuts" ]] || fail '缺少 shortcuts 文件夹。请完整解压 ZIP。'
[[ -f "$HERE/scripts/charge_sync.sh" && -f "$HERE/scripts/profile.sh" ]] || fail '缺少脚本。请完整解压 ZIP。'
info "检测通过：macOS $ver / Apple 芯片。"
echo '本工具只更改系统原生充电上限。不主动放电，也不保证电池能在指定时刻充满。'
echo '请先在快捷指令应用内完成两条快捷指令的导入（这是 Apple 安全确认，不能自动跳过）。'

for name in 白天充电上限80 晚间充电上限100; do
  if contains_name "$name"; then
    info "已存在：$name"
  else
    file="$HERE/shortcuts/$name.shortcut"
    [[ -s "$file" ]] || fail "缺少已签名的 $name.shortcut；不能用未签名文件代替。"
    info "正在打开导入界面：$name"
    /usr/bin/open -a Shortcuts "$file" || fail "无法打开 $name；请检查是否已完成 Apple 签名。"
    echo "在快捷指令应用中点击“添加快捷指令”，并确认里面是“将充电上限设为”。"
    printf '完成后回到这里按回车继续...'
    IFS= read -r _ || fail '未完成导入。'
    contains_name "$name" || fail "仍未发现 $name。若显示未知操作，请不要安装定时任务。"
  fi
done

info '两条快捷指令已在本机快捷指令列表中发现。'
[[ ! -L "$APP_DIR" && ! -L "$AGENT_DIR" && ! -L "$LOG_DIR" && ! -L "$PLIST" ]] || fail '检测到非预期符号链接，已中止以保护已有文件。'
/bin/mkdir -p "$APP_DIR" "$AGENT_DIR" "$LOG_DIR"
/bin/cp "$HERE/scripts/charge_sync.sh" "$APP_DIR/charge_sync.sh"
/bin/cp "$HERE/scripts/profile.sh" "$APP_DIR/profile.sh"
/bin/chmod 700 "$APP_DIR/charge_sync.sh" "$APP_DIR/profile.sh"

app_script="$(xml_escape "$APP_DIR/charge_sync.sh")"
log_out="$(xml_escape "$LOG_DIR/output.log")"
log_err="$(xml_escape "$LOG_DIR/error.log")"
tmp="$AGENT_DIR/.${LABEL}.$$.tmp"
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>${app_script}</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StartCalendarInterval</key><array>
    <dict><key>Hour</key><integer>6</integer><key>Minute</key><integer>0</integer></dict>
    <dict><key>Hour</key><integer>21</integer><key>Minute</key><integer>0</integer></dict>
  </array>
  <key>StandardOutPath</key><string>${log_out}</string>
  <key>StandardErrorPath</key><string>${log_err}</string>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$tmp" >/dev/null || fail 'launchd 配置验证失败。'
# Boot out any previous version. The exit status may indicate no prior job.
/bin/launchctl bootout "gui/$UID_NUM/$LABEL" >/dev/null 2>&1 || true
/bin/mv -f "$tmp" "$PLIST"
/bin/chmod 600 "$PLIST"
/bin/launchctl enable "gui/$UID_NUM/$LABEL" || fail '未能启用 launchd 任务。'
/bin/launchctl bootstrap "gui/$UID_NUM" "$PLIST" || fail '无法启动 launchd 任务。请运行“检查状态.command”诊断。'

info '安装完成：每天 06:00 上限 80%，21:00 上限 100%。'
echo '06:00 市电来电后停在 80%。21:00 开始允许充到 100%，给 23:30 断电前留出约 2.5 小时。'
echo '23:30 之后上限保持 100%，外置充电宝可以继续充电。'
echo '已经启动 launchd；登录时也会按当前时间校准。'
echo '请打开系统设置 → 电池，手动验证充电上限是否真的改变。'
echo '务必删除原先的 06:30 / 14:30 / 22:30 自动化，避免相互覆盖。'
echo '电池不会因为切换充电上限而自动放电。电量已经高于 80% 时，早上只会停止继续充，不会掉到 80%。'
