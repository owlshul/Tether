//
//  TrustStore.swift
//  Tether
//

import Foundation
import Combine

public final class TrustStore: ObservableObject, @unchecked Sendable {
    public static let shared = TrustStore()

    @Published public private(set) var pairedDevices: [String: PairedDevice] = [:]

    private let userDefaultsKey = "tether_paired_devices"
    private let lock = NSLock()

    private init() {
        loadDevices()
    }

    /// Build 1.2 shipped with the author's own phone pre-trusted on every install.
    /// It is removed on load so nobody trusts a device they never paired.
    private static let removedPreloadedDeviceIds: Set<String> = ["5bbcb3e152d34b9597997d39ca4587ce"]

    private func loadDevices() {
        let stored = Self.decode(key: userDefaultsKey) ?? Self.decode(key: "kdeconnect_paired_devices") ?? []
        let kept = stored.filter { !Self.removedPreloadedDeviceIds.contains($0.deviceId) }

        self.pairedDevices = Dictionary(kept.map { ($0.deviceId, $0) }, uniquingKeysWith: { _, latest in latest })

        // Persist when migrating from the legacy key or when a preloaded entry was dropped.
        if kept.count != stored.count || UserDefaults.standard.data(forKey: userDefaultsKey) == nil {
            saveDevices()
        }
    }

    private static func decode(key: String) -> [PairedDevice]? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([PairedDevice].self, from: data),
              !list.isEmpty else { return nil }
        return list
    }

    private func saveDevices() {
        let list = Array(pairedDevices.values)
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    public func isTrusted(deviceId: String) -> Bool {
        lock.withLock {
            pairedDevices[deviceId] != nil
        }
    }

    public func pairedDevice(for deviceId: String) -> PairedDevice? {
        lock.withLock {
            pairedDevices[deviceId]
        }
    }

    public func add(device: PairedDevice) {
        lock.withLock {
            self.pairedDevices[device.deviceId] = device
            self.saveDevices()
        }
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    public func remove(deviceId: String) {
        lock.withLock {
            self.pairedDevices.removeValue(forKey: deviceId)
            self.saveDevices()
        }
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    public func updateLastSeen(deviceId: String) {
        lock.withLock {
            guard var device = self.pairedDevices[deviceId] else { return }
            device.lastSeenDate = Date()
            self.pairedDevices[deviceId] = device
            self.saveDevices()
        }
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    public func updateSettings(deviceId: String, clipboard: Bool, notifications: Bool) {
        lock.withLock {
            guard var device = self.pairedDevices[deviceId] else { return }
            device.isClipboardSyncEnabled = clipboard
            device.isNotificationSyncEnabled = notifications
            self.pairedDevices[deviceId] = device
            self.saveDevices()
        }
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
}
