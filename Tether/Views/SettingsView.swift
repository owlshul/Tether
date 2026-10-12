//
//  SettingsView.swift
//  Tether
//

import SwiftUI
import UserNotifications

public struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings(viewModel: viewModel)
            }
            Tab("Devices", systemImage: "iphone.gen3") {
                DevicesSettings(viewModel: viewModel)
            }
            Tab("Permissions", systemImage: "hand.raised") {
                PermissionsSettings(viewModel: viewModel)
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettings()
            }
        }
        .frame(width: 560, height: 460)
        .onAppear { viewModel.refresh() }
    }
}

// MARK: - About

/// Who made Tether, shared with the app menu's About panel.
enum TetherCredits {
    static let author = "Subhash"
    static let authorURL = URL(string: "https://github.com/subhashhhhhh")!
    static let sourceURL = URL(string: "https://github.com/subhashhhhhh/Tether")!
    static let issuesURL = URL(string: "https://github.com/subhashhhhhh/Tether/issues")!

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "Version \(short) (\(build))"
    }

    /// Credits for the standard About panel.
    static var aboutPanelCredits: NSAttributedString {
        let text = NSMutableAttributedString(
            string: "Made by \(author)\n",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)]
        )
        text.append(NSAttributedString(
            string: "github.com/subhashhhhhh/Tether",
            attributes: [.link: sourceURL, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        ))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        return text
    }

    static func showAboutPanel() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: aboutPanelCredits])
    }
}

struct AboutSettings: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    Text("Tether")
                        .font(.title2.weight(.semibold))
                    Text(TetherCredits.version)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                LabeledContent("Made by") {
                    Link(TetherCredits.author, destination: TetherCredits.authorURL)
                }
                LabeledContent("Source code") {
                    Link("github.com/subhashhhhhh/Tether", destination: TetherCredits.sourceURL)
                }
                LabeledContent("Found a bug?") {
                    Link("Report an issue", destination: TetherCredits.issuesURL)
                }
            }

            Section {
                Text("Tether is free software under the GPL-2.0 license. It works with KDE Connect, but is an independent project and isn't affiliated with KDE.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var name = ""
    @AppStorage(MotionPreference.key) private var reduceMotion = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .onSubmit { viewModel.saveDeviceName(name) }
                    .onAppear { name = viewModel.deviceName }
            } header: {
                Text("This Mac")
            } footer: {
                Text("Shown on your phone in KDE Connect. Press Return to save.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open at Login", isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                ))
                Toggle(isOn: $reduceMotion) {
                    Text("Reduce motion")
                    Text("Turns off Tether's animations, such as the drop highlight and list changes.")
                }
            }

            TailscaleSection(viewModel: viewModel)

            Section("Identity") {
                LabeledContent("Device ID") {
                    Text(viewModel.deviceId)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("Certificate") {
                    VStack(alignment: .trailing, spacing: 1) {
                        ForEach(FingerprintFormat.rows(viewModel.certificateFingerprint), id: \.self) { Text($0) }
                    }
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                }
                LabeledContent("Listening on", value: "Port \(viewModel.listeningPort)")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tailscale

private struct TailscaleSection: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Section {
            Toggle("Find devices over Tailscale", isOn: $viewModel.isTailscaleDiscoveryEnabled)
                .disabled(!isRunning)
            LabeledContent("Status") {
                Text(statusText)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Tailscale")
        } footer: {
            Text("Connects to your phone from anywhere when both devices are on your Tailscale network. Tether only contacts Android and iOS devices signed in to your own Tailscale account.")
                .foregroundStyle(.secondary)
        }
    }

    private var isRunning: Bool {
        if case .running = viewModel.tailscaleStatus { return true }
        return false
    }

    private var statusText: String {
        switch viewModel.tailscaleStatus {
        case .notInstalled:
            return "Not installed"
        case .notRunning:
            return "Not connected"
        case .running(let selfIP, let phones):
            if phones.isEmpty { return "Connected as \(selfIP), no phones online" }
            return "Connected as \(selfIP) · \(phones.map(\.name).formatted(.list(type: .and)))"
        }
    }
}

// MARK: - Devices

private struct DevicesSettings: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var deviceToUnpair: PairedDevice?

    var body: some View {
        Form {
            if viewModel.pairedDevices.isEmpty {
                Section {
                    Text("No paired devices. Pair from KDE Connect on your phone, or from the Tether window.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(viewModel.pairedDevices) { device in
                Section {
                    Toggle("Share clipboard", isOn: Binding(
                        get: { device.isClipboardSyncEnabled },
                        set: { viewModel.setSync(deviceId: device.deviceId, clipboard: $0, notifications: device.isNotificationSyncEnabled) }
                    ))
                    Toggle("Show phone notifications", isOn: Binding(
                        get: { device.isNotificationSyncEnabled },
                        set: { viewModel.setSync(deviceId: device.deviceId, clipboard: device.isClipboardSyncEnabled, notifications: $0) }
                    ))
                    LabeledContent("Paired", value: device.pairedDate.formatted(date: .abbreviated, time: .omitted))
                    if let lastSeen = device.lastSeenDate {
                        LabeledContent("Last connected", value: lastSeen.formatted(.relative(presentation: .named)))
                    }
                } header: {
                    HStack(spacing: 8) {
                        DeviceSymbol(type: device.deviceType)
                        Text(device.deviceName)
                        Spacer()
                        Button("Unpair…", role: .destructive) { deviceToUnpair = device }
                            .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Unpair \(deviceToUnpair?.deviceName ?? "device")?",
            isPresented: Binding(get: { deviceToUnpair != nil }, set: { if !$0 { deviceToUnpair = nil } }),
            presenting: deviceToUnpair
        ) { device in
            Button("Unpair", role: .destructive) { viewModel.unpair(deviceId: device.deviceId) }
        } message: { device in
            Text("You'll need to pair again from \(device.deviceName) to reconnect.")
        }
    }
}

// MARK: - Permissions

private struct PermissionsSettings: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Notifications",
                    detail: "Show phone notifications and let you reply from banners.",
                    systemImage: "bell.badge",
                    state: notificationState
                ) {
                    if viewModel.notificationAuthStatus == .notDetermined {
                        Button("Allow") { viewModel.requestNotificationPermission() }
                    } else {
                        Button("Open Settings…") { viewModel.openNotificationSettings() }
                    }
                }

                PermissionRow(
                    title: "Accessibility",
                    detail: "Let your phone move the pointer, type and click as a remote trackpad and presenter.",
                    systemImage: "cursorarrow.motionlines",
                    state: viewModel.isAccessibilityTrusted ? .granted : .needed
                ) {
                    if !viewModel.isAccessibilityTrusted {
                        Button("Allow…") { viewModel.promptAccessibility() }
                    }
                }
            } footer: {
                Text("Tether talks to your devices directly, over your local network or Tailscale. Nothing is sent to a server.")
                    .foregroundStyle(.secondary)
            }

            Section("Presenter") {
                LabeledContent("Laser pointer") {
                    Button("Show Test Pointer") {
                        PresenterOverlayWindowController.shared.update(xPos: 0.5, yPos: 0.5)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: controlActiveState) { viewModel.refresh() }
    }

    private var notificationState: PermissionState {
        switch viewModel.notificationAuthStatus {
        case .authorized, .provisional, .ephemeral: .granted
        case .denied: .denied
        default: .needed
        }
    }
}

private enum PermissionState { case granted, needed, denied }

private struct PermissionRow<Action: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    let state: PermissionState
    @ViewBuilder var action: Action

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                    statusBadge
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch state {
        case .granted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Allowed")
        case .denied:
            Text("Off").font(.caption.weight(.medium)).foregroundStyle(.orange)
        case .needed:
            Text("Not allowed").font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView(viewModel: .mock())
}

#Preview("Permissions needed") {
    SettingsView(viewModel: .mockDenied())
}

#Preview("About") {
    AboutSettings()
        .frame(width: 560, height: 460)
}
#endif
