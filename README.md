<p align="center">
  <img src="Tether/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="112" height="112" alt="Tether app icon" />
</p>

<h1 align="center">Tether</h1>

<p align="center">
  <strong>Your Android phone, at home on your Mac.</strong><br />
  Notifications you can reply to, your texts, files and clipboard, in a native Mac app that weighs 2.3&nbsp;MB.
</p>

<p align="center">
  <a href="https://github.com/subhashhhhhh/Tether/releases/latest"><img src="https://img.shields.io/github/v/release/subhashhhhhh/Tether?style=flat-square&color=2e6bf0&label=download" alt="Latest release" /></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-black?style=flat-square" alt="macOS 15 or later" />
  <img src="https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-supported-black?style=flat-square" alt="Apple Silicon and Intel" />
  <img src="https://img.shields.io/badge/license-GPL--2.0-3b8f4a?style=flat-square" alt="GPL-2.0" />
</p>

<p align="center">
  <img src="docs/images/hero.jpg" alt="Tether's main window and menu bar popover on a Mac desktop" />
</p>

Tether is a native macOS app for the free **KDE Connect** app on Android. Pair your phone once, and from then on it shows up in your menu bar whenever it's nearby: phone notifications appear on your Mac and can be answered there, your text conversations sync, files and the clipboard move both ways, and you can ring, lock or control your phone without picking it up.

It is written entirely in Swift and SwiftUI, with no Qt, no Electron and no third-party libraries.

## Download

Get the latest release from the **[Releases page](https://github.com/subhashhhhhh/Tether/releases/latest)**. There are two downloads; pick the one for your Mac:

| Your Mac | Download |
| --- | --- |
| Apple Silicon (M1 and later) | `Tether-<version>-AppleSilicon.dmg` |
| Intel | `Tether-<version>-Intel.dmg` |

Not sure? Apple menu → **About This Mac**: it says **Chip** on Apple Silicon and **Processor** on Intel. Tether needs **macOS 15 Sequoia** or later.

On your phone, install **KDE Connect** from [Google Play](https://play.google.com/store/apps/details?id=org.kde.kdeconnect_tp) or [F-Droid](https://f-droid.org/packages/org.kde.kdeconnect_tp/).

## What it does

**Notifications, answered from the Mac.** Phone notifications appear in Notification Center. Messaging apps that support it (SMS, WhatsApp, Telegram, Signal and others) can be replied to right from the banner, and anything you dismiss on the Mac is dismissed on the phone.

**Your texts.** SMS conversations sync to the Messages section, where you can read threads and send replies.

**Files, both ways.** Drop files anywhere in the Tether window or on the menu bar popover, or choose **Share › Tether** in Finder, Photos and other apps, to send them to your phone. With more than one phone connected, the Share menu asks which one. Files shared from your phone land in **Downloads** with live progress.

**Clipboard, media and remote control.** Copy on one device, paste on the other. See what's playing on your phone and control playback and volume. **Find Phone** rings it at full volume, and **Lock** locks it.

**Your phone as a trackpad and presenter.** KDE Connect's Remote Input and Presentation tools move the pointer, click, scroll, type and show an on-screen laser pointer. This needs Accessibility access, which you can grant from Tether's Overview or Settings.

**Commands.** Set up shell commands on your Mac and run them from your phone.

**Lives in the menu bar.** The menu bar popover shows your phone's battery and connection, quick actions, what's playing and new pairing requests. The main window has a sidebar with your devices and each phone's Messages, Notifications, Files and Commands.

<p align="center">
  <img src="docs/images/messages.jpg" alt="Tether's Messages view with a reply from a notification banner" />
</p>

## Use it from anywhere with Tailscale

KDE Connect normally needs your phone and Mac on the same Wi-Fi. If you use [Tailscale](https://tailscale.com) on both, Tether finds your phone on your tailnet automatically, so everything keeps working when you're on mobile data or a different network.

- Tether only contacts Android and iOS devices that are signed in to **your own** Tailscale account. Devices shared with you by other people are never contacted.
- It reads your tailnet from the `tailscale` app on your Mac and never talks to Tailscale's servers.
- Turn it on or off in **Settings › General › Tailscale**. **Connect by Address…** also accepts Tailscale names such as `phone.tailnet.ts.net`.

<p align="center">
  <img src="docs/images/anywhere.jpg" alt="Tether connecting to a phone on mobile data over Tailscale" />
</p>

## Small, and quiet when idle

<p align="center">
  <img src="docs/images/size.jpg" alt="Tether's 2.3 MB download compared with the official KDE Connect for macOS at 87 MB" />
</p>

| | Tether 1.4 | KDE Connect 26.08 for macOS |
| --- | --- | --- |
| Download (Apple Silicon disk image) | **2.3 MB** | 87 MB |
| Installed app | **5.8 MB** | |
| Memory while idle | **19 MB** | |
| CPU while idle | **0%** | |

Measured in October 2026 on an Apple Silicon Mac: Tether's numbers come from the 1.4 release while connected to a phone, and the official app's download size from KDE's release builds. The empty cells weren't measured.

## Privacy and security

- **No cloud.** Your phone and Mac talk directly over your local network, or over your own Tailscale network. There are no Tether servers, accounts, analytics or telemetry.
- **Encrypted.** Every connection and file transfer uses TLS.
- **Pinned to your phone.** Pairing saves your phone's certificate, and every later connection and file transfer must present that exact certificate. A device that only pretends to be your phone is refused.
- **Your Mac's identity stays private.** Tether's certificate and key live in `~/Library/Application Support/Tether`, readable only by your user account, and are loaded into memory rather than the keychain.

## Install and pair

1. Open the disk image and drag **Tether** into **Applications**.
2. Open Tether. It lives in the menu bar.
3. On your phone, open **KDE Connect** and tap your Mac in the device list. Tether asks you to confirm: click **Pair**.

Your phone shows up under **Nearby** in Tether's sidebar too, if you'd rather start pairing from the Mac. If it doesn't appear, use **Connect by Address…** with the phone's IP address or Tailscale name.

### "Tether can't be opened"

Tether isn't notarized by Apple (that needs a paid developer account), so macOS blocks it the first time:

1. Try to open Tether, then close the warning.
2. Open **System Settings → Privacy & Security**, scroll to **Security** and click **Open Anyway**.

Or, in Terminal:

```bash
xattr -cr /Applications/Tether.app
```

## Build from source

You need **Xcode 26** or later (the project uses Swift 6.2's default main-actor isolation). There are no package dependencies.

```bash
git clone https://github.com/subhashhhhhh/Tether.git
cd Tether

# Run the tests
xcodebuild test -project Tether.xcodeproj -scheme Tether -destination "platform=macOS"

# Build the app (ends up in build/Build/Products/Release/Tether.app)
xcodebuild -project Tether.xcodeproj -scheme Tether -configuration Release -derivedDataPath build build

# Build the two release disk images (Apple Silicon and Intel) into dist/
scripts/release.sh
```

### How it works

- **UI:** SwiftUI with `@Observable` view models, built from stock controls, grouped forms and a sidebar list, so it follows Light and Dark mode, your accent colour and accessibility settings.
- **Networking:** BSD sockets with `poll()`-driven I/O and Security framework TLS. KDE Connect upgrades an open connection to TLS after a plaintext handshake, which `Network.framework` can't do.
- **Identity:** created once with the `openssl` tool that ships with macOS, then loaded in memory by the Security framework.

## License

GPL-2.0, like the KDE Connect ecosystem. See [LICENSE](LICENSE).

Tether is an independent project and isn't affiliated with KDE.
