//
//  NotificationPlugin.swift
//  Tether
//

import Foundation
import Combine
import UserNotifications

/// A notification currently showing on the phone, mirrored for the in-app list.
public struct PhoneNotification: Identifiable, Hashable, Sendable {
    public let id: String
    public let deviceId: String
    public let appName: String
    public let title: String
    public let text: String
    public let date: Date
    /// Present when the phone accepts an inline reply (messaging apps).
    public let replyId: String?
    public let isDismissable: Bool
}

public final class NotificationPlugin: NSObject, ObservableObject, TetherPlugin, UNUserNotificationCenterDelegate, @unchecked Sendable {
    /// Active phone notifications per device, newest first.
    @Published public private(set) var notifications: [String: [PhoneNotification]] = [:]

    public let supportedPacketTypes = [
        "kdeconnect.notification",
        "kdeconnect.notification.request",
        "kdeconnect.notification.reply"
    ]

    private var activeConnections: [String: DeviceConnection] = [:]

    public override init() {
        super.init()
        setupNotificationCategories()
        UNUserNotificationCenter.current().delegate = self
        requestPermission()
    }

    private func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            TetherLog("[NotificationPlugin] Notification authorization granted: \(granted)\(error != nil ? ", error: \(error!)" : "")")
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            TetherLog("[NotificationPlugin] Current notification authorization status: \(settings.authorizationStatus.rawValue) (0=notDetermined, 1=denied, 2=authorized, 3=provisional)")
        }
    }

    private func setupNotificationCategories() {
        let replyAction = UNTextInputNotificationAction(
            identifier: "TETHER_REPLY_ACTION",
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type a reply..."
        )

        let dismissAction = UNNotificationAction(
            identifier: "TETHER_DISMISS_ACTION",
            title: "Dismiss on Phone",
            options: [.destructive]
        )

        let category = UNNotificationCategory(
            identifier: "TETHER_NOTIFICATION_CATEGORY",
            actions: [replyAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        let acceptAction = UNNotificationAction(
            identifier: "TETHER_PAIR_ACCEPT_ACTION",
            title: "Accept",
            options: [.foreground]
        )

        let rejectAction = UNNotificationAction(
            identifier: "TETHER_PAIR_REJECT_ACTION",
            title: "Reject",
            options: [.destructive]
        )

        let pairCategory = UNNotificationCategory(
            identifier: "TETHER_PAIR_REQUEST_CATEGORY",
            actions: [acceptAction, rejectAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category, pairCategory])
    }

    public func onConnected(connection: DeviceConnection) {
        guard let deviceId = connection.peerDeviceInfo?.deviceId,
              let paired = TrustStore.shared.pairedDevice(for: deviceId),
              paired.isNotificationSyncEnabled else {
            return
        }
        activeConnections[deviceId] = connection

        // Request active notifications from remote phone
        let requestPacket = NetworkPacket(
            type: "kdeconnect.notification.request",
            body: ["request": true]
        )
        connection.send(packet: requestPacket)
    }

    public func onDisconnected(connection: DeviceConnection) {
        if let deviceId = connection.peerDeviceInfo?.deviceId {
            if activeConnections[deviceId] === connection {
                activeConnections.removeValue(forKey: deviceId)
                // The phone re-sends everything it is still showing on reconnect.
                DispatchQueue.main.async {
                    self.notifications[deviceId] = nil
                }
            }
        }
    }

    // MARK: - Actions

    /// Sends an inline reply for a notification that offered one.
    public func reply(to notification: PhoneNotification, text: String) {
        guard let replyId = notification.replyId,
              let connection = activeConnections[notification.deviceId] else { return }
        connection.send(packet: NetworkPacket(
            type: "kdeconnect.notification.reply",
            body: ["requestReplyId": replyId, "message": text]
        ))
        TetherLog("[NotificationPlugin] Sent notification reply to \(notification.deviceId)")
    }

    /// Asks the phone to dismiss a notification; the phone confirms with a cancel packet.
    public func dismiss(_ notification: PhoneNotification) {
        if let connection = activeConnections[notification.deviceId] {
            connection.send(packet: NetworkPacket(
                type: "kdeconnect.notification.request",
                body: ["cancel": notification.id]
            ))
        }
        removeLocally(id: notification.id, deviceId: notification.deviceId)
    }

    private func removeLocally(id: String, deviceId: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        DispatchQueue.main.async {
            self.notifications[deviceId]?.removeAll { $0.id == id }
        }
    }

    public func handlePacket(connection: DeviceConnection, packet: NetworkPacket) {
        guard packet.type == "kdeconnect.notification" else { return }

        guard let deviceId = connection.peerDeviceInfo?.deviceId,
              let paired = TrustStore.shared.pairedDevice(for: deviceId),
              paired.isNotificationSyncEnabled else {
            return
        }

        let isCancel = packet.bool(for: "isCancel")
        guard let notifId = packet.string(for: "id") else { return }

        if isCancel {
            removeLocally(id: notifId, deviceId: deviceId)
            return
        }

        let appName = packet.string(for: "appName") ?? "Notification"
        let title = packet.string(for: "title") ?? ""
        let text = packet.string(for: "text") ?? (packet.string(for: "ticker") ?? "")
        let silent = packet.bool(for: "silent")
        let replyId = packet.string(for: "requestReplyId").flatMap { $0.isEmpty ? nil : $0 }
        let timeMillis = packet.int64(for: "time")

        let item = PhoneNotification(
            id: notifId,
            deviceId: deviceId,
            appName: appName,
            title: title,
            text: text,
            date: timeMillis > 0 ? Date(timeIntervalSince1970: TimeInterval(timeMillis) / 1000) : Date(),
            replyId: replyId,
            isDismissable: packet.bool(for: "isClearable", default: true)
        )
        DispatchQueue.main.async {
            var list = self.notifications[deviceId] ?? []
            list.removeAll { $0.id == notifId }
            list.insert(item, at: 0)
            list.sort { $0.date > $1.date }
            self.notifications[deviceId] = list
        }

        // Silent notifications are ones the phone already showed (e.g. the
        // initial sync after connecting); list them but do not re-alert.
        if silent { return }

        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? appName : "\(appName): \(title)"
        content.body = text
        content.sound = .default
        content.categoryIdentifier = "TETHER_NOTIFICATION_CATEGORY"
        content.userInfo = [
            "deviceId": deviceId,
            "notifId": notifId,
            "replyId": replyId ?? ""
        ]

        let request = UNNotificationRequest(
            identifier: notifId,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                TetherLog("[NotificationPlugin] Failed to display notification: \(error)")
            }
        }
    }

    // UNUserNotificationCenterDelegate
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.categoryIdentifier == UpdateController.notificationCategory {
            Task { @MainActor in UpdateController.shared.showWindow() }
            completionHandler()
            return
        }

        if response.actionIdentifier == "TETHER_PAIR_ACCEPT_ACTION" {
            DispatchQueue.main.async {
                TetherService.shared.acceptIncomingPairRequest()
            }
            completionHandler()
            return
        } else if response.actionIdentifier == "TETHER_PAIR_REJECT_ACTION" {
            DispatchQueue.main.async {
                TetherService.shared.rejectIncomingPairRequest()
            }
            completionHandler()
            return
        }

        let userInfo = response.notification.request.content.userInfo
        guard let deviceId = userInfo["deviceId"] as? String,
              let connection = activeConnections[deviceId] else {
            completionHandler()
            return
        }

        if let textResponse = response as? UNTextInputNotificationResponse,
           let replyId = userInfo["replyId"] as? String, !replyId.isEmpty {
            let replyText = textResponse.userText
            let replyPacket = NetworkPacket(
                type: "kdeconnect.notification.reply",
                body: [
                    "requestReplyId": replyId,
                    "message": replyText
                ]
            )
            connection.send(packet: replyPacket)
            TetherLog("[NotificationPlugin] Sent notification reply to \(deviceId): \(replyText)")
        } else if response.actionIdentifier == "TETHER_DISMISS_ACTION" {
            if let notifId = userInfo["notifId"] as? String {
                let dismissPacket = NetworkPacket(
                    type: "kdeconnect.notification.request",
                    body: ["cancel": notifId]
                )
                connection.send(packet: dismissPacket)
                TetherLog("[NotificationPlugin] Sent dismiss request for \(notifId)")
            }
        }

        completionHandler()
    }
}
