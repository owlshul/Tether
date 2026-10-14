//
//  PhoneFileProvider.swift
//  TetherFiles
//
//  The phone's storage in Finder. Each paired phone is a File Provider
//  domain; this extension answers Finder for it and passes every operation
//  to Tether (see BackendLink), which talks to the phone over SFTP or ADB.
//
//  Folders are listed when Finder opens them. Changes made on the phone are
//  picked up when Tether signals the working set (once a minute): the
//  extension then re-lists a few of the folders the Mac has opened.
//

import FileProvider
import UniformTypeIdentifiers
import Foundation

final class PhoneFileProvider: NSObject, NSFileProviderReplicatedExtension, NSFileProviderServicing, @unchecked Sendable {
    let domain: NSFileProviderDomain
    let store: ItemStore
    let link: BackendLink

    private let lock = NSLock()
    /// Folders opened during this run, most recent first; checked before others.
    private var recentFolders: [NSFileProviderItemIdentifier] = []
    /// Where the round-robin through older opened folders continues.
    private var rotation = 0
    private static let foldersPerCheck = 8

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        store = ItemStore(domain: domain)
        link = BackendLink(domainIdentifier: domain.identifier.rawValue)
        super.init()
        link.onRefresh = { [weak self] in self?.signalChanges() }
    }

    func invalidate() {
        link.invalidate()
    }

    // MARK: - Items

    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        if identifier == .rootContainer {
            completionHandler(PhoneItem.root(named: domain.displayName), nil)
            return Progress()
        }
        guard let record = store.record(for: identifier) else {
            completionHandler(nil, NSFileProviderError(.noSuchItem))
            return Progress()
        }
        let parent = NSFileProviderItemIdentifier(record.parent)
        Task {
            do {
                let file = try await info(record.path)
                _ = store.identifier(for: file, parent: parent)
                completionHandler(PhoneItem(identifier: identifier, parent: parent, file: file), nil)
            } catch let error as NSFileProviderError where error.code == .serverUnreachable {
                // Offline: what we last knew is better than nothing.
                completionHandler(PhoneItem(identifier: identifier, parent: parent, file: record.file), nil)
            } catch {
                completionHandler(nil, error)
            }
        }
        return Progress()
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        guard let record = store.record(for: itemIdentifier) else {
            completionHandler(nil, nil, NSFileProviderError(.noSuchItem))
            return Progress()
        }
        let progress = Progress(totalUnitCount: max(record.file.size, 1))

        Task {
            do {
                guard let manager = NSFileProviderManager(for: domain) else { throw NSFileProviderError(.providerNotFound) }
                let url = try manager.temporaryDirectoryURL().appendingPathComponent(UUID().uuidString)
                FileManager.default.createFile(atPath: url.path, contents: nil)
                let handle = try FileHandle(forWritingTo: url)

                // Tether writes straight into the file; its size is the progress.
                let poll = Task {
                    while !Task.isCancelled {
                        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                        progress.completedUnitCount = min(size, progress.totalUnitCount)
                        try? await Task.sleep(for: .milliseconds(300))
                    }
                }
                defer { poll.cancel() }

                _ = try await link.call { (backend, reply: @escaping @Sendable (Bool?, NSError?) -> Void) in
                    backend.download(record.path, into: handle) { error in reply(error == nil, error) }
                }
                try handle.close()

                var file = record.file
                file.size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? file.size
                progress.completedUnitCount = progress.totalUnitCount
                completionHandler(url, PhoneItem(identifier: itemIdentifier, parent: NSFileProviderItemIdentifier(record.parent), file: file), nil)
            } catch {
                completionHandler(nil, nil, error)
            }
        }
        return progress
    }

    // MARK: - Changes from the Mac

    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?,
                    options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let parent = itemTemplate.parentItemIdentifier
        guard let folder = store.path(for: parent) else {
            completionHandler(nil, [], false, NSFileProviderError(.noSuchItem))
            return Progress()
        }
        let name = itemTemplate.filename
        let isFolder = itemTemplate.contentType == .folder

        if itemTemplate.contentType == .symbolicLink || itemTemplate.contentType == .aliasFile {
            completionHandler(nil, [], false, NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError,
                                                      userInfo: [NSLocalizedDescriptionKey: "Links can't be copied to the phone."]))
            return Progress()
        }

        Task {
            do {
                let file: RemoteFile
                if isFolder {
                    file = try await decodeFile(try await link.call { (backend, reply: @escaping @Sendable (Data?, NSError?) -> Void) in
                        backend.makeDirectory(folder: folder, name: name) { data, error in reply(data, error) }
                    })
                } else {
                    file = try await upload(url, folder: folder, name: name, modified: itemTemplate.contentModificationDate ?? nil)
                }
                let identifier = store.identifier(for: file, parent: parent)
                completionHandler(PhoneItem(identifier: identifier, parent: parent, file: file), [], false, nil)
            } catch {
                completionHandler(nil, [], false, error)
            }
        }
        return Progress()
    }

    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion,
                    changedFields: NSFileProviderItemFields, contents newContents: URL?,
                    options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        guard let record = store.record(for: item.itemIdentifier) else {
            completionHandler(nil, [], false, NSFileProviderError(.noSuchItem))
            return Progress()
        }
        Task {
            do {
                var file = record.file
                var parent = NSFileProviderItemIdentifier(record.parent)

                if changedFields.contains(.filename) || changedFields.contains(.parentItemIdentifier) {
                    let newParent = item.parentItemIdentifier
                    guard let folder = store.path(for: newParent) else { throw NSFileProviderError(.noSuchItem) }
                    let path = record.path, name = item.filename
                    file = try await decodeFile(try await link.call { (backend, reply: @escaping @Sendable (Data?, NSError?) -> Void) in
                        backend.move(path, toFolder: folder, name: name) { data, error in reply(data, error) }
                    })
                    store.move(item.itemIdentifier, to: file, parent: newParent)
                    parent = newParent
                }

                if changedFields.contains(.contents), !file.isDirectory, let newContents {
                    let folder = (file.path as NSString).deletingLastPathComponent
                    file = try await upload(newContents, folder: folder, name: file.name,
                                            modified: item.contentModificationDate ?? nil)
                    _ = store.identifier(for: file, parent: parent)
                }

                // Other fields (tags, last used date, …) have nowhere to go on the phone.
                completionHandler(PhoneItem(identifier: item.itemIdentifier, parent: parent, file: file), [], false, nil)
            } catch {
                completionHandler(nil, [], false, error)
            }
        }
        return Progress()
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress {
        guard let record = store.record(for: identifier) else {
            completionHandler(nil) // already gone
            return Progress()
        }
        Task {
            do {
                _ = try await link.call { (backend, reply: @escaping @Sendable (Bool?, NSError?) -> Void) in
                    backend.delete(record.path, isDirectory: record.file.isDirectory) { error in reply(error == nil, error) }
                }
                store.remove(identifier)
                completionHandler(nil)
            } catch let error as NSFileProviderError where error.code == .noSuchItem {
                store.remove(identifier)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
        return Progress()
    }

    // MARK: - Enumeration

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        guard containerItemIdentifier == .workingSet || store.path(for: containerItemIdentifier) != nil else {
            throw NSFileProviderError(.noSuchItem)
        }
        return PhoneEnumerator(container: containerItemIdentifier, provider: self)
    }

    /// Lists a folder, remembering it so later changes on the phone show up.
    func listItems(in container: NSFileProviderItemIdentifier) async throws -> [PhoneItem] {
        guard let path = store.path(for: container) else { throw NSFileProviderError(.noSuchItem) }
        let data = try await link.call { (backend, reply: @escaping @Sendable (Data?, NSError?) -> Void) in
            backend.listDirectory(path) { data, error in reply(data, error) }
        }
        let files = try JSONDecoder().decode([RemoteFile].self, from: data ?? Data("[]".utf8))
        let items = files.map { PhoneItem(identifier: store.identifier(for: $0, parent: container), parent: container, file: $0) }

        lock.withLock {
            recentFolders.removeAll { $0 == container }
            recentFolders.insert(container, at: 0)
            recentFolders = Array(recentFolders.prefix(Self.foldersPerCheck))
        }
        return items
    }

    struct Changes {
        var updated: [PhoneItem] = []
        var deleted: [NSFileProviderItemIdentifier] = []
    }

    /// Re-lists folders and reports their contents and what disappeared.
    /// Reporting unchanged items is fine: Finder compares versions itself.
    func changes(in containers: [NSFileProviderItemIdentifier]) async -> Changes {
        var changes = Changes()
        for container in containers {
            let before = store.children(of: container)
            guard let items = try? await listItems(in: container) else { continue }
            changes.updated += items
            let after = Set(items.map(\.itemIdentifier))
            for identifier in before.subtracting(after) {
                changes.deleted.append(identifier)
                store.remove(identifier)
            }
        }
        return changes
    }

    /// The folders to check this round: the ones opened most recently, then
    /// a rotating few of the others macOS has kept (materialized).
    func foldersToCheck() async -> [NSFileProviderItemIdentifier] {
        var folders = lock.withLock { recentFolders }
        guard let manager = NSFileProviderManager(for: domain) else { return folders }

        var materialized: [NSFileProviderItemIdentifier] = []
        let enumerator = manager.enumeratorForMaterializedItems()
        let collector = MaterializedCollector()
        await collector.collect(from: enumerator)
        materialized = collector.folders.filter { !folders.contains($0) }.sorted { $0.rawValue < $1.rawValue }

        let room = max(0, Self.foldersPerCheck - folders.count)
        if room > 0, !materialized.isEmpty {
            let start = lock.withLock { () -> Int in
                defer { rotation += room }
                return rotation % materialized.count
            }
            for offset in 0..<min(room, materialized.count) {
                folders.append(materialized[(start + offset) % materialized.count])
            }
        }
        return folders
    }

    var currentAnchor: NSFileProviderSyncAnchor {
        // Changes are computed by re-listing, not from a log, so any anchor works.
        NSFileProviderSyncAnchor(Data("\(Date().timeIntervalSince1970)".utf8))
    }

    func signalChanges() {
        NSFileProviderManager(for: domain)?.signalEnumerator(for: .workingSet) { _ in }
    }

    // MARK: - Helpers

    private func info(_ path: String) async throws -> RemoteFile {
        try await decodeFile(try await link.call { (backend, reply: @escaping @Sendable (Data?, NSError?) -> Void) in
            backend.itemInfo(path) { data, error in reply(data, error) }
        })
    }

    private func upload(_ url: URL?, folder: String, name: String, modified: Date?) async throws -> RemoteFile {
        // An empty file arrives without contents.
        let source: URL
        if let url {
            source = url
        } else {
            source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: source.path, contents: nil)
        }
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let size = (try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int64) ?? 0
        return try await decodeFile(try await link.call { (backend, reply: @escaping @Sendable (Data?, NSError?) -> Void) in
            backend.upload(handle, size: size, folder: folder, name: name, modified: modified) { data, error in reply(data, error) }
        })
    }

    private func decodeFile(_ data: Data?) async throws -> RemoteFile {
        guard let data, let file = try? JSONDecoder().decode(RemoteFile.self, from: data) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)
        }
        return file
    }

    // MARK: - Service for Tether

    func supportedServiceSources(for itemIdentifier: NSFileProviderItemIdentifier,
                                 completionHandler: @escaping ([NSFileProviderServiceSource]?, Error?) -> Void) -> Progress {
        completionHandler([link], nil)
        return Progress()
    }
}

final class PhoneEnumerator: NSObject, NSFileProviderEnumerator, @unchecked Sendable {
    private let container: NSFileProviderItemIdentifier
    private weak var provider: PhoneFileProvider?

    init(container: NSFileProviderItemIdentifier, provider: PhoneFileProvider) {
        self.container = container
        self.provider = provider
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        guard let provider, container != .workingSet else {
            // The working set is empty: nothing on the phone is kept on the Mac ahead of time.
            observer.finishEnumerating(upTo: nil)
            return
        }
        Task {
            do {
                let items = try await provider.listItems(in: container)
                for start in stride(from: 0, to: items.count, by: 500) {
                    observer.didEnumerate(Array(items[start..<min(start + 500, items.count)]))
                }
                observer.finishEnumerating(upTo: nil)
            } catch {
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        guard let provider else { return observer.finishEnumeratingWithError(NSFileProviderError(.syncAnchorExpired)) }
        Task {
            let folders = container == .workingSet ? await provider.foldersToCheck() : [container]
            let changes = await provider.changes(in: folders)
            if !changes.updated.isEmpty { observer.didUpdate(changes.updated) }
            if !changes.deleted.isEmpty { observer.didDeleteItems(withIdentifiers: changes.deleted) }
            observer.finishEnumeratingChanges(upTo: provider.currentAnchor, moreComing: false)
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(provider?.currentAnchor)
    }
}

/// Collects the folders among the items macOS has materialized.
final class MaterializedCollector: NSObject, NSFileProviderEnumerationObserver, @unchecked Sendable {
    private(set) var folders: [NSFileProviderItemIdentifier] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private weak var enumerator: NSFileProviderEnumerator?

    func collect(from enumerator: NSFileProviderEnumerator) async {
        self.enumerator = enumerator
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            enumerator.enumerateItems(for: self, startingAt: NSFileProviderPage(NSFileProviderPage.initialPageSortedByName as Data))
        }
    }

    func didEnumerate(_ updatedItems: [NSFileProviderItemProtocol]) {
        for item in updatedItems where item.contentType == .folder || item.itemIdentifier == .rootContainer {
            folders.append(item.itemIdentifier)
        }
    }

    func finishEnumerating(upTo nextPage: NSFileProviderPage?) {
        if let nextPage, let enumerator {
            enumerator.enumerateItems(for: self, startingAt: nextPage)
        } else {
            finish()
        }
    }

    func finishEnumeratingWithError(_ error: Error) {
        finish()
    }

    private func finish() {
        continuation?.resume()
        continuation = nil
    }
}
