# 充电上限 3.2.6

这一版让停电时的低电量模式变成可选的，默认不开；设置页的布局修正好了，弹窗宽度也跟着屏幕走。

## 变化

- **停电时的低电量模式默认不开。** 「工作日停电」里多了「停电时保持低电量」，默认不勾。不勾，停电时照常充电；勾上，停电时开低电量模式省电，来电就关。
- **设置页不再被撑宽。** 工作日停电的时间行，标题放在左边，时间选择器不再把页面撑宽，两边不再被裁掉。
- **弹窗宽度跟着屏幕走。** 宽度取图标所在屏幕可用宽度的三成，在 400 到 520 点之间。屏幕宽的时候弹窗也跟着变宽，设置里的文字和时间不再挤在一起。

## 升级

直接覆盖安装即可，设置保留。放电帮手跟着 App 版本走，升级到 3.2.6 后要在「设置 → 高级」里重新装一次；装好之前充电上限照样生效，放电和低电量模式要等装好才会用。PKG 会自己换掉它。

停电时的低电量模式现在默认不开。升级后如果要停电省电，在「工作日停电」里勾上「停电时保持低电量」。

---

## 繁體中文

Charge Limit 3.2.6 讓停電時的低電量模式變成可選，預設不開；設定頁的版面修正好了，視窗寬度也跟著螢幕走。

- **停電時的低電量模式預設不開。** 「工作日停電」裡多了「停電時保持低電量」，預設不勾。不勾，停電時照常充電；勾上，停電時開低電量模式省電，來電就關。
- **設定頁不再被撐寬。** 工作日停電的時間行，標題放在左邊，時間選擇器不再把頁面撐寬，兩邊不再被裁掉。
- **視窗寬度跟著螢幕走。** 寬度取圖示所在螢幕可用寬度的三成，在 400 到 520 點之間。螢幕寬的時候視窗也跟著變寬，設定裡的文字和時間不再擠在一起。

## 升級

直接覆蓋安裝即可，設定保留。放電幫手跟著 App 版本走，升級到 3.2.6 後要在「設定 → 進階」裡重新裝一次；裝好之前充電上限照樣生效，放電和低電量模式要等裝好才會用。PKG 會自己換掉它。

停電時的低電量模式現在預設不開。升級後如果要停電省電，在「工作日停電」裡勾上「停電時保持低電量」。

---

## English

Charge Limit 3.2.6 makes Low Power Mode during power cuts opt-in, fixes the settings layout, and lets the window width follow your screen.

## Changes

- **Low Power Mode during power cuts is off by default.** Weekday power cuts has a new option, Keep Low Power Mode during power cuts, which is off by default. When it's off, the battery charges as usual during the cut. When it's on, Low Power Mode turns on during the cut to save battery, and turns off when power returns.
- **The settings page no longer stretches.** The labels for the power-cut times sit to the left of the time pickers, so the pickers no longer push the page wider and cut off both edges.
- **The window width follows your screen.** It is 30% of the usable width of the screen the menu bar icon is on, between 400 and 520 points. On wide screens the window gets wider too, so the settings text and times no longer crowd together.

## Upgrading

Install over the existing app and your settings are kept. The discharge helper is tied to the app version, so after upgrading to 3.2.6, reinstall it in Settings → Advanced. The charge limit keeps working until then; discharging and Low Power Mode need the reinstalled helper. The PKG replaces it automatically.

Low Power Mode during power cuts is now off by default. If you want it after upgrading, tick Keep Low Power Mode during power cuts under Weekday power cuts.
