# 充电上限 3.2.0

这一版把更新改回手动下载（撤回 3.1.1 的自动安装），主窗口加了电量曲线，并修了一批检查时发现的问题。

## 变化

- **更新改回手动。** 3.1.1 的自动下载、校验、替换和密码都撤回了。查到新版本只提示，点「下载新版本」在浏览器里下载安装包，自己安装。手动装上以后，正在运行的旧版本会在一两分钟内自己重新打开。
- **电量曲线。** 主窗口「今晚」计划下面，过去 16 小时的实线，和之后 8 小时的虚线预测。预测跟着模式走，离电时间只有一个来源。
- **习惯。** 「同一个半小时里记满 3 次」才会学会，说法写清楚了；「一直插着电源」的提醒改成建议把日常上限设在 80%。
- **界面。** 新加的时间段默认 80%；设置页里也能看到提示；时间表有错的提示不再有无效的「关掉」按钮；一直充满模式不显示「临时充满」。
- **赞助。** 设置「关于」里加了「支持这个项目」和「企业合作」入口，链接改对了。去掉了没有依据的联系方式。

## 升级

直接覆盖安装即可，设置保留。覆盖安装 DMG 后，放电帮手要在「设置 → 高级」里重新装一次；PKG 会自己换掉它。

## 还没有在真机上完整测过

CI 能编译、跑测试、打包、生成截图，但菜单栏点击弹窗、灵动岛点击和插拔弹出、手动装上后旧版本自己重新打开、电量曲线的显示，都还没在真机上跑过。遇到问题请到 Issues 反馈。

---

## English

Charge Limit 3.2.0 takes automatic updates back out (3.1.1 installed updates on its own), adds a charge curve to the main window, and fixes several issues found in review.

- **Manual updates again.** Automatic download, verification, replacement, and the password prompt from 3.1.1 are removed. A new version only shows a notice. "Download New Version" opens the installer in your browser, and you install it yourself. After you install a new version, the old one still running reopens itself within a minute or two.
- **Charge curve.** Below tonight's plan in the main window: the last 16 hours as a solid line, and the next 8 hours as a dashed forecast. The forecast follows the mode, and there is one source for the time you unplug.
- **Habits.** The rule is now stated clearly: a habit is learned once 3 unplugs fall in the same half hour. The advice for staying plugged in is now to keep the daily limit at 80%.
- **Interface.** New time blocks default to 80%. Messages from Settings show on the Settings page. A schedule error has no dismiss button, since it goes away once fixed. Always-full mode doesn't show top-up.
- **Sponsorship.** Settings → About has "Support this project" and "Enterprise cooperation" links, now pointing at the right repository and README section. Unverified contact details were removed.

## Upgrading

Install over the existing app and your settings are kept. If you install the DMG over the old app, the discharge helper stays on the old version. Reinstall it in Settings → Advanced. The PKG replaces it automatically.

## Not yet tested on real Macs

CI can build, test, package, and generate screenshots. The menu bar popover, clicking and plug-in pop-up of the Notch island, the old version reopening itself after a manual install, and the charge curve still need a real Mac check. Report problems in Issues.
