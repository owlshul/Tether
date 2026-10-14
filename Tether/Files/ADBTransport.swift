//
//  ADBTransport.swift
//  Tether
//
//  Phone storage over ADB, using the phone's wireless debugging and the `adb`
//  tool installed on the Mac (Android SDK or `brew install android-platform-tools`).
//  It's opt-in and meant for people who already use ADB: they enter the
//  address and port shown under Developer options › Wireless debugging.
//
//  ADB gives full access to the phone, so this only runs file commands
//  (find, stat, cat, mkdir, rm, mv) on paths Finder asked for, each quoted.
//

import Foundation

nonisolated enum ADBError: LocalizedError {
    case notInstalled
    case unreachable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled: "adb isn't installed. Install it with: brew install android-platform-tools"
        case .unreachable(let detail): "Couldn't reach the phone over wireless debugging. \(detail)"
        case .failed(let detail): detail
        }
    }
}

actor ADBTransport: PhoneFileTransport {
    /// Internal storage, which is what ADB shares here.
    static let storagePath = "/storage/emulated/0"
    static let storageName = "Internal shared storage"

    static let searchPaths: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
        ]
    }()

    static var executable: String? {
        searchPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    let address: String
    private var isConnected = false

    init(address: String) {
        self.address = address
    }

    // MARK: - Running adb

    private struct Output {
        let status: Int32
        let stdout: Data
        let stderr: String
    }

    private func run(_ arguments: [String], stdin: FileHandle? = nil, stdout: FileHandle? = nil) async throws -> Output {
        guard let adb = Self.executable else { throw ADBError.notInstalled }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = arguments
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = stdout ?? outPipe
        process.standardError = errPipe
        process.standardInput = stdin ?? FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { continuation in
            // Read both pipes while it runs, so a large listing can't fill a pipe and stall adb.
            let group = DispatchGroup()
            var out = Data(), err = Data()
            group.enter()
            DispatchQueue.global().async {
                if stdout == nil { out = outPipe.fileHandleForReading.readDataToEndOfFile() }
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                err = errPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            process.terminationHandler = { process in
                group.notify(queue: .global()) {
                    continuation.resume(returning: Output(status: process.terminationStatus, stdout: out,
                                                          stderr: String(decoding: err, as: UTF8.self)))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ADBError.failed("Couldn't run adb: \(error.localizedDescription)"))
            }
        }
    }

    private func ensureConnected() async throws {
        if isConnected {
            let state = try await run(["-s", address, "get-state"])
            if state.status == 0 { return }
            isConnected = false
        }
        let result = try await run(["connect", address])
        let text = String(decoding: result.stdout, as: UTF8.self) + result.stderr
        guard text.contains("connected to") else {
            throw ADBError.unreachable(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        isConnected = true
    }

    /// Runs a shell command on the phone and returns its output.
    private func shell(_ command: String, stdin: FileHandle? = nil, stdout: FileHandle? = nil) async throws -> Data {
        try await ensureConnected()
        let verb = stdin != nil ? "exec-in" : (stdout != nil ? "exec-out" : "shell")
        let result = try await run(["-s", address, verb, command], stdin: stdin, stdout: stdout)
        // `shell` reports the command's exit status; exec-in/exec-out don't, so
        // for those an error message on stderr is the only sign of failure.
        let failedQuietly = verb != "shell" && (result.stderr.contains("No such file") || result.stderr.contains("Permission denied"))
        if result.status != 0 || failedQuietly {
            let output = (stdout == nil ? String(decoding: result.stdout, as: UTF8.self) : "") + result.stderr
            if output.contains("No such file") { throw SFTPError.noSuchFile }
            if output.contains("Permission denied") { throw SFTPError.permissionDenied }
            if output.contains("offline") || output.contains("not found") || output.contains("closed") {
                isConnected = false
                throw ADBError.unreachable(output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            throw ADBError.failed(output.isEmpty ? "adb exited with status \(result.status)" : output)
        }
        return result.stdout
    }

    /// Single-quotes a path for the phone's shell.
    private static func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func resolve(_ folder: String) -> String {
        folder == PhoneFiles.rootPath ? storagePath : folder
    }

    /// Parses `stat -c '%s|%Y|%f|%n'` lines: size, modified, raw mode (hex), path.
    private static func parse(_ output: Data) -> [RemoteFile] {
        String(decoding: output, as: UTF8.self).split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count == 4, let size = Int64(fields[0]), let seconds = TimeInterval(fields[1]),
                  let mode = UInt32(fields[2], radix: 16) else { return nil }
            let path = String(fields[3])
            return RemoteFile(path: path, name: (path as NSString).lastPathComponent,
                              isDirectory: mode & 0o170000 == 0o040000, size: size,
                              modified: Date(timeIntervalSince1970: seconds))
        }
    }

    private static let statFormat = "'%s|%Y|%f|%n'"

    // MARK: - PhoneFileTransport

    func list(_ path: String) async throws -> [RemoteFile] {
        let folder = Self.resolve(path)
        let output = try await shell("find \(Self.quote(folder)) -mindepth 1 -maxdepth 1 -exec stat -c \(Self.statFormat) {} + 2>/dev/null; true")
        return Self.parse(output)
    }

    func info(_ path: String) async throws -> RemoteFile {
        if path == PhoneFiles.rootPath {
            return RemoteFile(path: path, name: Self.storageName, isDirectory: true, size: 0, modified: nil)
        }
        guard let file = Self.parse(try await shell("stat -c \(Self.statFormat) \(Self.quote(path))")).first else {
            throw SFTPError.noSuchFile
        }
        return file
    }

    func download(_ path: String, to fileDescriptor: Int32) async throws {
        let expected = try await info(path).size
        let sink = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: false)
        _ = try await shell("cat \(Self.quote(path))", stdout: sink)
        let written = lseek(fileDescriptor, 0, SEEK_END)
        guard written == expected else {
            throw ADBError.failed("The download from the phone stopped early.")
        }
    }

    func upload(from fileDescriptor: Int32, size: Int64, folder: String, name: String, modified: Date?) async throws -> RemoteFile {
        let path = joinPath(Self.resolve(folder), name)
        lseek(fileDescriptor, 0, SEEK_SET)
        let source = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: false)
        _ = try await shell("cat > \(Self.quote(path))", stdin: source)
        let file = try await info(path)
        guard file.size == size else { throw ADBError.failed("The upload to the phone stopped early.") }
        return file
    }

    func makeDirectory(folder: String, name: String) async throws -> RemoteFile {
        let path = joinPath(Self.resolve(folder), name)
        _ = try await shell("mkdir \(Self.quote(path))")
        return try await info(path)
    }

    func delete(_ path: String, isDirectory: Bool) async throws {
        _ = try await shell((isDirectory ? "rm -rf " : "rm -f ") + Self.quote(path))
    }

    func move(_ path: String, toFolder folder: String, name: String) async throws -> RemoteFile {
        let destination = joinPath(Self.resolve(folder), name)
        _ = try await shell("mv \(Self.quote(path)) \(Self.quote(destination))")
        return try await info(destination)
    }

    func close() async {}
}
