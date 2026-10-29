# MacBatteryCharge

MacBook 充电上限定时切换，按这套作息：

- **06:00 市电来电**：充电上限设为 **80%**。白天插着电，停在 80% 附近。
- **21:00**：充电上限设为 **100%**。用 21:00 到 23:30 这 2.5 小时，把电从大约 80% 补上去。
- **23:30 市电断电**：此时开始用电池写代码。上限保持 100%，自己接上外置充电宝后可以继续充到 100%。

使用 Apple 系统原生的“将充电上限设为”快捷指令，不修改 SMC，不安装第三方电池驱动，不请求 root 权限。

> **适用条件：** Apple 芯片 MacBook、macOS 26.4 或更新版本。21:00 把上限改成 100%，并不保证 21:00 那一刻就满电；电脑必须还接着市电，才会开始补电。**本项目不主动放电**。若早上插电时电量已经高于 80%，改成 80% 不会把电量放下来，只会停止继续往上充。

80% 充到 100% 是整段充电里最慢的一段，常见要 1 到 2 小时，机器正在使用或充电器功率较低时更久。原先 22:30 才放开，到 23:30 断电只剩 1 小时，经常补不满。所以补电起点放在 **21:00**。

## 新建 GitHub 仓库并自动构建

1. 在 GitHub 新建一个**空仓库**，例如 `MacBatteryCharge`。不要勾选创建 README、`.gitignore` 或许可证（这些文件已在本项目里）。
2. 下载并解压提供的**仓库源码 ZIP**，打开其中 `MacBatteryCharge-GitHub` 文件夹，在这个文件夹内执行下面的命令。把 `<你的用户名>` 替换成你的 GitHub 用户名：

   ```bash
   git init -b main
   git add -A
   git commit -m "Initial MacBatteryCharge release"
   git remote add origin https://github.com/<你的用户名>/MacBatteryCharge.git
   git push -u origin main
   ```

3. 进入仓库的 **Actions** 页。如果出现启用工作流提示，按 GitHub 提示启用。推送到 `main` 后，工作流 `Build macOS battery charge installer` 将自动启动；也可以点 `Run workflow` 手动触发。
4. 工作流成功后，可在仓库 **Releases** 下载 `MacBatteryCharge-macOS-Installer.zip`；也可以在该次 Actions 运行页面的 **Artifacts** 下载。
5. 解压安装包，双击 **`安装.command`**，按提示在快捷指令应用里点击两次“添加快捷指令”。导入完成后，安装器自动创建并启用两个时间点的定时任务。
6. 完成后双击 **`检查状态.command`** 查看日志，再到“系统设置 → 电池”核对充电上限是否真的改变。

**提醒：** GitHub Actions 使用 Apple 提供的 macOS runner 和 `shortcuts sign --mode anyone` 签名；签名需要访问 Apple 服务。若 Apple 在无账号的 runner 上拒绝签名，构建会**明确失败**，不会发布一个冒充可安装文件的 ZIP。遇到此情况可在自己的 Mac 上执行 `scripts/local_build.command`，它会使用本机签名模式制作相同的安装包。该本机签名版本适合自己导入，不适合公开分享。

## 安装后如何运行

| 本机时间 | 市电 | 充电上限 | 实际含义 |
|---|---|---|---|
| 06:00–20:59 | 有 | 80% | 来电后允许充到 80%，然后停住 |
| 21:00–23:30 | 有 | 100% | 断电前的补电窗口 |
| 23:30–05:59 | 无 | 100% | 电池写代码；充电宝接入后可充到 100% |

- 安装器会在 `~/Library/LaunchAgents` 中创建用户级 `launchd` 任务，定时执行系统 `shortcuts run`。无需保持 Terminal 打开，也无需自行设置 Mac 快捷指令“自动化”选项。
- 两个触发点是 **06:00** 和 **21:00**。登录时会按当前时间校准。睡眠错过的日历触发通常在唤醒后补执行，并**以唤醒时当前时间**决定目标上限，避免执行过期的 80% / 100% 操作。设备关机时不会运行。
- 23:30 没有单独的定时任务。市电断开是物理断电，软件不需要再切一次；上限从 21:00 起已经是 100%。
- 需要用户处于登录会话；部分系统权限、锁屏或快捷指令设置仍可能阻止无交互运行。安装后必须在本机测试一次，并检查对应日志。

## 常用操作

在下载的安装包中双击：

- `安装.command`：导入两条中文快捷指令「白天充电上限80」「晚间充电上限100」，并安装 `launchd` 定时任务。
- `立即校准.command`：立即按当前时间设定上限。
- `检查状态.command`：检查是否安装、读取最近运行日志。
- `卸载.command`：移除定时任务；不删除两个快捷指令，不修改当前电池上限。

旧版通过快捷指令应用创建的 **06:30 / 14:30 / 22:30 自动化应先禁用或删除**，否则会与新定时器相互覆盖。电池的上限是系统设置，不是强制物理电源通断，也不是主动放电工具。

## 开发与验证

```bash
python3 -m unittest discover -s tests -v
python3 tools/charge_shortcuts.py --output build/unsigned
bash -n scripts/*.command scripts/*.sh
```

CI 检查 Bash 语法、1440 分钟的时间边界、快捷指令 plist 结构、Apple 签名及 ZIP 归档完整性。**CI 不会测试 MacBook 真实充电硬件**：GitHub runner 并不是有电池的 MacBook，因此签名或测试通过不等于实际电池上限已修改。

技术说明见 [docs/INSTALL.md](docs/INSTALL.md)。

## 参考资料

- [Apple：Mac 充电上限](https://support.apple.com/en-ie/102338)
- [Apple：运行和签署快捷指令](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac)
- [Apple：launchd.plist 定时任务](https://github.com/apple-oss-distributions/launchd/blob/main/man/launchd.plist.5)
- [GitHub：macos-26 runners](https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/)
