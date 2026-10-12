//
//  UpdateInstaller.swift
//  Tether
//
//  Downloads a release, proves it is ours, and swaps it in for the running app.
//  Nothing is replaced unless every check passes, so a failure leaves the
//  installed copy untouched.
//

import CryptoKit
import Foundation

nonisolated enum UpdateFailure: LocalizedError, Equatable {
    case download(String)
    case checksumMismatch
    case extractFailed
    case noAppInArchive
    case quarantined
    case wrongApp
    case versionMismatch(expected: String, found: String)
    case untrustedSignature
    case notWritable
    case replaceFailed(String)

    var errorDescription: String? {
        switch self {
        case .download(let reason): "The download failed: \(reason)"
        case .checksumMismatch: "The download was damaged. Try again."
        case .extractFailed, .noAppInArchive: "The download didn't contain a usable copy of Tether."
        case .quarantined: "macOS kept the download quarantined, so it wasn't installed."
        case .wrongApp: "The download isn't Tether."
        case .versionMismatch(let expected, let found): "Expected Tether \(expected) but the download is \(found)."
        case .untrustedSignature: "The download isn't signed by Tether's developer, so it wasn't installed."
        case .notWritable: "Tether can't replace itself in its current folder. Download the update and install it by hand."
        case .replaceFailed(let reason): "Tether couldn't be replaced: \(reason)"
        }
    }
}

nonisolated struct UpdateInstaller: Sendable {
    enum Phase: Sendable, Equatable {
        case downloading(received: Int64, expected: Int64)
        case verifying
        case installing

        var message: String {
            switch self {
            case .downloading(let received, let expected):
                "Downloading… \(received.formatted(.byteCount(style: .file))) of \(expected.formatted(.byteCount(style: .file)))"
            case .verifying: "Verifying…"
            case .installing: "Installing…"
            }
        }

        var fraction: Double? {
            guard case .downloading(let received, let expected) = self, expected > 0 else { return nil }
            return min(1, Double(received) / Double(expected))
        }
    }

    let bundleURL: URL
    let stagingDirectory: URL

    static var standard: UpdateInstaller {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return UpdateInstaller(
            bundleURL: Bundle.main.bundleURL,
            stagingDirectory: caches.appendingPathComponent("TetherUpdate", isDirectory: true)
        )
    }

    /// Whether the folder holding Tether can be written, so the app can be
    /// replaced without asking for an administrator password.
    var canReplaceInPlace: Bool {
        FileManager.default.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path)
    }

    func install(_ release: AvailableRelease, onProgress: @escaping @Sendable (Phase) -> Void) async throws {
        guard canReplaceInPlace else { throw UpdateFailure.notWritable }

        let fileManager = FileManager.default
        try? fileManager.removeItem(at: stagingDirectory)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        let archive = stagingDirectory.appendingPathComponent("\(release.tag).zip")
        onProgress(.downloading(received: 0, expected: release.archiveSize))
        let digest = try await download(release, to: archive, onProgress: onProgress)

        onProgress(.verifying)
        if let expected = release.archiveSHA256, expected != digest {
            throw UpdateFailure.checksumMismatch
        }
        let staged = try await expand(archive)
        try verify(staged, is: release)

        onProgress(.installing)
        do {
            _ = try fileManager.replaceItemAt(bundleURL, withItemAt: staged, options: .usingNewMetadataOnly)
        } catch {
            throw UpdateFailure.replaceFailed(error.localizedDescription)
        }
        TetherLog("[Updater] Installed Tether \(release.version)")
    }

    /// Streams the zip to disk and returns its SHA-256.
    private func download(
        _ release: AvailableRelease,
        to destination: URL,
        onProgress: @escaping @Sendable (Phase) -> Void
    ) async throws -> String {
        var request = URLRequest(url: release.archiveURL, timeoutInterval: 30)
        request.setValue("Tether/\(AppVersion.current?.description ?? "0")", forHTTPHeaderField: "User-Agent")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession(configuration: configuration).bytes(for: request)
        } catch {
            throw UpdateFailure.download(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateFailure.download("server answered \(status)") }

        let expected = response.expectedContentLength > 0 ? response.expectedContentLength : release.archiveSize
        guard FileManager.default.createFile(atPath: destination.path, contents: nil),
              let output = try? FileHandle(forWritingTo: destination) else {
            throw UpdateFailure.download("couldn't write to disk")
        }
        defer { try? output.close() }

        var hasher = SHA256()
        var buffer = Data()
        buffer.reserveCapacity(1 << 16)
        var received: Int64 = 0

        func flush() throws {
            hasher.update(data: buffer)
            try output.write(contentsOf: buffer)
            received += Int64(buffer.count)
            buffer.removeAll(keepingCapacity: true)
            onProgress(.downloading(received: received, expected: expected))
        }

        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 1 << 16 { try flush() }
            }
            try flush()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UpdateFailure.download(error.localizedDescription)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Unzips with `ditto`, which keeps the bundle's signature intact.
    private func expand(_ archive: URL) async throws -> URL {
        let directory = stagingDirectory.appendingPathComponent("expanded", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, directory.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: UpdateFailure.extractFailed)
            }
        }
        guard status == 0 else { throw UpdateFailure.extractFailed }

        let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        guard let app = contents?.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateFailure.noAppInArchive
        }
        return app
    }

    private func verify(_ staged: URL, is release: AvailableRelease) throws {
        // A file Tether downloads itself isn't quarantined, but check rather than assume.
        Quarantine.clear(from: staged)
        guard !Quarantine.isSet(on: staged) else { throw UpdateFailure.quarantined }

        // Read from disk, not through Bundle, whose cache could answer for the running copy.
        let plistURL = staged.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw UpdateFailure.wrongApp
        }
        let found = info["CFBundleShortVersionString"] as? String ?? "unknown"
        guard AppVersion(found) == release.version else {
            throw UpdateFailure.versionMismatch(expected: release.version.description, found: found)
        }
        guard BundleSignature.isTrusted(staged) else { throw UpdateFailure.untrustedSignature }
    }
}

nonisolated enum Quarantine {
    private static let attribute = "com.apple.quarantine"

    static func isSet(on url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, attribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0
        }
    }

    /// Unzipping a quarantined archive marks every file, not just the bundle.
    static func clear(from root: URL) {
        remove(from: root)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in walker { remove(from: url) }
    }

    private static func remove(from url: URL) {
        _ = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(0) }
            return removexattr(path, attribute, XATTR_NOFOLLOW)
        }
    }
}

nonisolated enum Relauncher {
    /// Reopens Tether once this process has exited. `open` on a bundle that is
    /// still running would only bring the old instance forward.
    static func relaunchAfterExit(_ bundleURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        let quoted = bundleURL.path.replacingOccurrences(of: "'", with: "'\\''")
        process.arguments = [
            "-c",
            "while /bin/kill -0 \(getpid()) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open '\(quoted)'"
        ]
        try? process.run()
    }
}
