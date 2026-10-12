# Tether

<p align="center">
  <img src="https://raw.githubusercontent.com/subhashhhhhh/Tether/main/Tether/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="128" height="128" alt="Tether App Icon" />
</p>

<p align="center">
  <strong>A modern, native macOS companion for Android built on the KDE Connect protocol.</strong>
</p>

<p align="center">
  <a href="https://github.com/subhashhhhhh/Tether/releases"><img src="https://img.shields.io/github/v/release/subhashhhhhh/Tether?style=flat-square&color=blue" alt="Release" /></a>
  <img src="https://img.shields.io/badge/DMG%20Size-3.3%20MB-brightgreen?style=flat-square" alt="DMG Size" />
  <img src="https://img.shields.io/badge/Installed%20Size-10%20MB-brightgreen?style=flat-square" alt="Installed Size" />
  <img src="https://img.shields.io/badge/Idle%20RAM-~15%20MB-brightgreen?style=flat-square" alt="Idle RAM" />
  <img src="https://img.shields.io/badge/Idle%20CPU-0.0%25-blue?style=flat-square" alt="Idle CPU" />
  <img src="https://img.shields.io/badge/Platform-macOS%2015%2B-black?style=flat-square" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5-orange?style=flat-square" alt="Swift" />
  <img src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20Observation-purple?style=flat-square" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/License-GPL--2.0-green?style=flat-square" alt="License" />
</p>

---

## Overview

**Tether** brings the power and versatility of the KDE Connect ecosystem to macOS in a fully native, sleek, and high-performance application. Designed from the ground up using SwiftUI, Apple's Observation framework, and native system materials, Tether seamlessly bridges the gap between your Mac and your Android device with **0.0% idle CPU** overhead and zero external dependencies.

Whether you want to push files, mirror notifications with inline replies, sync clipboards, control media, or navigate presentations with a virtual laser pointer, Tether provides an integrated, Apple-native experience.

---

## ⚡️ Lightweight & Blazing Fast: Tether vs. Official KDE Connect macOS

The official KDE Connect macOS release relies on Qt 6, KDE Frameworks, OpenSSL, D-Bus, and hundreds of dynamic shared libraries bundled into the package, resulting in a download size of **~90 MB** (expanding to **~370 MB** installed) and constant background resource overhead.

**Tether is written 100% natively in Swift**, utilizing Apple's system frameworks directly.

| Metric | Official KDE Connect (macOS) | Tether | Advantage |
| :--- | :--- | :--- | :--- |
| **Download / DMG Size** | ~90 MB | **3.3 MB** | **~96% smaller** |
| **Installed App Size** | ~370 MB | **10 MB** (universal) | **~97% smaller** |
| **Idle Memory (RAM)** | ~150 – 300 MB | **~15 – 25 MB** | **~90% less RAM** |
| **Idle CPU Usage** | 1.0 – 5.0% | **0.0%** | **Zero battery drain** |
| **External Dependencies** | Qt 6, D-Bus, OpenSSL | **Zero** (Pure Apple Frameworks) | **No background bloat** |
| **Cold Launch Time** | ~2 – 5 seconds | **< 50 milliseconds** | **Instantaneous** |
| **Design Language** | Emulated Qt / Linux widgets | **Native SwiftUI, system controls** | **True macOS look & feel** |

### Why is Tether so compact and efficient?
1. **Zero Web / Cross-Platform Runtimes**: No Chromium, Electron, Node.js, or Qt layers.
2. **Native Network & TLS Stack**: BSD sockets and Apple's `Security.framework` for TLS. (KDE Connect upgrades an open TCP connection to TLS after a plaintext handshake, which `Network.framework` cannot do.)
3. **ABI-Stable Swift Runtime**: Leverages the native Swift standard library already preinstalled in macOS.
4. **Single Universal Binary**: One compiled Mach-O for Apple Silicon and Intel, about 10 MB installed and 3.3 MB as a compressed disk image.

---

## ✨ Features

### 📱 Your Phone, at a Glance
- **Sidebar** with your paired and nearby devices; each connected phone lists its Messages, Notifications, Files and Commands right under it.
- **Overview** with battery, network, now playing (album art, playback controls, phone volume), recent files and remote-input status.
- **Toolbar actions**: Find Phone (rings at full volume), Lock, Send Clipboard and Send Files, also in the Device menu with keyboard shortcuts.

### 📬 Notification Mirroring & Inline Reply
- Forward Android alerts directly to macOS Notification Center.
- **Inline Replies**: Respond to SMS, WhatsApp, Telegram, or Signal notifications directly from macOS notification banners or the in-app Notifications tab.
- **System Permission Guard**: Proactively detects if macOS notification delivery is disabled in System Settings and displays a quick-action banner to restore permissions.

### ⚡️ Drag-and-Drop File Sharing
- Drop files anywhere in the Tether window (or on the menu bar popover) to send them over local Wi-Fi.
- Files from your phone stream straight to Downloads, with live progress and a transfer log.

### 💬 SMS Sync & Conversation Threads
- Synchronize active SMS threads from your phone.
- Native conversation viewer with iMessage-style bubbles and a responsive bottom composer.

### 🖱️ Remote Input & Presentation Tools
- **Wireless Trackpad**: Control cursor movement, tap-to-click, and two-finger scrolling from your phone's touchscreen.
- **Virtual Laser Pointer**: Full-screen transparent overlay rendering a high-visibility laser dot for presentations and slide decks.
- macOS Accessibility integration for smooth, native input synthesis (`CGEvent`).

### 💻 Remote Shell Commands
- Configure custom shell scripts and automation commands on your Mac and trigger them on demand from your phone.

### 🎛️ Menu Bar Companion (`MenuBarExtra`)
- Monochrome menu bar mark with connected (interlocking rings) and disconnected (severed link) states.
- A Control Center–style popover: device status, Find / Lock / Clipboard / Send File, now playing, nearby devices and pairing requests.

---

## 🔒 Privacy & Security

- **Direct Peer-to-Peer Encryption**: All communication is secured with TLS 1.2 over local network sockets (port 1716 UDP & TCP).
- **Certificate Pinning**: A paired device must present the exact certificate it paired with; a device that only claims a paired device's ID is refused.
- **No Cloud Services or Relays**: Data never leaves your local Wi-Fi network. No telemetry, no third-party servers, and no tracking.
- **Private Identity**: A unique P-256 device certificate, stored in `~/Library/Application Support/Tether` readable only by your user account and loaded in memory (never added to the keychain).

---

## 🛠️ System Requirements

- **Mac**: macOS 15 (Sequoia) or newer, on Apple Silicon or Intel.
- **Phone**: Android device running the official **KDE Connect** app (available on [Google Play](https://play.google.com/store/apps/details?id=org.kde.kdeconnect_tp) or [F-Droid](https://f-droid.org/packages/org.kde.kdeconnect_tp/)).
- **Network**: Both devices must be connected to the same local Wi-Fi network (or reachable via local subnet / VPN like Tailscale).

---

## 📥 Installation

1. Download the latest **`Tether-1.3.1.dmg`** from the [GitHub Releases](https://github.com/subhashhhhhh/Tether/releases) page.
2. Open the downloaded `.dmg` file.
3. Drag **Tether.app** into your **Applications** folder.
4. Launch **Tether**.

### 🛡️ First-Time Launch (Bypassing macOS Gatekeeper)

Because Tether is an open-source indie application not yet notarized through an Apple Developer account (\$99/year), macOS Gatekeeper will protectively block it on first launch. You can allow it using either of the two standard methods:

#### Method 1: System Settings (Recommended — No Terminal Required)
1. Try to open **Tether.app**. When the macOS warning appears (*"Tether cannot be opened because Apple cannot check it for malicious software"*), click **Done** or **Cancel**.
2. Open your Mac's **System Settings** app.
3. Go to **Privacy & Security** and scroll down to the **Security** section.
4. You will see: *"'Tether' was blocked from use because it is not from an identified developer"*.
5. Click **Open Anyway** (authenticate with Touch ID or your Mac password).
6. Click **Open** on the final confirmation prompt.

> **Tip**: You can also **Right-Click** (or **Control-Click**) `Tether.app` in your `/Applications` folder, select **Open**, and then click **Open** in the dialog.

#### Method 2: Terminal (`xattr`)
If macOS marks the downloaded binary as quarantined or says the app is damaged, open **Terminal** and run:
```bash
xattr -cr /Applications/Tether.app
```
This removes the download quarantine attribute. You can now launch Tether normally from Spotlight or Launchpad.

### Pairing Your Phone
1. Open the **KDE Connect** app on your Android device.
2. Under **Available devices**, find your Mac's name and tap **Request Pairing**.
3. A notification banner and pairing card will appear on your Mac. Click **Accept**.
4. Once paired, your phone and Mac will automatically sync whenever they are on the same network!

---

## 🏗️ Building from Source

Tether is written in 100% Swift and SwiftUI with no CocoaPods or external package dependencies.

### Prerequisites
- Xcode 15.0 or newer
- Command Line Tools (`xcode-select --install`)

### Build Commands
```bash
# Clone the repository
git clone https://github.com/subhashhhhhh/Tether.git
cd Tether

# Build the Release configuration
xcodebuild -project Tether.xcodeproj -scheme Tether -configuration Release build

# Run unit tests
xcodebuild test -project Tether.xcodeproj -scheme Tether -destination "platform=macOS"
```

The compiled application bundle will be located at:
`build/Build/Products/Release/Tether.app`

---

## 🏛️ Architecture & Tech Stack

- **UI Framework**: SwiftUI with Apple's `@Observable` observation framework.
- **Design**: Stock SwiftUI controls, grouped forms and a sidebar `List`, system colours and SF Symbols, so the app follows Light/Dark mode, accent colour and accessibility settings.
- **Networking**: BSD sockets with `poll()`-driven I/O and SecureTransport TLS, pinned per device by certificate fingerprint.
- **Concurrency**: `@MainActor` UI state with Swift Concurrency; networking on dedicated dispatch queues.
- **Security**: `openssl` (bundled with macOS) creates the identity once; Apple `Security.framework` loads it and runs TLS.

---

## 📄 License

Tether is distributed under the GNU General Public License v2.0 (GPL-2.0), matching the KDE Connect protocol ecosystem. See the LICENSE file for details.

---

<p align="center">
  Crafted with care for macOS. Enjoy a seamless connection between Mac and Android!
</p>
