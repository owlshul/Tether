//
//  UpdateWindowView.swift
//  Tether
//

import SwiftUI

struct UpdateWindowView: View {
    let controller: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(20)
        .frame(width: 480)
    }

    private var title: String {
        switch controller.state {
        case .available(let release), .installing(let release, _): "Tether \(release.version) is available"
        case .upToDate: "Tether is up to date"
        case .failed: "Update failed"
        case .checking, .idle: "Checking for updates…"
        }
    }

    private var subtitle: String {
        switch controller.state {
        case .available, .installing: "You have version \(controller.currentVersion)."
        case .upToDate: "Version \(controller.currentVersion) is the newest version."
        case .failed(let message): message
        case .checking, .idle: "Looking for a newer version on GitHub."
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .available(let release):
            ReleaseNotesView(notes: release.notes)
            HStack {
                Button("Skip This Version") { controller.skip() }
                Spacer()
                if controller.canInstall {
                    Button("Later") { controller.closeWindow() }
                        .keyboardShortcut(.cancelAction)
                    Button("Install and Relaunch") { controller.install() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Later") { controller.closeWindow() }
                        .keyboardShortcut(.cancelAction)
                    Button("Download…") { controller.openReleasePage() }
                        .keyboardShortcut(.defaultAction)
                }
            }

        case .installing(let release, let phase):
            ReleaseNotesView(notes: release.notes)
            VStack(alignment: .leading, spacing: 6) {
                if let fraction = phase.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                HStack {
                    Text(phase.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Button("Cancel") { controller.cancelInstall() }
                        .disabled(phase == .installing)
                }
            }

        case .checking, .idle:
            ProgressView()
                .progressViewStyle(.linear)

        case .upToDate:
            HStack {
                Spacer()
                Button("OK") { controller.closeWindow() }
                    .keyboardShortcut(.defaultAction)
            }

        case .failed:
            HStack {
                Button("Download from GitHub…") { controller.openReleasePage() }
                Spacer()
                Button("Close") { controller.closeWindow() }
                    .keyboardShortcut(.cancelAction)
                Button("Try Again") { controller.checkForUpdates() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Lays out the release notes' Markdown: AttributedString handles only inline
/// styling, so headings and bullets are placed by hand.
struct ReleaseNotesView: View {
    let notes: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .heading(let text):
                        Text(inline(text))
                            .font(.headline)
                            .padding(.top, 6)
                    case .bullet(let text):
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•").foregroundStyle(.secondary)
                            Text(inline(text))
                        }
                    case .paragraph(let text):
                        Text(inline(text))
                    }
                }
            }
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(height: 220)
        .background(.background.secondary, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }

    private enum Block {
        case heading(String)
        case bullet(String)
        case paragraph(String)
    }

    private var blocks: [Block] {
        notes.split(separator: "\n").compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return nil }
            if line.hasPrefix("#") {
                return .heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                return .bullet(String(line.dropFirst(2)))
            }
            return .paragraph(line)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

#if DEBUG
#Preview("Release notes") {
    ReleaseNotesView(notes: """
        ### 📤 Tether in the Share menu
        - Choose **Share › Tether** in Finder, Photos and Safari.
        - With more than one phone connected, Tether asks which one.
        ### 🗂️ Sending several files now works
        - **Fixed:** files larger than 128 KB could arrive cut off.
        """)
    .padding()
    .frame(width: 480)
}
#endif
