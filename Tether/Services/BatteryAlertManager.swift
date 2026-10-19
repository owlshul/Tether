//
//  BatteryAlertManager.swift
//  Tether
//
//  Monitors connected device battery levels and sends smart native macOS
//  notifications for low battery (<=15%) and full charge (100%).
//

import Foundation
import UserNotifications

public final class BatteryAlertManager: @unchecked Sendable {
    public static let shared = BatteryAlertManager()

    public static let lowAlertKey = "TetherBatteryLowAlertEnabled"
    public static let fullAlertKey = "TetherBatteryFullAlertEnabled"
    public static let lowThresholdKey = "TetherBatteryLowAlertThreshold"

    private var didAlertLow: [String: Bool] = [:]
    private var didAlertFull: [String: Bool] = [:]
    private let lock = NSLock()

    private init() {
        UserDefaults.standard.register(defaults: [
            Self.lowAlertKey: true,
            Self.fullAlertKey: true,
            Self.lowThresholdKey: 15
        ])
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    public func evaluate(deviceId: String, deviceName: String, charge: Int, isCharging: Bool, thresholdEvent: Int) {
        lock.lock()
        defer { lock.unlock() }

        let defaults = UserDefaults.standard
        let lowAlertEnabled = defaults.bool(forKey: Self.lowAlertKey)
        let fullAlertEnabled = defaults.bool(forKey: Self.fullAlertKey)
        let rawThreshold = defaults.integer(forKey: Self.lowThresholdKey)
        let lowThreshold = rawThreshold > 0 ? rawThreshold : 15

        // Low Battery Alert: fires when battery is <= threshold and not charging
        if lowAlertEnabled && !isCharging && charge <= lowThreshold && charge >= 0 {
            if didAlertLow[deviceId] != true {
                didAlertLow[deviceId] = true
                postLowBatteryNotification(deviceName: deviceName, charge: charge)
            }
        } else if isCharging || charge > (lowThreshold + 5) {
            // Reset low battery alert once phone is plugged in or charge rises safely
            didAlertLow[deviceId] = false
        }

        // Full Charge Alert: fires when battery reaches 100% (or event 2) while plugged in
        if fullAlertEnabled && isCharging && (charge >= 100 || thresholdEvent == 2) {
            if didAlertFull[deviceId] != true {
                didAlertFull[deviceId] = true
                postFullChargeNotification(deviceName: deviceName)
            }
        } else if !isCharging || charge < 95 {
            // Reset full charge alert once unplugged or charge drops below 95%
            didAlertFull[deviceId] = false
        }
    }

    private func postLowBatteryNotification(deviceName: String, charge: Int) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Battery Low (\(charge)%)"
        content.body = "\(deviceName) battery is running low. Connect it to a charger."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "tether.battery.low.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                TetherLog("[BatteryAlert] Error posting low battery notification: \(error)")
            } else {
                TetherLog("[BatteryAlert] Posted low battery notification for \(deviceName) (\(charge)%)")
            }
        }
    }

    private func postFullChargeNotification(deviceName: String) {
        let content = UNMutableNotificationContent()
        content.title = "⚡️ Battery Fully Charged (100%)"
        content.body = "\(deviceName) has finished charging. You can unplug it now."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "tether.battery.full.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                TetherLog("[BatteryAlert] Error posting full charge notification: \(error)")
            } else {
                TetherLog("[BatteryAlert] Posted full charge notification for \(deviceName)")
            }
        }
    }

    public func reset(for deviceId: String) {
        lock.lock()
        defer { lock.unlock() }
        didAlertLow.removeValue(forKey: deviceId)
        didAlertFull.removeValue(forKey: deviceId)
    }
}
