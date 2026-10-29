# 充电上限 3.1.0

这一版把功能收窄，让平时用得上的部分更清楚，并修了安装包里看不到应用图标的问题。

## 变化

- **三种模式都能用，行为写得清楚。**
  - 智能（默认）：平时停在日常上限（80%，可选 85、90、95）；记住你平时几点拔电源，离电前充到目标（100%，可选 80、90）。
  - 固定：一天分段，每段一个上限；没排到的时间按 100% 充；可以选「断电前充满」。
  - 一直充满：接电源就充到 100%。
- **记住你的充电习惯。** 每天第一次接着电源满 30 分钟以上、然后拔掉，记作一次；记满 3 次就能说出你平时几点拔电源。可以重新学习，也可以关掉学习。
- **过热保护对所有模式都生效。** 电池偏热时最高停在 80%，之前「一直充满」模式会漏掉这一条，现在修了。
- **修正：** 智能模式不再显示「已提前放开」的通知（那是固定模式的逻辑）；检查更新指向正确的仓库。
- **界面重做。** 主窗口一屏看完状态、模式和临时充满；设置收进右上角的齿轮。引导改成三步。
- **去掉** 低电量模式、漂移、应用内安装和卸载、诊断复制。检查更新只打开发布页，下载你自己装。
- **安装包。** DMG 显示应用图标；PKG 的安装器里有欢迎页和应用图标，并限定芯片架构。
- **多语言。** 简体中文、繁體中文、English，默认跟随系统。

## 升级

旧版的设置文件照常读取。没有模式这一项的老文件，仍按固定模式（时间段）运行，不会悄悄换成智能。老文件里的低电量和漂移设置会被忽略。

## 还没有在真机上完整测过

CI 能编译、跑单元测试、打包，但没法替你在每一台真机上测。请在你自己的 Mac 上确认：智能模式会不会按时放开；固定时间段是否按设定；插拔电源时刘海弹出是否正常。遇到问题请到 Issues 反馈。


---

## English

Charge Limit 3.1.0 narrows the app to what people use every day, makes the three modes behave as described, and fixes missing app icons in the installers.

- **Three modes, clearly defined.** Smart (default) holds at the daily limit and learns when you usually unplug. Fixed uses a schedule of limits. Always full charges to 100%.
- **Learns your habits.** The first long plugged-in session each day (30+ minutes) that ends in an unplug counts. After three, it knows your usual unplug time. You can learn again or turn learning off.
- **Heat protection applies to every mode**, including Always full.
- **Interface redone.** One main window; settings behind the gear icon. Three-step guide.
- **Removed:** low-power mode, drift, in-app installer and uninstaller, diagnostics export. Update checks now open the release page.
- **Installers.** The DMG shows the app icon. The PKG installer has a welcome page with the icon and limits installation to the matching chip.
- **Languages:** 简体中文, 繁體中文, English, following the system by default.

Settings from older versions still load. A file without a mode stays on Fixed. Old low-power and drift settings are ignored.
