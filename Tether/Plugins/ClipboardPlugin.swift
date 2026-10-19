//
//  ClipboardPlugin.swift
//  Tether
//

import AppKit
import Foundation
import UserNotifications

public final class ClipboardPlugin: TetherPlugin, @unchecked Sendable {
    public let supportedPacketTypes = [
        "kdeconnect.clipboard",
        "kdeconnect.clipboard.connect"
    ]

    private var lastChangeCount: Int = 0
    private var lastReceivedContent: String = ""
    private var lastSentContent: String = ""
    private var lastLocalClipboardTimestamp: Int64 = 0
    private var timer: Timer?
    private var activeConnections: [DeviceConnection] = []
    private let lock = NSLock()

    public init() {
        UserDefaults.standard.register(defaults: [
            "TetherNotifyOnClipboardSync": true
        ])
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        self.lastChangeCount = NSPasteboard.general.changeCount
        if let initial = NSPasteboard.general.string(forType: .string), !initial.isEmpty {
            self.lastSentContent = initial
        }
        startMonitoring()
    }

    private func startMonitoring() {
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.checkPasteboard()
            }
        }
    }

    private func checkPasteboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }

        // Suppress echo if this content originated from remote device or was already sent
        if text == lastReceivedContent || text == lastSentContent {
            return
        }

        lastSentContent = text
        lastLocalClipboardTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
        TetherLog("[ClipboardPlugin] Local clipboard changed: \(text.prefix(30))... Broadcasting to paired devices")
        broadcastClipboard(content: text)
    }

    public func onConnected(connection: DeviceConnection) {
        guard let deviceId = connection.peerDeviceInfo?.deviceId,
              let paired = TrustStore.shared.pairedDevice(for: deviceId),
              paired.isClipboardSyncEnabled else {
            return
        }

        lock.withLock {
            activeConnections.removeAll { $0.peerDeviceInfo?.deviceId == deviceId }
            activeConnections.append(connection)
        }
    }

    public func onDisconnected(connection: DeviceConnection) {
        lock.withLock {
            activeConnections.removeAll { $0 === connection }
        }
    }

    public func handlePacket(connection: DeviceConnection, packet: NetworkPacket) {
        guard packet.type == "kdeconnect.clipboard" || packet.type == "kdeconnect.clipboard.connect" else { return }

        guard let deviceId = connection.peerDeviceInfo?.deviceId,
              let paired = TrustStore.shared.pairedDevice(for: deviceId),
              paired.isClipboardSyncEnabled else {
            return
        }

        guard let content = packet.string(for: "content") else { return }

        // If it's a connect packet, verify timestamp to prevent overwriting with stale content
        if packet.type == "kdeconnect.clipboard.connect" {
            let packetTime = packet.int64(for: "timestamp", default: 0)
            if packetTime > 0 && packetTime < lastLocalClipboardTimestamp {
                TetherLog("[ClipboardPlugin] Ignoring connect packet with older timestamp: \(packetTime) vs \(lastLocalClipboardTimestamp)")
                return
            }
        }

        guard content != lastReceivedContent && content != lastSentContent else { return }

        lastReceivedContent = content
        lastSentContent = content
        if packet.type == "kdeconnect.clipboard.connect" {
            let packetTime = packet.int64(for: "timestamp", default: 0)
            if packetTime > 0 {
                lastLocalClipboardTimestamp = packetTime
            }
        } else {
            lastLocalClipboardTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
        }

        DispatchQueue.main.async {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content, forType: .string)
            self.lastChangeCount = NSPasteboard.general.changeCount
            TetherLog("[ClipboardPlugin] Synced clipboard from \(connection.peerDeviceInfo?.deviceName ?? "Device"): \(content.prefix(30))...")
        }

        if packet.type == "kdeconnect.clipboard" {
            let shouldNotify = UserDefaults.standard.object(forKey: "TetherNotifyOnClipboardSync") as? Bool ?? true
            if shouldNotify {
                let deviceName = connection.peerDeviceInfo?.deviceName ?? "Phone"
                let preview = content.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayBody = preview.count > 120 ? "\(preview.prefix(120))…" : preview

                let notif = UNMutableNotificationContent()
                notif.title = "📋 Clipboard Synced"
                notif.subtitle = "From \(deviceName)"
                notif.body = displayBody
                notif.sound = .default
                let req = UNNotificationRequest(
                    identifier: "tether.clipboard.\(UUID().uuidString)",
                    content: notif,
                    trigger: nil
                )
                UNUserNotificationCenter.current().add(req) { error in
                    if let error {
                        TetherLog("[ClipboardPlugin] Error posting notification: \(error)")
                    } else {
                        TetherLog("[ClipboardPlugin] Posted clipboard sync notification for \(deviceName)")
                    }
                }
            }
        }
    }

    public func broadcastClipboard(content: String) {
        let packet = NetworkPacket(
            type: "kdeconnect.clipboard",
            body: ["content": content]
        )
        let targets: [DeviceConnection] = lock.withLock { activeConnections }
        for connection in targets {
            if let deviceId = connection.peerDeviceInfo?.deviceId,
               let paired = TrustStore.shared.pairedDevice(for: deviceId),
               paired.isClipboardSyncEnabled {
                connection.send(packet: packet)
            }
        }
    }
}
