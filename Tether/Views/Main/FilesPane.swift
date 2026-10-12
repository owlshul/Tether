//
//  FilesPane.swift
//  Tether
//

import SwiftUI
import AppKit

struct FilesPane: View {
    let device: DeviceViewModel

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button("Choose Files…") {
                        device.sendFiles(FilePicker.chooseFiles(sendingTo: device.name))
                    }
                } label: {
                    Text("Send to \(device.name)")
                    Text("Or drop files anywhere in this window.")
                }
            }

            Section {
                if device.transfers.isEmpty {
                    Text("Nothing sent or received yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(device.transfers) { item in
                        TransferRow(item: item)
                    }
                }
            } header: {
                HStack {
                    Text("Transfers")
                    Spacer()
                    Button("Open Downloads") {
                        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                            NSWorkspace.shared.open(downloads)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            } footer: {
                Text("Files from \(device.name) are saved to your Downloads folder.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct TransferRow: View {
    let item: TransferItem

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: FileIcon.image(for: item.filename))
                .resizable()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if item.status == .transferring {
                    ProgressView(value: item.progress)
                        .controlSize(.small)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailing
        }
        .contentShape(.rect)
        .onTapGesture(count: 2) {
            if let url = item.localURL, item.status == .completed { NSWorkspace.shared.open(url) }
        }
        .contextMenu {
            if let url = item.localURL {
                Button("Open") { NSWorkspace.shared.open(url) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
    }

    private var detail: String {
        let direction = item.direction == .incoming ? "From \(item.deviceName)" : "To \(item.deviceName)"
        let size = ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file)
        switch item.status {
        case .transferring:
            let done = ByteCountFormatter.string(fromByteCount: item.transferredBytes, countStyle: .file)
            return "\(direction) · \(done) of \(size)"
        case .failed(let reason):
            return "\(direction) · Failed: \(reason)"
        case .queued:
            return "\(direction) · Waiting"
        case .cancelled:
            return "\(direction) · Cancelled"
        case .completed:
            return "\(direction) · \(size) · \(item.timestamp.formatted(.relative(presentation: .named)))"
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch item.status {
        case .transferring:
            Text(item.progress, format: .percent.precision(.fractionLength(0)))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        case .completed:
            if let url = item.localURL {
                Button("Show in Finder", systemImage: "magnifyingglass.circle.fill") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .imageScale(.large)
                .foregroundStyle(.secondary)
                .help("Show in Finder")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Sent")
            }
        case .failed(let reason):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(reason)
                .accessibilityLabel("Failed: \(reason)")
        case .queued, .cancelled:
            EmptyView()
        }
    }
}

#if DEBUG
#Preview {
    FilesPane(device: .mockConnectedPhone())
        .frame(width: 760, height: 600)
}
#endif
