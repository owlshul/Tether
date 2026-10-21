import AppKit
import UserNotifications

/// Let the native WhatsApp app deliver its own alerts while it is running,
/// including when hidden or minimized. The mirrored list remains available.
enum NativeNotificationFilter {
    static let whatsAppBundleIdentifier = "net.whatsapp.WhatsApp"

    static func shouldSuppress(_ item: PhoneNotification) -> Bool {
        guard isWhatsApp(appName: item.appName, notificationId: item.id) else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: whatsAppBundleIdentifier)
            .contains { !$0.isTerminated }
    }

    /// Only a click on the notification body opens the native app. Reply,
    /// dismiss and code-copy buttons retain their original behavior.
    static func applicationForDefaultAction(_ action: String, appName: String, notificationId: String) -> String? {
        guard action == UNNotificationDefaultActionIdentifier,
              isWhatsApp(appName: appName, notificationId: notificationId) else { return nil }
        return whatsAppBundleIdentifier
    }

    static func isWhatsApp(appName: String, notificationId: String) -> Bool {
        // KDE Connect normally forwards StatusBarNotification.key:
        // userId|packageName|notificationId|tag|uid. Prefer its package over a
        // display name, so similarly named apps / WhatsApp Business stay distinct.
        let fields = notificationId.split(separator: "|", omittingEmptySubsequences: false)
        if fields.count >= 5, Int(fields[0]) != nil, Int(fields[2]) != nil {
            return fields[1] == "com.whatsapp"
        }
        // Older / compatible senders can use opaque IDs with only appName.
        return appName.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("WhatsApp") == .orderedSame
    }
}
