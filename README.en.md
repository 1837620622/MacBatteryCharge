# Charge Limit

**Easier on your battery, and full enough when you unplug.**

Charge Limit is a small macOS menu bar app. By day it holds the battery at around 80% so it doesn't sit at 100% for hours. It learns when you usually unplug, and tops the battery up before that moment. Free and open source.

English · [简体中文](README.md) · [繁體中文](README.zh-Hant.md)

<p align="center">
  <img src="docs/images/main-smart-en.png" height="460" alt="Main window: Smart mode">
  <img src="docs/images/settings-en.png" height="460" alt="Settings window">
</p>

## Three modes

Pick one at the top of the window:

| Mode | Good for | What it does |
|---|---|---|
| **Smart** (default) | Most people | Holds at the daily limit (80% by default; 85, 90 or 95 if you prefer). Learns when you usually unplug and reaches your target (100% by default; 80 or 90 possible) before then. |
| **Fixed** | People who want their own schedule | Splits the day into blocks, each with a limit you choose (80, 85, 90, 95 or 100). Time not covered charges to 100%. You can also turn on "full before unplugging". |
| **Always full** | Desktops, or machines that stay plugged in | Charges to 100% whenever it is plugged in. |

All three modes have heat protection: when the battery runs hot (above 35°C), the limit stays at 80% until it cools below 33°C.

## How it learns your habits

- The first long plugged-in session each day (at least 30 minutes) that ends in an unplug counts as one unplug. Moving the Mac around or a quick replug doesn't count.
- After three of them it can tell you roughly when you usually unplug, and tops up before that time.
- Everything stays on your Mac. Nothing is uploaded. You can learn again at any time, or turn learning off and use only your default unplug time.

## The interface

- **Main window**: charge level, what it is doing right now, the three modes and "top up now".
- **Settings** (the gear in the top-right corner): language (English, 简体中文, 繁體中文; follows the system by default), launch at login, notifications, appearance, the notch island, advanced options.
- **Notch island** (Macs with a notch): click the notch to open it, click again to close it. It also pops out when you plug or unplug, and closes after a few seconds.

<p align="center">
  <img src="docs/images/island-expanded-en.png" width="420" alt="Notch island expanded">
</p>

## Install

Download the file for your chip from [Releases](https://github.com/1837620622/MacFullBar/releases):

- Apple silicon: `MacBatteryCharge-<version>-arm64.dmg` or `.pkg`
- Intel: `MacBatteryCharge-<version>-intel.dmg` or `.pkg`

Open the DMG and drag Charge Limit into Applications. The PKG walks you through the installation into Applications.

The app is not notarized by Apple. If macOS blocks it the first time, go to System Settings → Privacy & Security and click "Open Anyway".

## Permissions and privacy

- Reading the battery and temperature needs no permission.
- Setting the charge limit needs no password.
- It does not ask for Full Disk Access, Accessibility, Screen Recording or Input Monitoring. The notch island only uses mouse position and clicks.
- No account, no upload of battery data, no collection of usage habits.
- The app only goes online to check for new versions (at most once a day by default; you can turn it off in Settings) and when you choose to download an update.

## Discharge helper (optional)

macOS's own charge limit only stops charging. It cannot discharge while plugged in. To bring the battery down from 85% to 80%, the app has to disconnect the power adapter for a moment, which means writing to the SMC. That needs a small helper that runs as root.

- It is only used by blocks in Fixed mode that have "discharge" turned on. Installing it asks for an administrator password once; the app never sees that password.
- It only disconnects and reconnects the adapter. It writes nothing else.
- It does not discharge below 20%. It always reconnects power before sleep, and when the app quits or loses contact with the helper.
- To remove it: Settings → Advanced → Remove discharge helper.

## Honest limits

- Topping up before you unplug is not a guarantee. If the unplug time moves earlier, or charging is slower (for example on a power bank), the battery may not be full in time.
- Apple's own limit is approximate. It can be a few percent off, and it occasionally charges to 100%. The app cannot prevent that.
- Temperature comes from the battery sensor the system reads, and it may differ slightly from what other tools show.
- Continuous integration builds, tests and packages the app, but it cannot test on every real Mac. Please try it on your own machine and report problems in [Issues](https://github.com/1837620622/MacFullBar/issues).

## Development

```bash
swift test                                              # logic tests, no hardware needed
bash packaging/build.sh                                 # builds both chips, makes the PKG and DMG, checks icon and languages are inside
.build/release/MacBatteryCharge --snapshot snapshots    # renders the interface with sample data
```

Design notes: [requirements](docs/设计要求.md), [interface](docs/界面.md), [research](docs/调研.md) (in Chinese). Version history: [CHANGELOG](CHANGELOG.md).

## Support and partnership

Charge Limit is free and open source, and every feature is free. Personal support is voluntary and any amount is fine; it does not unlock anything. For company partnerships, custom work or support, see [enterprise cooperation](docs/企业合作.md) (in Chinese).

Contact: WeChat 1837620622 (please say why you are writing).

## Thanks

Thanks to [Calma](https://github.com/Milanpatel35/calma) and [batt](https://github.com/charlie0129/batt) for their public work and ideas.

## License

GNU GPL-3.0, see [LICENSE](LICENSE). © 2026 传康Kk.
