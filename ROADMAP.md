# Roadmap

What Tether does today, what's being built next, and what isn't possible.

Everything here works with the regular **KDE Connect** app on Android from Google Play or F-Droid. Tether never needs a custom phone app, so features that would need one are listed under [Not possible](#not-possible) rather than promised.

Planned features have no dates. Ideas and bug reports are welcome in [Issues](https://github.com/subhashhhhhh/Tether/issues).

## Available now

As of Tether 1.6.

### Connecting
- [x] Finds your phone automatically on the same Wi-Fi
- [x] Finds your phone over [Tailscale](https://tailscale.com), so it works away from home
- [x] Connect by IP address or Tailscale name
- [x] Pairing with certificate pinning, so only your phone can connect as your phone
- [x] Several phones or tablets at once
- [x] Notices within about 15 seconds when a phone leaves Wi-Fi or goes out of range

### Notifications and calls
- [x] Phone notifications in macOS Notification Center
- [x] Reply to messages (SMS, WhatsApp, Telegram, Signal and others) from the banner
- [x] Dismissing on the Mac dismisses on the phone
- [x] Incoming and missed call notifications

### Messages
- [x] SMS conversations sync to the Mac
- [x] Read threads and send replies

### Files and clipboard
- [x] Send files by dropping them on the window or the menu bar popover
- [x] **Share › Tether** in Finder, Photos, Safari and other apps, with a chooser when several phones are connected
- [x] Several files at once, of any size
- [x] Files from the phone land in Downloads, with progress
- [x] Clipboard sync both ways (text)
- [x] **Your phone as a drive.** While it's connected, the phone is mounted in Finder as a drive named after it, with an eject button. Files are read from the phone as you open them, so videos play right away. Works over Wi-Fi and Tailscale, with an optional ADB mode, and needs no administrator password or system extension. Eject and mount it from the Files tab.

### Media and controls
- [x] See what's playing on the phone, with album art and playback controls
- [x] Set the phone's media volume while something is playing
- [x] **Find Phone** rings it at full volume
- [x] Battery level, charging state, network type and signal strength

### Using your phone as an input device
- [x] Trackpad and keyboard for the Mac (KDE Connect's Remote Input)
- [x] Presentation remote with an on-screen laser pointer
- [x] Run commands you set up on the Mac from the phone

### The app
- [x] Menu bar popover and a main window, with Liquid Glass on macOS 26 and translucent materials on macOS 15
- [x] Light and Dark mode, accent colour, and a Reduce Motion setting
- [x] Updates itself, after checking each update's signature
- [x] Homebrew install: `brew install --cask subhashhhhhh/tether/tether`
- [x] Apple Silicon and Intel, macOS 15 Sequoia or later

## Planned

### Coming next
- [ ] **Copy verification codes.** One-time codes in texts and notifications get a "Copy code" button, like Messages on an iPhone.
- [ ] **Contact names and photos.** Show names and photos from your phone's contacts in Messages and call notifications instead of bare numbers.
- [ ] **Better call notifications.** Caller photo, a button to silence the ringer, and pausing whatever is playing on the Mac.
- [ ] **Ring your Mac from your phone.** Answer KDE Connect's "Ring" button on the phone by playing a sound on the Mac.
- [ ] **Pairing fixes.** Let a phone that forgot the Mac ask to pair again, and check pairing requests' timestamps like desktop KDE Connect does.

### Later
- [ ] **Shortcuts and Siri.** Actions such as "Send file to phone", "Ring my phone", "Send a text" and "Get phone battery" for the Shortcuts app.
- [ ] **Run Mac Shortcuts from your phone.** List your macOS Shortcuts in KDE Connect's Run Command on the phone.
- [ ] **Lock the Mac when you walk away.** Optional: lock when the phone disconnects.
- [ ] **Battery alerts.** "Phone is at 15%" and "Phone fully charged".
- [ ] **Widgets.** Battery and what's playing on the desktop and in Notification Center.
- [ ] **Search messages in Spotlight.**
- [ ] **Control the Mac's volume from your phone**, using KDE Connect's volume panel on the phone.
- [ ] **Control Mac media from your phone.** Music and Spotify at first; see the note under [Not possible](#not-possible).
- [ ] **Type on your phone from the Mac keyboard**, using KDE Connect's keyboard on the phone.
- [ ] **Phone as a drawing tablet**, with pressure, using KDE Connect's Digitizer.

## Not possible

These would need features the KDE Connect Android app doesn't have, or that macOS doesn't allow.

- **Lock the phone from the Mac.** KDE Connect for Android has no remote lock.
- **Unlock the Mac with the phone.** That needs a dedicated phone app; locking is possible (see Planned).
- **Change ringer or notification volume.** The phone only accepts volume changes for an active media player.
- **Show Mac notifications on the phone.** macOS doesn't let apps read other apps' notifications.
- **Control every Mac media app from the phone.** Since macOS 15.4, apps can't control the system-wide Now Playing, so this is limited to apps Tether can talk to directly.
- **Clipboard images and files.** KDE Connect's clipboard sync is text only. Use Share or drag and drop instead.
