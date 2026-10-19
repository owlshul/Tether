//
//  TelephonyPlugin.swift
//  Tether
//

import Foundation
import UserNotifications

/// Incoming call and messaging events from the phone.
///
/// The peer sends `kdeconnect.telephony` with `event` set to `ringing`,
/// `missedCall`, `talking` or `sms`, plus `phoneNumber`, and `contactName` and
/// a JPEG `phoneThumbnail` when the phone knows the caller. `isCancel` marks a
/// previously announced event as no longer relevant.
public final class TelephonyPlugin: ObservableObject, TetherPlugin, @unchecked Sendable {
    static let requestMuteType = "kdeconnect.telephony.request_mute"
    static let callCategory = "TETHER_CALL_CATEGORY"
    static let muteAction = "TETHER_MUTE_RINGER_ACTION"

    public let supportedPacketTypes = ["kdeconnect.telephony"]

    @Published public private(set) var ringingCalls: [String: String] = [:]

    public init() {}

    public func onConnected(connection: DeviceConnection) {}
    public func onDisconnected(connection: DeviceConnection) {
        if let id = connection.peerDeviceInfo?.deviceId {
            DispatchQueue.main.async {
                self.ringingCalls.removeValue(forKey: id)
            }
        }
    }

    public func handlePacket(connection: DeviceConnection, packet: NetworkPacket) {
        guard packet.type == "kdeconnect.telephony",
              let deviceId = connection.peerDeviceInfo?.deviceId else { return }

        let event = packet.string(for: "event") ?? ""
        let identifier = "tether-telephony-\(deviceId)-\(event)"
        let isCall = event == "ringing" || event == "talking"

        // A cancel retracts what was posted for this event; for a call, it ended.
        if packet.bool(for: "isCancel") {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
            if isCall {
                Task { @MainActor in CallMediaPauser.shared.callEnded("\(deviceId)/\(event)") }
                DispatchQueue.main.async {
                    self.ringingCalls.removeValue(forKey: deviceId)
                }
            }
            return
        }
        if isCall {
            Task { @MainActor in CallMediaPauser.shared.callStarted("\(deviceId)/\(event)") }
        }

        // The phone's own contact name wins; otherwise Tether's copy of the
        // contacts; otherwise the number.
        let number = packet.string(for: "phoneNumber")
        let contact = number.flatMap { TetherService.shared.contactsPlugin.contactNow(for: $0, on: deviceId) }
        let name = packet.string(for: "contactName").flatMap { $0.isEmpty ? nil : $0 } ?? contact?.name
        let who = name ?? number ?? "Unknown number"
        let photo = packet.string(for: "phoneThumbnail").flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
            ?? contact?.photo

        let content = UNMutableNotificationContent()
        switch event {
        case "ringing":
            content.title = who
            content.subtitle = "Incoming call"
            if name != nil, let number { content.body = number }
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = Self.callCategory
            content.userInfo = ["deviceId": deviceId]
            DispatchQueue.main.async {
                self.ringingCalls[deviceId] = who
            }
        case "missedCall":
            content.title = who
            content.subtitle = "Missed call"
            if name != nil, let number { content.body = number }
            content.sound = .default
            DispatchQueue.main.async {
                self.ringingCalls.removeValue(forKey: deviceId)
            }
        case "talking":
            content.title = who
            content.subtitle = "Call in progress"
            DispatchQueue.main.async {
                self.ringingCalls.removeValue(forKey: deviceId)
            }
        case "sms":
            content.title = "Message from \(who)"
            content.body = packet.string(for: "messageBody") ?? ""
        default:
            TetherLog("[TelephonyPlugin] Ignoring unknown telephony event '\(event)'")
            return
        }
        if let photo, let attachment = Self.attachment(photo) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                TetherLog("[TelephonyPlugin] Failed to post notification: \(error)")
            }
        }
    }

    public func muteRinger(deviceId: String) {
        Self.muteRinger(deviceId: deviceId)
        DispatchQueue.main.async {
            self.ringingCalls.removeValue(forKey: deviceId)
        }
    }

    /// Asks the phone to silence its ringer, from the incoming-call notification.
    public static func muteRinger(deviceId: String) {
        guard let connection = TetherService.shared.connection(for: deviceId) else { return }
        connection.send(packet: NetworkPacket(type: requestMuteType))
        TetherLog("[TelephonyPlugin] Asked the phone to mute its ringer")
    }

    /// The caller's photo as a notification attachment. The notification
    /// center moves the file into its own store.
    private static func attachment(_ photo: Data) -> UNNotificationAttachment? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tether-caller-\(UUID().uuidString).jpg")
        guard (try? photo.write(to: url)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "photo", url: url, options: nil)
    }
}
