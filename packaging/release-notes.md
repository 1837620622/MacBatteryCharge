# 充电上限 3.2.4

这一版让「平时停在多少」和「拔电源时要多少」能填自定义的数字，习惯页看得懂了，第一次打开的引导也重做了。

## 变化

- **自定义数字。** 「平时停在多少」可选 80、85、90、95，「拔电源时要多少」可选 80、90、100，两个都能点「自定义」，填你想要的数字。系统只接受它自己的几档时，超出的部分按最近一档停；要精确停在那个数，需要放电帮手（在「设置 → 高级」里装一次）。
- **习惯和细节重做。** 显示学习依据：一共记下几次、一小时之内最多几次、还差几次；列出最近几次拔电源的日期和时间。温馨提醒没够用时，直接说还差几天。
- **学习规则改了。** 一小时之内记满 3 次，才会说「你平时大约几点拔电源」，跨午夜也算。之前要求同一个半小时。
- **五页引导。** 第一次打开时，依次说明是什么、怎么运行、怎么设置、怎么学习、其他。可以跳过，设置里能再看一次。
- **退出时保存习惯。** 之前退出时可能丢掉最后几分钟的拔电源记录，现在退出前会一起写下来。
- **手动装新版后更快重开。** 旧版本每 5 秒看一次，装完十几秒内换成新版本，不用等一两分钟。窗口开着时带着窗口重开。
- **引导文字更正。** 「平时停在多少」的可选值是 80、85、90、95；装放电帮手需要管理员密码，引导不再说「不要密码」。
- **README 截图更新。** 三种语言的 README 换成最新界面，包括设置里的工作日停电。

## 升级

直接覆盖安装即可，设置保留。放电帮手跟着 App 版本走，升级到 3.2.4 后要在「设置 → 高级」里重新装一次；装好之前充电上限照样生效，放电和低电量模式要等装好才会用。PKG 会自己换掉它。

---

## 繁體中文

Charge Limit 3.2.4 讓「平時停在多少」和「拔電源時要多少」能填自訂的數字，習慣頁看得懂了，第一次打開的引導也重做了。

- **自訂數字。** 「平時停在多少」可選 80、85、90、95，「拔電源時要多少」可選 80、90、100，兩個都能點「自訂」，填你想要的數字。系統只接受它自己的幾檔時，超出的部分按最近一檔停；要精確停在那個數，需要放電幫手（在「設定 → 進階」裡裝一次）。
- **習慣和細節重做。** 顯示學習依據：一共記下幾次、一小時之內最多幾次、還差幾次；列出最近幾次拔電源的日期和時間。溫馨提醒沒夠用時，直接說還差幾天。
- **學習規則改了。** 一小時之內記滿 3 次，才會說「你平時大約幾點拔電源」，跨午夜也算。之前要求同一個半小時。
- **五頁引導。** 第一次打開時，依次說明是什麼、怎麼運行、怎麼設定、怎麼學習、其他。可以跳過，設定裡能再看一次。
- **退出時保存習慣。** 之前退出時可能丟掉最後幾分鐘的拔電源記錄，現在退出前會一起寫下來。
- **手動裝新版後更快重開。** 舊版本每 5 秒看一次，裝完十幾秒內換成新版本，不用等一兩分鐘。視窗開著時帶著視窗重開。
- **引導文字更正。** 「平時停在多少」的可選值是 80、85、90、95；裝放電幫手需要管理員密碼，引導不再說「不要密碼」。
- **README 截圖更新。** 三種語言的 README 換成最新介面，包括設定裡的工作日停電。

## 升級

直接覆蓋安裝即可，設定保留。放電幫手跟著 App 版本走，升級到 3.2.4 後要在「設定 → 進階」裡重新裝一次；裝好之前充電上限照樣生效，放電和低電量模式要等裝好才會用。PKG 會自己換掉它。

## English

Charge Limit 3.2.4 lets you enter your own numbers for the everyday limit and the unplug target, makes the habit section easier to follow, and redesigns the first-run guide.

- **Custom values.** The everyday limit offers 80, 85, 90 and 95; the unplug target offers 80, 90 and 100. Both have a Custom option where you can type any number. When the system only accepts its own steps, a value in between stops at the nearest one. To stop at that exact number, install the discharge helper once in Settings → Advanced.
- **Habit section rebuilt.** It shows the basis for what the app has learned: how many unplugs it has recorded, how many fell within one hour, and how many are still needed. It also lists your most recent unplugs by date and time. When there isn't enough data for the tips, it says how many more days are needed.
- **New learning rule.** The app only says when you usually unplug after it has recorded 3 unplugs within one hour, counting across midnight. Previously the window was half an hour.
- **Five-page guide.** On first launch it explains what the app is, how it runs, how to set it up, how it learns, and other details. You can skip it, and see it again in Settings.
- **Habits saved on quit.** Quitting could previously lose the last few minutes of unplug records. The app now saves them before it exits.
- **Faster reopen after a manual update.** The running old version checks every 5 seconds and switches to the new one within about ten seconds of installing, rather than after a minute or two. If the window is open, it reopens with the window.
- **Guide text corrected.** The everyday limit's options are 80, 85, 90 and 95. Installing the discharge helper asks for an administrator password, so the guide no longer says you don't need one.
- **Updated README screenshots.** The READMEs in all three languages show the current interface, including weekday power cuts in Settings.

## Upgrading

Install over the existing app and your settings are kept. The discharge helper is tied to the app version, so after upgrading to 3.2.4, reinstall it in Settings → Advanced. The charge limit keeps working until then; discharging and Low Power Mode need the reinstalled helper. The PKG replaces it automatically.
