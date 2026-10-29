# 充电上限 3.1.1

这一版加了自动更新，菜单栏改成弹窗，图标换成和 App 图标一样的五格电池，并修了一批检查时发现的问题。

## 变化

- **自动更新。** 查到新版本后在后台下好安装包，用 GitHub 给的 SHA-256 核对。主窗口最上面提示：点「立即安装」，输入一次管理员密码，装完退出并打开新版本，设置和数据都保留。下载或安装没成功时写明原因，并给「去下载页面」。
- **菜单栏是弹窗。** 点图标从图标下面弹出主界面，点别处或再点图标收起。设置和引导在弹窗里换页。
- **新图标。** 菜单栏图标是五格电池：电量够几格就填几格，右边是百分比，充电时带闪电。安装器的欢迎页和结束页用 2 倍图标。
- **界面。** 主窗口最上面放「今晚」的计划；智能模式的「习惯和细节」收进折叠区；时间选择器跟着界面语言显示；放电选项单独一行。
- **修正。** 习惯时长按小数累计；「平时几点拔」票数并列时固定取较早的一个；一直充满模式的预计时间不再借用固定时间表；智能模式的临时充满一直到拔掉电源为止；灵动岛面板看不见时不再装鼠标监听。

## 升级

直接覆盖安装即可，设置保留。

## 还没有在真机上完整测过

CI 能编译、跑测试、打包和生成截图，但自动更新的下载、密码框、安装和重新打开，菜单栏点击弹窗，灵动岛的点击和插拔弹出，都还没在真机上跑过。遇到问题请到 Issues 反馈。

---

## English

Charge Limit 3.1.1 adds automatic updates, turns the menu bar item into a popover, and switches the icon to the five-bar battery from the app icon. It also fixes several issues found in review.

- **Automatic updates.** New versions download in the background and are checked against GitHub's SHA-256. The main window shows the update at the top: click “Install Now”, enter your administrator password once, and the app installs the new version and reopens. Your settings and data are kept. If the download or install fails, the reason is shown with an “Open Download Page” link.
- **Menu bar popover.** Click the icon to open the window below it; click elsewhere or the icon again to close it. Settings and the guide page inside the popover.
- **New icon.** The menu bar icon is a five-bar battery that fills with your charge, with the percentage beside it and a bolt while charging. The installer's welcome and conclusion pages use a 2× icon.
- **Interface.** Tonight's plan sits at the top of the main window. Habit details are collapsed in smart mode. Time pickers follow the interface language. The discharge option has its own line.
- **Fixes.** Habit durations accumulate as fractions. Ties in the usual unplug time resolve to the earlier one. Always-full forecasts no longer borrow the fixed schedule. Smart-mode top-up runs until you unplug. The island no longer installs mouse monitors while its panel is hidden.

## Upgrading

Install over 3.1.0 as usual. Settings are kept.

## Not yet fully tested on real hardware

CI compiles, runs the tests, packages the apps, and renders the screenshots. The update download, password prompt, install and relaunch, the menu bar popover click behaviour, and the island's click and plug-in behaviour have not yet been run on a real Mac. Please report problems in Issues.
