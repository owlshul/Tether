//
//  ItemStore.swift
//  TetherFiles
//
//  Finder needs an identifier for each item that survives renames and moves,
//  but SFTP and ADB only know paths. This gives each path a permanent random
//  identifier, moves it along with renames, and remembers each item's parent.
//  It's saved in the extension's container so identifiers survive restarts.
//

import FileProvider
import Foundation

final class ItemStore: @unchecked Sendable {
    struct Record: Codable {
        var path: String
        var parent: String
        var file: RemoteFile
    }

    private let lock = NSLock()
    private let url: URL
    private var records: [String: Record] = [:]
    private var identifierByPath: [String: String] = [:]
    private var saveScheduled = false

    init(domain: NSFileProviderDomain) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("Items", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("\(domain.identifier.rawValue).json")

        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = saved
            for (identifier, record) in saved { identifierByPath[record.path] = identifier }
        }
    }

    /// The identifier for a file seen in `parent`, creating one if it's new.
    func identifier(for file: RemoteFile, parent: NSFileProviderItemIdentifier) -> NSFileProviderItemIdentifier {
        lock.withLock {
            let identifier = identifierByPath[file.path] ?? UUID().uuidString
            identifierByPath[file.path] = identifier
            records[identifier] = Record(path: file.path, parent: parent.rawValue, file: file)
            scheduleSave()
            return NSFileProviderItemIdentifier(identifier)
        }
    }

    func record(for identifier: NSFileProviderItemIdentifier) -> Record? {
        lock.withLock { records[identifier.rawValue] }
    }

    /// Items last seen in `parent`.
    func children(of parent: NSFileProviderItemIdentifier) -> Set<NSFileProviderItemIdentifier> {
        lock.withLock {
            Set(records.compactMap { $0.value.parent == parent.rawValue ? NSFileProviderItemIdentifier($0.key) : nil })
        }
    }

    /// The phone path for an identifier; the root is `PhoneFiles.rootPath`.
    func path(for identifier: NSFileProviderItemIdentifier) -> String? {
        if identifier == .rootContainer { return PhoneFiles.rootPath }
        return lock.withLock { records[identifier.rawValue]?.path }
    }

    /// Records a rename or move, carrying the identifiers of everything inside a folder along.
    func move(_ identifier: NSFileProviderItemIdentifier, to file: RemoteFile, parent: NSFileProviderItemIdentifier) {
        lock.withLock {
            guard let old = records[identifier.rawValue]?.path else { return }
            let prefix = old + "/"
            for (id, record) in records where record.path.hasPrefix(prefix) {
                let newPath = file.path + "/" + record.path.dropFirst(prefix.count)
                identifierByPath.removeValue(forKey: record.path)
                identifierByPath[newPath] = id
                records[id]?.path = newPath
                records[id]?.file.path = newPath
            }
            identifierByPath.removeValue(forKey: old)
            identifierByPath[file.path] = identifier.rawValue
            records[identifier.rawValue] = Record(path: file.path, parent: parent.rawValue, file: file)
            scheduleSave()
        }
    }

    /// Forgets an item and, for a folder, everything inside it.
    func remove(_ identifier: NSFileProviderItemIdentifier) {
        lock.withLock {
            guard let path = records[identifier.rawValue]?.path else { return }
            let prefix = path + "/"
            for (id, record) in records where record.path == path || record.path.hasPrefix(prefix) {
                records.removeValue(forKey: id)
                identifierByPath.removeValue(forKey: record.path)
            }
            scheduleSave()
        }
    }

    /// Saves at most once a second; called with the lock held.
    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [self] in
            let snapshot = lock.withLock {
                saveScheduled = false
                return records
            }
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
