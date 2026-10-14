//
//  PhoneItem.swift
//  TetherFiles
//

import FileProvider
import UniformTypeIdentifiers

/// A file or folder on the phone, as Finder sees it.
final class PhoneItem: NSObject, NSFileProviderItem {
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let file: RemoteFile

    init(identifier: NSFileProviderItemIdentifier, parent: NSFileProviderItemIdentifier, file: RemoteFile) {
        itemIdentifier = identifier
        parentItemIdentifier = parent
        self.file = file
    }

    /// The top of the phone's storage.
    static func root(named name: String) -> PhoneItem {
        PhoneItem(identifier: .rootContainer, parent: .rootContainer,
                  file: RemoteFile(path: PhoneFiles.rootPath, name: name, isDirectory: true, size: 0, modified: nil))
    }

    var filename: String { file.name }

    var contentType: UTType {
        if file.isDirectory { return .folder }
        let ext = (file.name as NSString).pathExtension
        return UTType(filenameExtension: ext) ?? .data
    }

    // The phone has no Trash, so deleting is permanent; Finder warns about that.
    var capabilities: NSFileProviderItemCapabilities {
        if itemIdentifier == .rootContainer {
            return [.allowsReading, .allowsWriting, .allowsAddingSubItems, .allowsContentEnumerating]
        }
        if file.isDirectory {
            return [.allowsReading, .allowsWriting, .allowsAddingSubItems, .allowsContentEnumerating,
                    .allowsRenaming, .allowsReparenting, .allowsDeleting]
        }
        return [.allowsReading, .allowsWriting, .allowsRenaming, .allowsReparenting, .allowsDeleting]
    }

    var documentSize: NSNumber? { file.isDirectory ? nil : NSNumber(value: file.size) }
    var contentModificationDate: Date? { file.modified }
    var creationDate: Date? { file.modified }

    var itemVersion: NSFileProviderItemVersion {
        let stamp = Int64((file.modified ?? .distantPast).timeIntervalSince1970)
        return NSFileProviderItemVersion(
            contentVersion: Data("\(file.size)-\(stamp)".utf8),
            metadataVersion: Data("\(file.name)-\(file.size)-\(stamp)".utf8)
        )
    }
}
