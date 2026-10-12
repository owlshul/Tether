//
//  ShareViewController.swift
//  TetherShare
//
//  "Tether" in the Share menu. Collects what was shared, hands it to the Tether
//  app, and closes; Tether sends it to the connected phone.
//
//  The hand-off uses a private named pasteboard plus a distributed notification
//  rather than a URL scheme: a `tether://send?file=…` link could be opened by any
//  web page or app to push files off the Mac, whereas only local processes can
//  write this pasteboard. Shared data (e.g. a photo from Photos) travels as bytes,
//  so Tether never has to read inside this extension's sandbox container.
//

import Cocoa
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: NSViewController {
    override var nibName: NSNib.Name? { nil }

    private let devices = ShareHandoff.connectedDevices()

    override func loadView() {
        if devices.count > 1 {
            // More than one device connected: ask which, like AirDrop.
            let chooser = DeviceChooser(devices: devices, choose: { [weak self] device in
                Task { await self?.handOff(to: device.id) }
            }, cancel: { [weak self] in
                self?.cancel()
            })
            let hosting = NSHostingView(rootView: chooser)
            hosting.frame.size = hosting.fittingSize
            view = hosting
            preferredContentSize = hosting.fittingSize
        } else {
            // One device or none: nothing to ask. Tether sends to its current
            // device, or explains that none is connected.
            view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if devices.count <= 1 {
            Task { await handOff(to: nil) }
        }
    }

    private func handOff(to deviceId: String?) async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }

        var entries: [ShareHandoff.Entry] = []
        for provider in providers {
            if let entry = await Self.entry(for: provider) {
                entries.append(entry)
            }
        }

        guard !entries.isEmpty else {
            cancel()
            return
        }

        ShareHandoff.write(entries, deviceId: deviceId)
        ShareHandoff.deliver(appURL: Self.containingAppURL)
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    /// Tether.app, which contains this extension at Contents/PlugIns/TetherShare.appex.
    private static var containingAppURL: URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent() // PlugIns
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // Tether.app
    }

    /// Prefers a file on disk, then a web link, then raw data, then text.
    private static func entry(for provider: NSItemProvider) async -> ShareHandoff.Entry? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadURL(provider, type: .fileURL), url.isFileURL {
            return .file(path: url.path)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(provider, type: .url), !url.isFileURL {
            return .url(url.absoluteString)
        }
        for type in [UTType.image, .movie, .data] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let data = await loadData(provider, type: type) {
                let ext = provider.registeredContentTypes.first { $0.conforms(to: type) }?.preferredFilenameExtension
                let base = provider.suggestedName ?? "Shared"
                let name = ext.map { (base as NSString).pathExtension.isEmpty ? "\(base).\($0)" : base } ?? base
                return .data(data, name: name)
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let text = await loadText(provider) {
            return .text(text)
        }
        return nil
    }

    private static func loadURL(_ provider: NSItemProvider, type: UTType) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private static func loadData(_ provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { text, _ in
                continuation.resume(returning: text as? String)
            }
        }
    }
}

/// "Send to" list shown in the share popover when several devices are connected.
private struct DeviceChooser: View {
    let devices: [ShareHandoff.Device]
    let choose: (ShareHandoff.Device) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send with Tether to")
                .font(.headline)

            VStack(spacing: 6) {
                ForEach(devices) { device in
                    Button {
                        choose(device)
                    } label: {
                        Label(device.name, systemImage: device.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .contentShape(.rect)
                    }
                    .controlSize(.large)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

#if DEBUG
#Preview {
    DeviceChooser(devices: [
        .init(id: "1", name: "Pixel 9 Pro", symbol: "iphone"),
        .init(id: "2", name: "Galaxy Tab S9", symbol: "ipad"),
    ], choose: { _ in }, cancel: {})
}
#endif
