//
//  OverviewPane.swift
//  Tether
//
//  A connected device's home: who it is and how it's doing, what it's playing,
//  recent files, and whether it can drive this Mac. Laid out like a device
//  page in System Settings: one grouped form, no dashboard.
//

import SwiftUI

struct OverviewPane: View {
    @Bindable var device: DeviceViewModel
    let onSelectSection: (DeviceSection) -> Void

    var body: some View {
        Form {
            Section {
                header
            }

            Section("Now Playing") {
                NowPlayingRows(device: device)
            }

            Section {
                if device.transfers.isEmpty {
                    Text("Drop files anywhere in this window to send them. Files from \(device.name) are saved to Downloads.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(device.transfers.prefix(3)) { item in
                        TransferRow(item: item)
                    }
                }
            } header: {
                HStack {
                    Text("Recent Files")
                    Spacer()
                    if device.transfers.count > 3 {
                        Button("Show All") { onSelectSection(.files) }
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                }
            }

            RemoteInputSection()
        }
        .formStyle(.grouped)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: device.deviceType.systemImageName)
                .resizable()
                .scaledToFit()
                .fontWeight(.light)
                .foregroundStyle(.tint)
                .frame(width: 34, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 12) {
                    Text("Connected")
                    if let battery = device.batteryPercent {
                        BatteryLabel(percent: battery, isCharging: device.isCharging)
                    }
                    if let network = device.networkType, !network.isEmpty {
                        Label {
                            Text(network)
                        } icon: {
                            Image(systemName: "cellularbars", variableValue: Double(device.cellularSignalStrength ?? 0) / 4)
                        }
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Now playing

private struct NowPlayingRows: View {
    @Bindable var device: DeviceViewModel
    @State private var draftVolume: Float = 0.5
    @State private var isEditingVolume = false

    var body: some View {
        HStack(spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 2) {
                Text(device.hasNowPlaying ? device.nowPlayingTitle ?? "" : "Nothing Playing")
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 16) {
                Button("Previous", systemImage: "backward.fill") { device.previousMedia() }
                Button(device.nowPlayingIsPlaying ? "Pause" : "Play",
                       systemImage: device.nowPlayingIsPlaying ? "pause.fill" : "play.fill") {
                    device.playPauseMedia()
                }
                .contentTransition(.symbolEffect(.replace))
                Button("Next", systemImage: "forward.fill") { device.nextMedia() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .imageScale(.large)
            .disabled(!device.hasNowPlaying)
        }

        LabeledContent("Volume") {
            Slider(value: $draftVolume, in: 0...1) {
                Text("Volume")
            } minimumValueLabel: {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
            } maximumValueLabel: {
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            } onEditingChanged: { editing in
                isEditingVolume = editing
                // Send once when the drag ends rather than on every tick.
                if !editing { device.setVolume(draftVolume) }
            }
            .labelsHidden()
            .frame(maxWidth: 260)
            .disabled(!device.canSetVolume)
            .help(device.canSetVolume ? "Media volume on \(device.name)" : "Start playing something on \(device.name) to change its volume")
        }
        .onAppear { draftVolume = device.volume }
        .onChange(of: device.volume) {
            if !isEditingVolume { draftVolume = device.volume }
        }
    }

    private var subtitle: String? {
        guard device.hasNowPlaying else { return nil }
        let parts = [device.nowPlayingArtist, device.nowPlayingAlbum].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = device.albumArt {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(.rect(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(.quaternary, in: .rect(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Remote input

private struct RemoteInputSection: View {
    @State private var isTrusted = InputSynthesizer.shared.isAccessibilityTrusted
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        Section {
            LabeledContent("Trackpad, keyboard & presenter") {
                if isTrusted {
                    Text("Ready")
                } else {
                    Button("Allow…") { InputSynthesizer.shared.openAccessibilitySettings() }
                }
            }
        } header: {
            Text("Remote Input")
        } footer: {
            Text(isTrusted
                 ? "Open Remote Input or Presentation in KDE Connect on your phone to control this Mac."
                 : "Tether needs Accessibility access to move the pointer and type for your phone.")
                .foregroundStyle(.secondary)
        }
        // Re-check when the window regains focus, e.g. after visiting System Settings.
        .onChange(of: controlActiveState) {
            isTrusted = InputSynthesizer.shared.isAccessibilityTrusted
        }
    }
}

#if DEBUG
#Preview {
    OverviewPane(device: .mockConnectedPhone()) { _ in }
        .frame(width: 640, height: 720)
}
#endif
