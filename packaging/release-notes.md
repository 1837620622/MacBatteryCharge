# 充电上限 3.2.3

这一版让多语言也覆盖文档：README 和企业合作文档都有简体、繁体、英文三个版本，应用里的赞助和企业合作链接跟着界面语言走。

## 变化

- **多语言文档。** 三个 README 之间可以切换，企业合作文档也有繁体和英文版；链接都指向对应语言。
- **应用里的链接跟着语言走。** 设置「关于」里的「支持这个项目」「企业合作」打开的是当前界面语言的文档。
- **离电那一分钟仍保持离电目标。** 之前最后一分钟会掉回日常上限。
- **放电更稳。** 温度或电量偶尔读不到时，正在放电的先保持一分钟，不再让适配器来回切换。
- **删掉残留的低电量说明。** 权限提示里不再写「写入低电量模式」。
- **低电量模式。** 夜间（18:00 到次日 06:00）充电时开启，充完电或白天充电时关掉；拔掉电源后只关掉自己开过的。需要放电帮手（装一次）。
- **旧版本的放电帮手不再挡住充电上限。** 版本不对时充电上限照样生效。

## 升级

直接覆盖安装即可，设置保留。覆盖安装 DMG 后，放电帮手要在「设置 → 高级」里重新装一次；PKG 会自己换掉它。

---

## 繁體中文

Charge Limit 3.2.3 讓多語言也涵蓋文件：README 和企業合作文件都有簡體、繁體、英文三個版本，應用裡的贊助和企業合作連結跟著介面語言走。

- **多語言文件。** 三個 README 之間可以切換，企業合作文件也有繁體和英文版。
- **應用裡的連結跟著語言走。** 設定「關於」裡的「支援這個專案」「企業合作」打開的是目前介面語言的文件。
- **離電那一分鐘仍保持離電目標。** 之前最後一分鐘會掉回日常上限。
- **放電更穩。** 溫度或電量偶爾讀不到時，正在放電的先保持一分鐘，不再讓轉接器來回切換。
- **刪掉殘留的低電量說明。** 權限提示裡不再寫「寫入低電量模式」。
- **低電量模式。** 夜間（18:00 到次日 06:00）充電時開啟，充完電或白天充電時關掉；拔掉電源後只關掉自己開過的。需要放電幫手（裝一次）。
- **舊版本的放電幫手不再擋住充電上限。** 版本不對時充電上限照樣生效。

## English

Charge Limit 3.2.3 extends multilingual support to the documentation. The README and the enterprise cooperation document are now available in Simplified Chinese, Traditional Chinese and English, and the sponsorship and enterprise links in the app open the version matching the interface language.

- **Multilingual docs.** You can switch between the three READMEs, and the enterprise cooperation document has Traditional Chinese and English versions. Links point to the matching language.
- **App links follow the language.** "Support this project" and "Enterprise cooperation" in Settings → About open the document in the current interface language.
- **Charge target held at the deadline minute.** Previously the last minute before the deadline dropped back to the everyday cap.
- **Steadier discharging.** If temperature or charge is briefly unreadable, an ongoing discharge holds for one minute instead of switching the adapter back and forth.
- **Stale low-power text removed.** The permission prompt no longer says it writes low-power mode.
- **Low Power Mode.** Turned on while charging at night (18:00 to 06:00), and off when charging finishes or when charging during the day. After you unplug, only what the app turned on is turned off. Needs the discharge helper (install once).
- **An older discharge helper no longer blocks the charge limit.** The charge limit keeps working after an app update until you reinstall the helper.

## Upgrading

Install over the existing app and your settings are kept. If you install the DMG over the old app, the discharge helper stays on the old version. Reinstall it in Settings → Advanced. The PKG replaces it automatically.
