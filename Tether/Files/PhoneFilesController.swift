//
//  PhoneFilesController.swift
//  Tether
//
//  Puts each paired phone in Finder's sidebar (a File Provider domain per
//  phone) and serves the TetherFiles extension: whenever a phone is
//  connected, Tether connects to the extension's service and answers its file
//  requests over SFTP, or ADB when the user chose it and it's reachable.
//

import AppKit
import FileProvider
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

    /// Shows paired phones in Finder.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            Task { await syncDomains() }
        }
    }

    /// When ADB is chosen but can't be used, why; SFTP is used meanwhile.
    private(set) var adbProblem: [String: String] = [:]
    /// The last error setting up Finder, if any.
    private(set) var setupError: String?

    private var paired: [String: String] = [:]
    private var connected = Set<String>()
    private var routers: [String: PhoneFilesRouter] = [:]
    private var links: [String: NSXPCConnection] = [:]
    private var attaching = Set<String>()
    private var observer: NSObjectProtocol?
    private var changeCheck: Task<Void, Never>?

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: PhoneFiles.needsBackendNotification, object: nil, queue: .main
        ) { notification in
            guard let deviceId = notification.object as? String else { return }
            // The extension has no working link, whatever we think: connect again.
            Task { @MainActor in PhoneFilesController.shared.attach(deviceId, replacing: true) }
        }
        // There's no change feed from the phone: once a minute, have Finder
        // re-read the phone folders it has open. This wakes the extension.
        changeCheck = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                for deviceId in self.links.keys { self.signalChanges(deviceId) }
            }
        }
    }

    private func signalChanges(_ deviceId: String) {
        NSFileProviderManager(for: domain(deviceId))?.signalEnumerator(for: .workingSet) { _ in }
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
        Task {
            await router.setADB(adb)
            self.refreshFinder(deviceId)
        }
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
        let pairedChanged = newPaired != paired
        let wentOffline = connected.subtracting(newConnected)
        let cameOnline = newConnected.subtracting(connected)
        paired = newPaired
        connected = newConnected

        for deviceId in wentOffline { detach(deviceId) }
        if pairedChanged {
            for deviceId in routers.keys where newPaired[deviceId] == nil {
                // Unpaired: forget its server's pinned key too.
                UserDefaults.standard.removeObject(forKey: SFTPTransport.hostKeyDefaultsKey(deviceId))
            }
            Task { await syncDomains() }
        }
        for deviceId in cameOnline { attach(deviceId) }
    }

    private func domain(_ deviceId: String) -> NSFileProviderDomain {
        NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(deviceId), displayName: paired[deviceId] ?? "Phone")
    }

    /// Adds a Finder location for each paired phone and removes any others.
    private func syncDomains() async {
        do {
            let existing = try await NSFileProviderManager.domains()
            let wanted = isEnabled ? paired : [:]
            for domain in existing where wanted[domain.identifier.rawValue] != domain.displayName {
                try await NSFileProviderManager.remove(domain)
            }
            let kept = Set(existing.filter { wanted[$0.identifier.rawValue] == $0.displayName }.map(\.identifier.rawValue))
            for deviceId in wanted.keys where !kept.contains(deviceId) {
                try await NSFileProviderManager.add(domain(deviceId))
                TetherLog("[Files] Added \(wanted[deviceId] ?? deviceId) to Finder")
            }
            setupError = nil
            for deviceId in connected where wanted[deviceId] != nil { attach(deviceId) }
        } catch {
            TetherLog("[Files] Couldn't update Finder locations: \(error)")
            setupError = error.localizedDescription
        }
    }

    // MARK: - Serving the extension

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

    /// Connects to the extension for this phone, so Finder can reach it.
    /// `replacing` drops an existing link first: the extension can restart
    /// without our side of the connection noticing.
    func attach(_ deviceId: String, replacing: Bool = false) {
        guard isEnabled, connected.contains(deviceId), paired[deviceId] != nil,
              let manager = NSFileProviderManager(for: domain(deviceId)) else {
            if replacing { TetherLog("[Files] Finder asked for \(deviceId), but it isn't connected or paired") }
            return
        }
        guard !attaching.contains(deviceId) else { return }
        if replacing {
            links.removeValue(forKey: deviceId)?.invalidate()
        } else if links[deviceId] != nil {
            return
        }
        attaching.insert(deviceId)
        let backend = PhoneFilesBackendService(router: router(for: deviceId))

        Task {
            defer { attaching.remove(deviceId) }
            do {
                guard let service = try await manager.service(named: NSFileProviderServiceName(PhoneFiles.serviceName), for: .rootContainer) else {
                    throw PhoneFileError.notConnected("The Finder extension didn't offer its service.")
                }
                let connection = try await service.fileProviderConnection()
                connection.exportedInterface = .phoneFilesBackend
                connection.exportedObject = backend
                connection.remoteObjectInterface = .phoneFilesExtensionControl
                connection.invalidationHandler = { [weak connection] in
                    Task { @MainActor in
                        let controller = PhoneFilesController.shared
                        if controller.links[deviceId] === connection { controller.links[deviceId] = nil }
                    }
                }
                connection.resume()
                links[deviceId] = connection
                (connection.remoteObjectProxy as? PhoneFilesExtensionControl)?.attach { _ in }
                TetherLog("[Files] Finder connected for \(paired[deviceId] ?? deviceId)")
                signalChanges(deviceId)
            } catch {
                TetherLog("[Files] Couldn't connect to the Finder extension: \(error)")
            }
        }
    }

    private func detach(_ deviceId: String) {
        links.removeValue(forKey: deviceId)?.invalidate()
        if let router = routers[deviceId] {
            Task { await router.close() }
        }
    }

    /// Tells Finder to re-read the folders it has open for this phone.
    func refreshFinder(_ deviceId: String) {
        (links[deviceId]?.remoteObjectProxy as? PhoneFilesExtensionControl)?.refresh()
    }

    /// Opens the phone's location in Finder.
    func showInFinder(_ deviceId: String) {
        guard let manager = NSFileProviderManager(for: domain(deviceId)) else { return }
        Task {
            do {
                let url = try await manager.getUserVisibleURL(for: .rootContainer)
                NSWorkspace.shared.open(url)
            } catch {
                TetherLog("[Files] Couldn't open the phone in Finder: \(error)")
                setupError = error.localizedDescription
            }
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

/// Answers the extension's requests for one phone.
final class PhoneFilesBackendService: NSObject, PhoneFilesBackend, @unchecked Sendable {
    private let router: PhoneFilesRouter

    init(router: PhoneFilesRouter) {
        self.router = router
    }

    private func respond(_ reply: @escaping (Data?, NSError?) -> Void, _ work: @escaping @Sendable () async throws -> Data) {
        Task {
            do {
                reply(try await work(), nil)
            } catch {
                reply(nil, Self.bridge(error))
            }
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    /// Turns any failure into one of the codes the extension maps for Finder.
    static func bridge(_ error: Error) -> NSError {
        let message = error.localizedDescription
        switch error {
        case SFTPError.noSuchFile: return PhoneFiles.error(.noSuchItem, message)
        case SFTPError.permissionDenied: return PhoneFiles.error(.permissionDenied, message)
        case let sftp as SFTPError: return PhoneFiles.error(.failed, sftp.localizedDescription)
        case SftpPlugin.RequestError.refused(let reason): return PhoneFiles.error(.failed, reason)
        case is SftpPlugin.RequestError, is SSHSocketError, PhoneFileError.notConnected:
            return PhoneFiles.error(.notConnected, message)
        case SSHError.disconnected: return PhoneFiles.error(.notConnected, message)
        default: return PhoneFiles.error(.failed, message)
        }
    }

    func listDirectory(_ path: String, reply: @escaping (Data?, NSError?) -> Void) {
        respond(reply) { try Self.encode(try await self.router.run { try await $0.list(path) }) }
    }

    func itemInfo(_ path: String, reply: @escaping (Data?, NSError?) -> Void) {
        respond(reply) { try Self.encode(try await self.router.run { try await $0.info(path) }) }
    }

    func download(_ path: String, into file: FileHandle, reply: @escaping (NSError?) -> Void) {
        respond({ _, error in reply(error) }) {
            // Keep the handle alive until the transfer is done.
            let descriptor = file.fileDescriptor
            try await self.router.run { try await $0.download(path, to: descriptor) }
            try file.close()
            return Data()
        }
    }

    func upload(_ file: FileHandle, size: Int64, folder: String, name: String, modified: Date?,
                reply: @escaping (Data?, NSError?) -> Void) {
        respond(reply) {
            let descriptor = file.fileDescriptor
            let result = try await self.router.run {
                try await $0.upload(from: descriptor, size: size, folder: folder, name: name, modified: modified)
            }
            try file.close()
            return try Self.encode(result)
        }
    }

    func makeDirectory(folder: String, name: String, reply: @escaping (Data?, NSError?) -> Void) {
        respond(reply) { try Self.encode(try await self.router.run { try await $0.makeDirectory(folder: folder, name: name) }) }
    }

    func delete(_ path: String, isDirectory: Bool, reply: @escaping (NSError?) -> Void) {
        respond({ _, error in reply(error) }) {
            try await self.router.run { try await $0.delete(path, isDirectory: isDirectory) }
            return Data()
        }
    }

    func move(_ path: String, toFolder folder: String, name: String, reply: @escaping (Data?, NSError?) -> Void) {
        respond(reply) { try Self.encode(try await self.router.run { try await $0.move(path, toFolder: folder, name: name) }) }
    }
}
