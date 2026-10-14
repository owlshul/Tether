//
//  SFTPLiveTests.swift
//  TetherTests
//
//  Runs the SSH/SFTP client against a real phone. Skipped unless
//  TETHER_SFTP_LIVE names a JSON file with the phone's SFTP reply (ip, port,
//  user, password, path); TETHER_SFTP_HOST overrides the address, e.g. with
//  the phone's Tailscale IP.
//

import Foundation
import Testing
@testable import Tether

@Suite(.serialized) struct SFTPLiveTests {
    static let credentialsPath = ProcessInfo.processInfo.environment["TETHER_SFTP_LIVE"]

    private struct Credentials: Decodable {
        let ip: String
        let port: Int
        let user: String
        let password: String
        let path: String
    }

    private func connect() async throws -> (SFTPClient, String) {
        let data = try Data(contentsOf: URL(fileURLWithPath: Self.credentialsPath!))
        let credentials = try JSONDecoder().decode(Credentials.self, from: data)
        let host = ProcessInfo.processInfo.environment["TETHER_SFTP_HOST"] ?? credentials.ip
        let client = try await SFTPClient.connect(
            host: host, port: UInt16(credentials.port), user: credentials.user, password: credentials.password,
            checkHostKey: { key in
                print("Host key: \(key.algorithm) \(key.fingerprint)")
                return true
            }
        )
        return (client, credentials.path)
    }

    @Test(.enabled(if: credentialsPath != nil))
    func listsDownloadsAndUploads() async throws {
        let (client, root) = try await connect()

        let entries = try await client.list(root)
        print("\(root): \(entries.count) entries, e.g. \(entries.prefix(5).map(\.name))")
        #expect(entries.contains { $0.name == "Download" && $0.isDirectory })

        // Upload 3 MB of random data, read it back, compare, delete.
        let size = 3 * 1024 * 1024 + 123
        var original = Data(count: size)
        _ = original.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, size, $0.baseAddress!) }
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try original.write(to: local)
        let remote = SFTPClient.join(root, "Download/tether-sftp-test.bin")

        let source = try FileHandle(forReadingFrom: local)
        let started = Date()
        try await client.upload(from: source.fileDescriptor, size: Int64(size), to: remote, modified: nil) { _ in }
        try source.close()
        let uploadTime = Date().timeIntervalSince(started)

        let stat = try await client.stat(remote)
        #expect(stat.size == Int64(size))

        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: copy.path, contents: nil)
        let sink = try FileHandle(forWritingTo: copy)
        let downloadStarted = Date()
        let received = try await client.download(remote, to: sink.fileDescriptor) { _ in }
        try sink.close()
        let downloadTime = Date().timeIntervalSince(downloadStarted)

        #expect(received == Int64(size))
        #expect(try Data(contentsOf: copy) == original)
        print(String(format: "Upload %.2f MB/s, download %.2f MB/s",
                     Double(size) / 1_048_576 / uploadTime, Double(size) / 1_048_576 / downloadTime))

        try await client.removeFile(remote)
        await #expect(throws: SFTPError.noSuchFile) { _ = try await client.stat(remote) }
        await client.close()
    }
}
