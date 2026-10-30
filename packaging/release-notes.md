# 充电上限 3.2.7

这一版修正停电低电量模式的两个问题：重启以后不会残留，也不会关掉你自己开着的低电量模式。

## 变化

- **重启以后不再残留低电量模式。** 停电时软件开了低电量模式，之后重启或者退出重开，来电时会把它关掉。之前重启后可能一直停在低电量模式里。
- **不动你自己开着的低电量模式。** 停电时如果低电量模式本来就是你手动开着的，软件不再接手，来电时也不会把它关掉。

## 升级

直接覆盖安装即可，设置保留。放电帮手跟着 App 版本走，升级到 3.2.7 后要在「设置 → 高级」里重新装一次；装好之前充电上限照样生效，放电和低电量模式要等装好才会用。PKG 会自己换掉它。

---

## 繁體中文

Charge Limit 3.2.7 修正停電低電量模式的兩個問題：重開機以後不會殘留，也不會關掉你自己開著的低電量模式。

## 變化

- **重開機以後不再殘留低電量模式。** 停電時軟體開了低電量模式，之後重開機或者退出重開，來電時會把它關掉。之前重開機後可能一直停在低電量模式裡。
- **不動你自己開著的低電量模式。** 停電時如果低電量模式本來就是你手動開著的，軟體不再接手，來電時也不會把它關掉。

## 升級

直接覆蓋安裝即可，設定保留。放電幫手跟著 App 版本走，升級到 3.2.7 後要在「設定 → 進階」裡重新裝一次；裝好之前充電上限照樣生效，放電和低電量模式要等裝好才會用。PKG 會自己換掉它。

---

## English

Charge Limit 3.2.7 fixes two problems with Low Power Mode during power cuts: it no longer lingers after a restart, and it no longer turns off a Low Power Mode you set yourself.

## Changes

- **Low Power Mode no longer lingers after a restart.** If the app turned on Low Power Mode during a cut, and then the Mac restarts or the app quits and reopens, it turns Low Power Mode off when power returns. Before this, it could stay on after a restart.
- **Your own Low Power Mode is left alone.** If you already had Low Power Mode on yourself when a cut started, the app doesn't take over, and it doesn't turn it off when power returns.

## Upgrading

Install over the existing app and your settings are kept. The discharge helper is tied to the app version, so after upgrading to 3.2.7, reinstall it in Settings → Advanced. The charge limit keeps working until then; discharging and Low Power Mode need the reinstalled helper. The PKG replaces it automatically.
