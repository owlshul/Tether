//
//  BackendLink.swift
//  TetherFiles
//
//  The extension's line to Tether. Tether connects through the File Provider
//  service below whenever the phone is connected; until it does, requests wait
//  briefly while the extension asks for it with a distributed notification.
//

import FileProvider
import Foundation

final class BackendLink: NSObject, NSFileProviderServiceSource, NSXPCListenerDelegate, PhoneFilesExtensionControl, @unchecked Sendable {
    let serviceName = NSFileProviderServiceName(PhoneFiles.serviceName)

    private let domainIdentifier: String
    private let listener = NSXPCListener.anonymous()
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var waiters: [UUID: CheckedContinuation<NSXPCConnection, Error>] = [:]

    /// Called when Tether asks the extension to re-read open folders.
    var onRefresh: (() -> Void)?

    init(domainIdentifier: String) {
        self.domainIdentifier = domainIdentifier
        super.init()
        listener.delegate = self
        listener.resume()
    }

    func invalidate() {
        listener.invalidate()
        lock.withLock { connection }?.invalidate()
    }

    // MARK: NSFileProviderServiceSource

    func makeListenerEndpoint() throws -> NSXPCListenerEndpoint {
        listener.endpoint
    }

    // MARK: NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = .phoneFilesExtensionControl
        newConnection.exportedObject = self
        newConnection.remoteObjectInterface = .phoneFilesBackend
        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            guard let self else { return }
            lock.withLock {
                if self.connection === newConnection { self.connection = nil }
            }
        }
        newConnection.interruptionHandler = newConnection.invalidationHandler
        newConnection.resume()
        return true
    }

    // MARK: PhoneFilesExtensionControl

    func attach(reply: @escaping (Bool) -> Void) {
        guard let current = NSXPCConnection.current() else { return reply(false) }
        let waiting = lock.withLock {
            let old = connection
            connection = current
            defer { waiters.removeAll() }
            if let old, old !== current { old.invalidate() }
            return waiters
        }
        waiting.values.forEach { $0.resume(returning: current) }
        reply(true)
    }

    func refresh() {
        onRefresh?()
    }

    // MARK: Calling Tether

    /// Tether's connection, waiting up to 10 seconds for it to attach.
    private func currentConnection() async throws -> NSXPCConnection {
        if let connection = lock.withLock({ connection }) { return connection }

        DistributedNotificationCenter.default().postNotificationName(
            PhoneFiles.needsBackendNotification, object: domainIdentifier, userInfo: nil, deliverImmediately: true
        )
        let token = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock { self.waiters[token] = continuation }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self else { return }
                lock.withLock { self.waiters.removeValue(forKey: token) }?
                    .resume(throwing: NSFileProviderError(.serverUnreachable))
            }
        }
    }

    /// Calls Tether, turning a broken connection into "server unreachable".
    /// `body` must call the reply it's given exactly once.
    func call<Result: Sendable>(
        _ body: @escaping (PhoneFilesBackend, @escaping @Sendable (Result?, NSError?) -> Void) -> Void
    ) async throws -> Result? {
        let connection = try await currentConnection()
        return try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                once.run { continuation.resume(throwing: NSFileProviderError(.serverUnreachable)) }
            }
            guard let backend = proxy as? PhoneFilesBackend else {
                return once.run { continuation.resume(throwing: NSFileProviderError(.serverUnreachable)) }
            }
            body(backend) { result, error in
                once.run {
                    if let error {
                        continuation.resume(throwing: Self.fileProviderError(from: error))
                    } else {
                        continuation.resume(returning: result)
                    }
                }
            }
        }
    }

    /// Maps Tether's errors to ones Finder understands.
    static func fileProviderError(from error: NSError) -> Error {
        guard error.domain == PhoneFiles.errorDomain, let code = PhoneFiles.ErrorCode(rawValue: error.code) else {
            return NSFileProviderError(.serverUnreachable)
        }
        switch code {
        case .notConnected: return NSFileProviderError(.serverUnreachable)
        case .noSuchItem: return NSFileProviderError(.noSuchItem)
        case .alreadyExists: return NSFileProviderError(.filenameCollision)
        case .permissionDenied:
            return NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                           userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
        case .failed:
            return NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
                           userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
        }
    }
}

/// Runs a closure at most once, from any thread.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        let first = lock.withLock { () -> Bool in
            defer { done = true }
            return !done
        }
        if first { body() }
    }
}
