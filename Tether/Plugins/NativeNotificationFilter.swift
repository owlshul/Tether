import AppKit

/// Let the native WhatsApp app deliver its own alerts while it is running,
/// including when hidden or minimized. The mirrored list remains available.
enum NativeNotificationFilter {
    static func shouldSuppress(_ item: PhoneNotification) -> Bool {
        guard isWhatsApp(appName: item.appName, notificationId: item.id) else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: "net.whatsapp.WhatsApp")
            .contains { !$0.isTerminated }
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
