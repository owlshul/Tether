//
//  MenuBarView.swift
//  Tether
//
//  Menu bar popover. Laid out like Control Center: the connected device and its
//  controls up top, then menu-style rows for the app itself.
//

import SwiftUI
import AppKit

public struct MenuBarView: View {
    @Bindable var appModel: TetherAppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var isDropTargeted = false

    public init(appModel: TetherAppModel) {
        self.appModel = appModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let request = appModel.incomingPairRequest {
                pairRequestCard(request)
            }

            if let device = appModel.primaryDevice {
                deviceCard(device)
                if device.hasNowPlaying {
                    nowPlayingCard(device)
                }
            } else {
                emptyCard
            }

            if !appModel.availableDevices.isEmpty {
                nearbyCard
            }

            Divider()
                .padding(.horizontal, 6)

            VStack(spacing: 0) {
                if let release = UpdateController.shared.availableRelease {
                    MenuRow(title: "Update to Tether \(release.version)…", systemImage: "arrow.down.circle") {
                        UpdateController.shared.showWindow()
                    }
                }
                MenuRow(title: "Open Tether", systemImage: "macwindow") { openMainWindow() }
                MenuRow(title: "Settings…", systemImage: "gearshape") {
                    openSettings()
                    NSApp.activate()
                }
                MenuRow(title: "Quit Tether", systemImage: "power") { NSApp.terminate(nil) }
            }
        }
        .padding(10)
        .frame(width: 320)
        .dropDestination(for: URL.self) { urls, _ in
            guard let device = appModel.primaryDevice else { return false }
            let files = urls.filter(\.isFileURL)
            device.sendFiles(files)
            return !files.isEmpty
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted, let device = appModel.primaryDevice {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .overlay {
                        Label("Send to \(device.name)", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: .capsule)
                    }
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { appModel.refreshDiscovery() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Tether")
                .font(.headline)
            Spacer()
            Text(appModel.connectedDevices.isEmpty ? "Not Connected" : "Connected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }

    private func deviceCard(_ device: DeviceViewModel) -> some View {
        PopoverCard {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    DeviceSymbol(type: device.deviceType)
                        .font(.title)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.name)
                            .font(.headline)
                            .lineLimit(1)
                        HStack(spacing: 10) {
                            if let battery = device.batteryPercent {
                                BatteryLabel(percent: battery, isCharging: device.isCharging)
                            }
                            if let network = device.networkType, !network.isEmpty {
                                Text(network)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if appModel.connectedDevices.count > 1 {
                        Menu {
                            Picker("Device", selection: $appModel.selectedDeviceId) {
                                ForEach(appModel.connectedDevices) { Text($0.name).tag(Optional($0.id)) }
                            }
                            .pickerStyle(.inline)
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .menuStyle(.button)
                        .menuIndicator(.hidden)
                        .buttonStyle(.borderless)
                        .fixedSize()
                        .accessibilityLabel("Choose device")
                    }
                }

                HStack(spacing: 0) {
                    CircleAction(title: "Find", systemImage: "speaker.wave.3") { device.findMyPhone() }
                    if device.canLock {
                        CircleAction(title: "Lock", systemImage: "lock") { device.lockDevice() }
                    }
                    CircleAction(title: "Clipboard", systemImage: "doc.on.clipboard") { device.sendClipboard() }
                    CircleAction(title: "Send File", systemImage: "square.and.arrow.up") {
                        NSApp.activate()
                        device.sendFiles(FilePicker.chooseFiles(sendingTo: device.name))
                    }
                }
            }
        }
    }

    private func nowPlayingCard(_ device: DeviceViewModel) -> some View {
        PopoverCard {
            HStack(spacing: 10) {
                Group {
                    if let image = device.albumArt {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.quaternary)
                    }
                }
                .frame(width: 38, height: 38)
                .clipShape(.rect(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.nowPlayingTitle ?? "")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(device.nowPlayingArtist ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                HStack(spacing: 12) {
                    Button(device.nowPlayingIsPlaying ? "Pause" : "Play",
                           systemImage: device.nowPlayingIsPlaying ? "pause.fill" : "play.fill") {
                        device.playPauseMedia()
                    }
                    .contentTransition(.symbolEffect(.replace))
                    Button("Next", systemImage: "forward.fill") { device.nextMedia() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.title3)
            }
        }
    }

    private func pairRequestCard(_ request: PairRequestViewModel) -> some View {
        PopoverCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    DeviceSymbol(type: request.deviceType)
                        .font(.title2)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Pairing Request")
                            .font(.subheadline.weight(.semibold))
                        Text("\(request.deviceName) wants to pair")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button {
                        appModel.rejectIncomingPairRequest()
                    } label: {
                        Text("Decline").frame(maxWidth: .infinity)
                    }
                    Button {
                        appModel.acceptIncomingPairRequest()
                    } label: {
                        Text("Pair").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var emptyCard: some View {
        PopoverCard {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text(appModel.offlineDevices.isEmpty ? "No Devices" : "Not Connected")
                        .font(.subheadline.weight(.medium))
                    Text(appModel.offlineDevices.isEmpty
                         ? "Open KDE Connect on your phone to pair."
                         : "Looking for \(appModel.offlineDevices.map(\.name).formatted(.list(type: .or)))…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var nearbyCard: some View {
        PopoverCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nearby")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(appModel.availableDevices) { device in
                    HStack(spacing: 10) {
                        DeviceSymbol(type: device.deviceType, isActive: false)
                            .frame(width: 20)
                        Text(device.name)
                            .lineLimit(1)
                        Spacer()
                        if device.isAwaitingPairing {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Pair") { device.pair() }
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

// MARK: - Pieces

private struct PopoverCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12, style: .continuous))
    }
}

private struct CircleAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .imageScale(.medium)
                    .fontWeight(.medium)
                    .frame(width: 36, height: 36)
                    .background(.tint.opacity(0.15), in: .circle)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A full-width row that highlights on hover, like an NSMenu item.
private struct MenuRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .foregroundStyle(isHovering ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(isHovering ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

#if DEBUG
#Preview("Connected") {
    MenuBarView(appModel: .mock())
}

#Preview("Pair request") {
    MenuBarView(appModel: .mockPairRequest())
}

#Preview("Empty") {
    MenuBarView(appModel: .mockEmpty())
}
#endif
