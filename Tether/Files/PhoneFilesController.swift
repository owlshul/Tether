//
//  PhoneFilesController.swift
//  Tether
//
//  Mounts each connected phone as a drive in Finder (see PhoneMount), serving
//  it over SFTP, or ADB when the user chose it and it's reachable.
//

import AppKit
import Foundation

enum PhoneFilesMethod: String, CaseIterable, Identifiable {
    case sftp
    case adb

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sftp: "KDE Connect (SFTP)"
        case .adb: "ADB (wireless debugging)"
        }
    }
}

@MainActor
@Observable
final class PhoneFilesController {
    static let shared = PhoneFilesController()

    private static let enabledKey = "tether_files_enabled"

    /// Mounts connected phones as drives.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            Task { await syncMounts() }
        }
    }

    /// When ADB is chosen but can't be used, why; SFTP is used meanwhile.
    private(set) var adbProblem: [String: String] = [:]
    /// Why a phone couldn't be mounted, if it couldn't.
    private(set) var mountError: [String: String] = [:]
    /// Phones currently mounted.
    private(set) var mountedDevices = Set<String>()

    private var paired: [String: String] = [:]
    private var connected = Set<String>()
    private var routers: [String: PhoneFilesRouter] = [:]
    private var mounts: [String: PhoneMount] = [:]
    private var busy = Set<String>()
    private var started = false

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func start() {
        guard !started else { return }
        started = true
        PhoneMount.cleanUpStaleMounts()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated {
                for mount in PhoneFilesController.shared.mounts.values { mount.unmountNow() }
            }
        }
    }

    // MARK: - Settings per phone

    func method(for deviceId: String) -> PhoneFilesMethod {
        UserDefaults.standard.string(forKey: "tether_files_method_\(deviceId)").flatMap(PhoneFilesMethod.init) ?? .sftp
    }

    func setMethod(_ method: PhoneFilesMethod, for deviceId: String) {
        UserDefaults.standard.set(method.rawValue, forKey: "tether_files_method_\(deviceId)")
        reconfigure(deviceId)
    }

    func adbAddress(for deviceId: String) -> String {
        UserDefaults.standard.string(forKey: "tether_files_adb_\(deviceId)") ?? ""
    }

    func setADBAddress(_ address: String, for deviceId: String) {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(trimmed, forKey: "tether_files_adb_\(deviceId)")
        reconfigure(deviceId)
    }

    var isADBInstalled: Bool { ADBTransport.executable != nil }

    private func reconfigure(_ deviceId: String) {
        adbProblem[deviceId] = nil
        guard let router = routers[deviceId] else { return }
        let adb = adbTransport(for: deviceId)
        Task { await router.setADB(adb) }
    }

    private func adbTransport(for deviceId: String) -> ADBTransport? {
        guard method(for: deviceId) == .adb else { return nil }
        let address = adbAddress(for: deviceId)
        guard address.contains(":") else {
            adbProblem[deviceId] = "Enter the address and port from Wireless debugging."
            return nil
        }
        guard isADBInstalled else {
            adbProblem[deviceId] = ADBError.notInstalled.localizedDescription
            return nil
        }
        return ADBTransport(address: address)
    }

    fileprivate func reportADB(_ deviceId: String, problem: String?) {
        if adbProblem[deviceId] != problem { adbProblem[deviceId] = problem }
    }

    // MARK: - Devices

    /// Called whenever the device list changes.
    func update(paired newPaired: [String: String], connected newConnected: Set<String>) {
        guard newPaired != paired || newConnected != connected else { return }
        for deviceId in paired.keys where newPaired[deviceId] == nil {
            // Unpaired: forget its server's pinned key too.
            UserDefaults.standard.removeObject(forKey: SFTPTransport.hostKeyDefaultsKey(deviceId))
            routers.removeValue(forKey: deviceId)
        }
        paired = newPaired
        connected = newConnected
        Task { await syncMounts() }
    }

    /// Mounts connected, paired phones and unmounts the rest.
    private func syncMounts() async {
        let wanted = isEnabled ? connected.filter { paired[$0] != nil } : []
        for deviceId in Array(mounts.keys) where !wanted.contains(deviceId) || mounts[deviceId]?.name != Self.mountName(paired[deviceId]) {
            await unmount(deviceId)
        }
        for deviceId in wanted where mounts[deviceId] == nil {
            await mount(deviceId)
        }
    }

    private static func mountName(_ name: String?) -> String {
        (name ?? "Phone").replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
    }

    private func router(for deviceId: String) -> PhoneFilesRouter {
        if let router = routers[deviceId] { return router }
        let router = PhoneFilesRouter(
            deviceId: deviceId,
            sftp: SFTPTransport(deviceId: deviceId, plugin: TetherService.shared.sftpPlugin),
            adb: adbTransport(for: deviceId)
        )
        routers[deviceId] = router
        return router
    }

    private func mount(_ deviceId: String) async {
        guard !busy.contains(deviceId), let name = paired[deviceId] else { return }
        busy.insert(deviceId)
        defer { busy.remove(deviceId) }

        let mount = PhoneMount(deviceId: deviceId, name: name, router: router(for: deviceId))
        do {
            try await mount.mount()
            mounts[deviceId] = mount
            mountedDevices.insert(deviceId)
            mountError[deviceId] = nil
        } catch {
            TetherLog("[Files] \(error.localizedDescription)")
            mountError[deviceId] = error.localizedDescription
        }
    }

    private func unmount(_ deviceId: String) async {
        guard let mount = mounts.removeValue(forKey: deviceId) else { return }
        mountedDevices.remove(deviceId)
        await mount.unmount()
        if let router = routers[deviceId] { await router.close() }
    }

    /// Opens the phone's drive in Finder. Through `open` on another thread:
    /// Tether's main thread must never wait on the drive, because answering
    /// the drive can need the main thread (e.g. to fetch SFTP login details).
    func showInFinder(_ deviceId: String) {
        guard let path = mounts[deviceId]?.mountPoint.path else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [path]
            try? process.run()
        }
    }
}

/// Picks SFTP or ADB for each request. If ADB was chosen but stops answering
/// (its port changes whenever wireless debugging restarts), it falls back to
/// SFTP and says why in Settings.
actor PhoneFilesRouter {
    private let deviceId: String
    private let sftp: SFTPTransport
    private var adb: ADBTransport?

    init(deviceId: String, sftp: SFTPTransport, adb: ADBTransport?) {
        self.deviceId = deviceId
        self.sftp = sftp
        self.adb = adb
    }

    func setADB(_ transport: ADBTransport?) { adb = transport }

    func run<T: Sendable>(_ operation: (any PhoneFileTransport) async throws -> T) async throws -> T {
        if let adb {
            do {
                let result = try await operation(adb)
                await report(nil)
                return result
            } catch let error as ADBError {
                if case .failed = error { throw error }
                await report(error.localizedDescription + " Using KDE Connect instead.")
            }
        }
        return try await operation(sftp)
    }

    private func report(_ problem: String?) async {
        let deviceId = deviceId
        await MainActor.run { PhoneFilesController.shared.reportADB(deviceId, problem: problem) }
    }

    func close() async {
        await sftp.close()
        await adb?.close()
    }
}

