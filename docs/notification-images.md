# Android notification images

Tether displays the image supplied by KDE Connect beside each notification in
its Notifications pane. When an image is ready before delivery, it also adds a
PNG attachment to the native macOS notification. macOS decides how attachments
appear in banners and expanded notifications, depending on system settings.

## What this can and cannot change

The public `UNMutableNotificationContent` API exposes attachments, but no
per-notification application-icon setter. These notifications still belong to
Tether and retain Tether's app icon. An attachment is supplementary content; it
does not replace the originating application's identity.

KDE Connect's Android notification plugin selects the notification's large icon
first, then its small icon, then its legacy icon, and encodes that as PNG. The
large icon can be a contact photo or conversation avatar. There is no separate,
guaranteed application-logo field in this notification packet. Consequently,
Tether must not label the received image an application logo or share it across
all notifications from the same app.

The Android plugin includes `payloadHash` (currently the MD5 of the PNG) even
when it suppresses retransmission of unchanged image bytes for a notification.
Its image privacy option can omit both the bytes and the hash. A packet without
an image hash never inherits previously received artwork.

Sources checked:

- [Apple: UNMutableNotificationContent](https://developer.apple.com/documentation/usernotifications/unmutablenotificationcontent)
- [Apple: UNNotificationAttachment](https://developer.apple.com/documentation/usernotifications/unnotificationattachment)
- [KDE Connect Android: NotificationsPlugin.kt, inspected revision](https://github.com/KDE/kdeconnect-android/blob/d9510469bb3ac5dadc9e9a99e38b693f7431aaff/src/main/java/org/kde/kdeconnect/plugins/notifications/NotificationsPlugin.kt)

## Delivery, cache and fallback

- Reuse Tether's existing TLS payload downloader and certificate pinning.
- Limit notification image payloads to 1 MiB before downloading. Decode only
  PNG, downsample to at most 128 pixels per side, and re-encode as PNG.
- Cache in memory by device ID and explicit image hash, with limits of 128
  entries and 8 MiB. Cache eviction or a restart can leave a hash-only update
  without artwork until Android sends the bytes again. Cache is cleared on
  disconnect; no avatar cache is persisted to disk.
- If a usable image transfer is announced, wait at most one second. Missing,
  malformed, oversized or failed images leave the text and existing actions
  available. If scheduling rejects an attachment, retry the current alert once
  without it. A late image updates only the in-app list, without a second alert.
- Initial silent sync receives artwork without generating banners. Revisions,
  cancellation and disconnect invalidate deferred alerts. A payload from an
  older revision is accepted only if its explicit hash matches current artwork.
- Scope Notification Center identifiers by device as well as Android ID, so two
  phones' similarly named notifications cannot replace or cancel each other.
- Create a disposable file for each attachment, since UserNotifications may
  take ownership of the source. Retain the temporary source until scheduling completes, then remove it. macOS
  manages its own delivered-notification attachments.

There are no downloaded icon packs, package-name guesses, bundle mutations,
private notification APIs or synthetic communication intents.

## Verification

`NotificationImagesTests` covers PNG validation/downsampling, cache isolation
and misses, missing hashes, unusable payload announcements, same-ID devices,
stale payloads, silent updates, cancellation, disconnect, and single delivery
when the timeout and image callback race.

Manual acceptance checks on a paired Android phone:

1. Send new WhatsApp/Telegram notifications with and without contact photos.
   Check the source app name, artwork, reply and dismiss actions in both views.
2. Update a notification with unchanged artwork (hash-only packet), then change
   the conversation avatar. Verify no artwork leaks between conversations.
3. Disable image sharing in Android's KDE Connect privacy options. New packets
   without a hash must show text with no inherited image.
4. Reconnect with active notifications. They should populate silently. Delay or
   fail an image transfer: the alert should appear after at most one second,
   with no repeat banner when the image eventually arrives.
5. Dismiss/update a notification or disconnect before its image arrives. Verify
   no obsolete alert is posted. Repeat with two phones using the same app.
6. Check collapsed and expanded notifications on macOS 15 and 26. The Tether
   app icon is expected to remain. Attachment visibility is controlled by macOS.

These manual checks require a paired device and are not implied by unit tests.

### Local validation (2026-10-19)

On Apple Silicon, macOS 26.6, Xcode 26.2 / Swift 6.2.3:

- Debug app build passed.
- The `TetherTests` target passed: 40 test cases, 6 skipped, 0 failed (53
  passing invocations when parameterized tests are expanded). All eight new
  `NotificationImagesTests` passed, including native attachment creation and
  source-file lifetime. UI tests and paired-phone acceptance checks were not run.
- `git diff --check` passed.

Two pre-existing upstream/toolchain incompatibilities required adjustments in
an isolated build copy: Xcode 26.2 cannot open `objectVersion = 110`, so only the
copy used `objectVersion = 77`; the existing payload-test helper needed an
explicit `UnsafeMutableRawBufferPointer` closure parameter to disambiguate
`Data.withUnsafeMutableBytes`. Neither adjustment is included in this change.
The app sources and new image tests were otherwise compiled unchanged, with
`CODE_SIGNING_ALLOWED=NO`.
