//
//  PhoneFilesInterface.swift
//  Tether and TetherFiles
//
//  The connection between Tether and its Finder extension. The extension is
//  sandboxed and has no connection to the phone, so it passes every file
//  operation to Tether over XPC. Tether opens that connection itself, through
//  the extension's File Provider service, whenever the phone is connected.
//

import Foundation

nonisolated enum PhoneFiles {
    /// The File Provider service the extension offers and Tether connects to.
    static let serviceName = "com.subhashh.Tether.files.backend"

    /// Posted by the extension (object: the domain identifier, which is the
    /// device ID) when Finder needs files and Tether hasn't connected yet.
    static let needsBackendNotification = Notification.Name("com.subhashh.Tether.files.needsBackend")

    static let errorDomain = "com.subhashh.Tether.files"

    /// The root of the phone's storage. With one storage volume it's that
    /// volume; with several (an SD card) it lists them as folders.
    static let rootPath = ""

    enum ErrorCode: Int {
        case notConnected = 1
        case noSuchItem = 2
        case permissionDenied = 3
        case failed = 4
        case alreadyExists = 5
    }

    static func error(_ code: ErrorCode, _ message: String) -> NSError {
        NSError(domain: errorDomain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// A file or folder on the phone.
nonisolated struct RemoteFile: Codable, Sendable, Equatable {
    var path: String
    var name: String
    var isDirectory: Bool
    var size: Int64
    var modified: Date?
}

/// Implemented by Tether, called by the extension. Entries travel as
/// JSON-encoded `RemoteFile`s; file contents travel as file handles, so the
/// bytes go straight into the file Finder will use.
@objc protocol PhoneFilesBackend {
    func listDirectory(_ path: String, reply: @escaping (Data?, NSError?) -> Void)
    func itemInfo(_ path: String, reply: @escaping (Data?, NSError?) -> Void)
    func download(_ path: String, into file: FileHandle, reply: @escaping (NSError?) -> Void)
    /// Creates or replaces `name` in `folder`. `folder` may be `PhoneFiles.rootPath`.
    func upload(_ file: FileHandle, size: Int64, folder: String, name: String, modified: Date?, reply: @escaping (Data?, NSError?) -> Void)
    func makeDirectory(folder: String, name: String, reply: @escaping (Data?, NSError?) -> Void)
    /// Deletes a file, or a folder and everything in it.
    func delete(_ path: String, isDirectory: Bool, reply: @escaping (NSError?) -> Void)
    func move(_ path: String, toFolder folder: String, name: String, reply: @escaping (Data?, NSError?) -> Void)
}

/// Implemented by the extension, called by Tether.
@objc protocol PhoneFilesExtensionControl {
    /// Makes this connection the extension's way to reach the phone.
    func attach(reply: @escaping (Bool) -> Void)
    /// The phone reconnected or the access method changed: re-read open folders.
    func refresh()
}

nonisolated extension NSXPCInterface {
    static var phoneFilesBackend: NSXPCInterface { NSXPCInterface(with: PhoneFilesBackend.self) }
    static var phoneFilesExtensionControl: NSXPCInterface { NSXPCInterface(with: PhoneFilesExtensionControl.self) }
}
