//
//  MenuBarView.swift
//  Tether
//
//  Menu bar popover: floating glass panels, the connected phone first (wearing
//  the same picture as the phone card in the window), then menu-style rows.
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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                header
                    .staggeredEntrance(0)

                if let request = appModel.incomingPairRequest {
                    pairRequestCard(request)
                        .staggeredEntrance(1)
                }

                if let device = appModel.primaryDevice {
                    if device.isRinging {
                        ringingCallBanner(device)
                            .staggeredEntrance(1)
                    }

                    if let alarmNotif = device.activeAlarmNotification {
                        alarmBanner(device, notification: alarmNotif)
                            .staggeredEntrance(1)
                    }

                    deviceCard(device)
                        .staggeredEntrance(1)

                    nowPlayingCard(device)
                        .staggeredEntrance(2)

                    volumeCard(device)
                        .staggeredEntrance(2)

                    notificationsCard(device)
                        .staggeredEntrance(3)
                } else {
                    emptyCard
                        .staggeredEntrance(1)
                }

                if !appModel.availableDevices.isEmpty {
                    nearbyCard
                        .staggeredEntrance(4)
                }

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
            .padding(12)
        }
        .frame(width: 350)
        .frame(maxHeight: 620)
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
        // Just the routine announcement: a full sweep makes a connected phone reconnect.
        .onAppear {
            appModel.refreshDiscovery(thorough: false)
            if let device = appModel.primaryDevice {
                appModel.refreshRemoteState(deviceId: device.id)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Tether")
                .font(.title3.weight(.bold))
            Spacer()
            let connected = !appModel.connectedDevices.isEmpty
            Label(connected ? "Connected" : "Not Connected", systemImage: "circle.fill")
                .labelStyle(StatusDotLabelStyle(color: connected ? .green : .secondary))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }

    private func deviceCard(_ device: DeviceViewModel) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: device.deviceType.systemImageName)
                    .font(.system(size: 26, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 10) {
                        if let battery = device.batteryPercent {
                            Label("\(battery)%", systemImage: DeviceSymbols.battery(battery, charging: device.isCharging))
                        }
                        if let network = device.networkType, !network.isEmpty {
                            Label(network, systemImage: "cellularbars")
                        }
                        if device.isViaTailscale {
                            Label("Tailscale", systemImage: "point.3.connected.trianglepath.dotted")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if appModel.connectedDevices.count > 1 { deviceSwitcher }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)

            callKashishButton(for: device)

            HStack(spacing: 0) {
                GlassCircleButton(title: "Find", systemImage: "speaker.wave.3.fill", size: 40) { device.findMyPhone() }
                    .frame(maxWidth: .infinity)
                if device.canLock {
                    GlassCircleButton(title: "Lock", systemImage: "lock.fill", size: 40) { device.lockDevice() }
                        .frame(maxWidth: .infinity)
                }
                GlassCircleButton(
                    title: device.isSilenced ? "Unsilence" : "Silence",
                    systemImage: device.isSilenced ? "bell.slash.fill" : "bell.fill",
                    size: 40,
                    isProminent: device.isSilenced
                ) {
                    device.toggleSilence()
                }
                .frame(maxWidth: .infinity)
                GlassCircleButton(title: "Clipboard", systemImage: "doc.on.clipboard", size: 40) { device.sendClipboard() }
                    .frame(maxWidth: .infinity)
                GlassCircleButton(title: "Send Files", systemImage: "arrow.up.doc", size: 40) {
                    NSApp.activate()
                    device.sendFiles(FilePicker.chooseFiles(sendingTo: device.name))
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 2)
        }
        .padding(8)
        .glassPanel(radius: 20)
    }

    private var deviceSwitcher: some View {
        Menu {
            Picker("Device", selection: $appModel.selectedDeviceId) {
                ForEach(appModel.connectedDevices) { Text($0.name).tag(Optional($0.id)) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "chevron.up.chevron.down")
                .font(.callout.weight(.semibold))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .fixedSize()
        .accessibilityLabel("Choose device")
    }

    private func callKashishButton(for device: DeviceViewModel) -> some View {
        Button {
            device.callKashish()
        } label: {
            HStack(spacing: 8) {
                if let photoData = device.kashishPhotoData, let nsImage = NSImage(data: photoData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.green, lineWidth: 1.5))
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 26, height: 26)
                        Image(systemName: "phone.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text("Call \(device.kashishDisplayName)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("• One-Tap")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    Text(device.kashishPhoneNumber)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "phone.arrow.up.right.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Color.green, in: Circle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.green.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func ringingCallBanner(_ device: DeviceViewModel) -> some View {
        PopoverCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "phone.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.callerName ?? "Incoming Call")
                        .font(.headline)
                        .lineLimit(1)
                    Text("Ringing on \(device.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    device.silenceRinger()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.slash.fill")
                        Text("Silence")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.85), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func alarmBanner(_ device: DeviceViewModel, notification: PhoneNotification) -> some View {
        PopoverCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(notification.title.isEmpty ? notification.appName : notification.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(notification.text.isEmpty ? "Active alarm / timer" : notification.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    device.silenceAlarms()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.slash.fill")
                        Text("Dismiss")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func nowPlayingCard(_ device: DeviceViewModel) -> some View {
        NowPlayingCardView(device: device)
    }

    private func volumeCard(_ device: DeviceViewModel) -> some View {
        PhoneVolumeCard(device: device)
    }

    private func notificationsCard(_ device: DeviceViewModel) -> some View {
        MenuBarNotificationsCard(device: device)
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
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(radius: 20)
    }
}

/// A label whose icon is a small coloured status dot.
private struct StatusDotLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            configuration.title
        }
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

// MARK: - Now Playing Card

private struct NowPlayingCardView: View {
    @Bindable var device: DeviceViewModel

    var body: some View {
        PopoverCard {
            VStack(spacing: 8) {
                // Header with Now Playing label and Player selector
                HStack {
                    Label("Now Playing", systemImage: "music.note")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if device.availablePlayers.count > 1 {
                        Menu {
                            ForEach(device.availablePlayers, id: \.self) { player in
                                Button {
                                    device.selectPlayer(player)
                                } label: {
                                    if player == device.nowPlayingPlayer {
                                        Label(player, systemImage: "checkmark")
                                    } else {
                                        Text(player)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "hifispeaker.fill").font(.system(size: 9))
                                Text(device.nowPlayingPlayer ?? "Player")
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 7, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                    } else if let player = device.nowPlayingPlayer, !player.isEmpty {
                        Text(player)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                    }
                }

                // Artwork, Title, and Transport Controls
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
                    .frame(width: 42, height: 42)
                    .clipShape(.rect(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.nowPlayingTitle?.isEmpty == false ? device.nowPlayingTitle! : "Media Player")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        let artistText = device.nowPlayingArtist?.isEmpty == false ? device.nowPlayingArtist! : (device.nowPlayingAlbum ?? "")
                        if !artistText.isEmpty {
                            Text(artistText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if !device.hasNowPlaying {
                            Text(device.nowPlayingPlayer ?? "Music controls")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 12) {
                        Button("Previous", systemImage: "backward.fill") { device.previousMedia() }
                            .disabled(!device.nowPlayingCanGoPrevious && device.hasNowPlaying)

                        Button(device.nowPlayingIsPlaying ? "Pause" : "Play",
                               systemImage: device.nowPlayingIsPlaying ? "pause.fill" : "play.fill") {
                            device.playPauseMedia()
                        }
                        .contentTransition(.symbolEffect(.replace))

                        Button("Next", systemImage: "forward.fill") { device.nextMedia() }
                            .disabled(!device.nowPlayingCanGoNext && device.hasNowPlaying)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.title3)
                }

                // Scrubber / Seek Bar
                NowPlayingScrubberView(device: device)
            }
        }
    }
}

private struct NowPlayingScrubberView: View {
    @Bindable var device: DeviceViewModel
    @State private var scrubFraction: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        if device.nowPlayingLength > 0 {
            VStack(spacing: 2) {
                Slider(value: Binding(
                    get: { isScrubbing ? scrubFraction : device.nowPlayingProgressFraction },
                    set: { scrubFraction = $0 }
                ), in: 0...1) { editing in
                    isScrubbing = editing
                    if !editing {
                        let targetMs = Int(scrubFraction * Double(device.nowPlayingLength))
                        device.seekPosition(targetMs)
                    }
                }
                .controlSize(.mini)

                HStack {
                    Text(isScrubbing ? formatTime(Int(scrubFraction * Double(device.nowPlayingLength))) : device.nowPlayingElapsedLabel)
                    Spacer()
                    Text(device.nowPlayingLengthLabel)
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
    }

    private func formatTime(_ ms: Int) -> String {
        let seconds = max(0, ms / 1000)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Phone Volume Card

private struct PhoneVolumeCard: View {
    @Bindable var device: DeviceViewModel

    var body: some View {
        PopoverCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("Phone Volume & Audio", systemImage: "speaker.wave.2.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        device.toggleSilence()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: device.isSilenced ? "bell.slash.fill" : "bell.fill")
                            Text(device.isSilenced ? "Unsilence All" : "Silence All")
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(device.isSilenced ? Color.orange : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(device.isSilenced ? "Click to unsilence and restore sound" : "Click to silence calls, alarms, and media")
                }

                // Media volume slider is always shown
                MediaVolumeRow(device: device)

                if !device.audioSinks.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(device.audioSinks) { sink in
                            let name = sink.name.lowercased()
                            let desc = sink.description.lowercased()
                            if !name.contains("music") && !desc.contains("music") {
                                AudioSinkRow(device: device, sink: sink)
                            }
                        }
                    }
                }

                // Quick Silence Controls
                HStack(spacing: 6) {
                    QuickSilenceButton(
                        title: device.isSilenced ? "Unsilence" : "Silence",
                        systemImage: device.isSilenced ? "bell.slash.fill" : "bell.fill",
                        isActive: device.isSilenced
                    ) {
                        device.toggleSilence()
                    }

                    QuickSilenceButton(title: "Mute Calls", systemImage: "phone.down.fill") {
                        device.silenceRinger()
                    }
                    QuickSilenceButton(title: "Stop Alarms", systemImage: "alarm.fill") {
                        device.silenceAlarms()
                    }
                    if !device.notifications.isEmpty {
                        QuickSilenceButton(title: "Clear Notifs", systemImage: "bell.slash") {
                            for notif in device.notifications {
                                device.dismiss(notif)
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

private struct QuickSilenceButton: View {
    let title: String
    let systemImage: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.orange.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
            .foregroundStyle(isActive ? Color.orange : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct AudioSinkRow: View {
    @Bindable var device: DeviceViewModel
    let sink: AudioSink
    @State private var draftVolume: Double = 0
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                device.setSinkMuted(name: sink.name, muted: !sink.muted)
            } label: {
                Image(systemName: iconName)
                    .foregroundStyle(sink.muted ? .secondary : .primary)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(friendlyName)
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text("\(Int((isDragging ? draftVolume : currentFraction) * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(value: Binding(
                    get: { isDragging ? draftVolume : currentFraction },
                    set: { draftVolume = $0 }
                ), in: 0...1) { editing in
                    isDragging = editing
                    if !editing {
                        let targetVol = Int(draftVolume * Double(sink.maxVolume))
                        device.setSinkVolume(name: sink.name, volume: targetVol)
                    }
                }
                .controlSize(.mini)
            }
        }
        .onAppear { draftVolume = currentFraction }
        .onChange(of: currentFraction) {
            if !isDragging { draftVolume = currentFraction }
        }
    }

    private var currentFraction: Double {
        sink.maxVolume > 0 ? Double(sink.volume) / Double(sink.maxVolume) : 0
    }

    private var friendlyName: String {
        let desc = sink.description.lowercased()
        let name = sink.name.lowercased()
        if desc.contains("ring") || name.contains("ring") { return "Ringtone" }
        if desc.contains("alarm") || name.contains("alarm") { return "Alarm" }
        if desc.contains("notif") || name.contains("notif") { return "Notification" }
        if desc.contains("music") || desc.contains("media") || name.contains("music") || name.contains("media") { return "Media" }
        if desc.contains("call") || desc.contains("voice") || name.contains("voice") { return "Calls" }
        return sink.description.isEmpty ? sink.name : sink.description
    }

    private var iconName: String {
        if sink.muted { return "speaker.slash.fill" }
        let desc = sink.description.lowercased()
        let name = sink.name.lowercased()
        if desc.contains("ring") || name.contains("ring") { return "bell.fill" }
        if desc.contains("alarm") || name.contains("alarm") { return "alarm.fill" }
        if desc.contains("notif") || name.contains("notif") { return "bubble.left.fill" }
        if desc.contains("music") || desc.contains("media") || name.contains("music") || name.contains("media") { return "speaker.wave.2.fill" }
        if desc.contains("call") || desc.contains("voice") || name.contains("voice") { return "phone.fill" }
        return "speaker.wave.2.fill"
    }
}

private struct MediaVolumeRow: View {
    @Bindable var device: DeviceViewModel
    @State private var draftVolume: Float = 0.5
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if device.volume > 0 {
                    device.preSilenceVolume = device.volume
                    device.setVolume(0)
                } else {
                    let restore = device.preSilenceVolume ?? 0.5
                    device.setVolume(restore)
                }
            } label: {
                Image(systemName: device.volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .foregroundStyle(device.volume > 0 ? .primary : .secondary)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .help(device.volume > 0 ? "Mute media" : "Unmute media")

            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text("Media Volume")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text("\(Int((isDragging ? draftVolume : device.volume) * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(value: Binding(
                    get: { isDragging ? draftVolume : device.volume },
                    set: { draftVolume = $0 }
                ), in: 0...1) { editing in
                    isDragging = editing
                    if !editing {
                        device.setVolume(draftVolume)
                    }
                }
                .controlSize(.mini)
            }
        }
        .onAppear { draftVolume = device.volume }
        .onChange(of: device.volume) {
            if !isDragging { draftVolume = device.volume }
        }
    }
}

// MARK: - Phone Notifications Card

private struct MenuBarNotificationsCard: View {
    @Bindable var device: DeviceViewModel
    @State private var isExpanded = false

    var body: some View {
        PopoverCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Notifications", systemImage: "bell.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !device.notifications.isEmpty {
                        Text("\(device.notifications.count)")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.tint, in: .capsule)
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    if !device.notifications.isEmpty {
                        Button("Clear All") {
                            for notif in device.notifications {
                                device.dismiss(notif)
                            }
                        }
                        .font(.caption2)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }

                if device.notifications.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.slash")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text("No notifications from \(device.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    let displayed = isExpanded ? device.notifications : Array(device.notifications.prefix(3))
                    VStack(spacing: 8) {
                        ForEach(displayed) { notif in
                            MenuBarNotificationRow(notification: notif, device: device)
                            if notif.id != displayed.last?.id {
                                Divider()
                            }
                        }

                        if device.notifications.count > 3 {
                            Button(isExpanded ? "Show Less" : "Show All (\(device.notifications.count))") {
                                withAnimation(.snappy(duration: 0.2)) {
                                    isExpanded.toggle()
                                }
                            }
                            .font(.caption2.weight(.medium))
                            .buttonStyle(.borderless)
                            .foregroundStyle(.tint)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 2)
                        }
                    }
                }
            }
        }
    }
}

private struct MenuBarNotificationRow: View {
    let notification: PhoneNotification
    let device: DeviceViewModel

    @State private var isReplying = false
    @State private var replyText = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(notification.appName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tint)
                Spacer()
                Text(notification.date.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Button {
                    device.dismiss(notification)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss on phone")
                .padding(.leading, 4)
            }

            if !notification.title.isEmpty {
                Text(notification.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }

            if !notification.text.isEmpty {
                Text(notification.text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(isReplying ? 4 : 2)
            }

            if isReplying {
                HStack(spacing: 6) {
                    TextField("Reply…", text: $replyText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .focused($isFieldFocused)
                        .onSubmit(sendReply)

                    Button("Cancel") {
                        isReplying = false
                        replyText = ""
                    }
                    .font(.caption2)
                    .buttonStyle(.borderless)

                    Button("Send", action: sendReply)
                        .font(.caption2.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 4)
                .onAppear { isFieldFocused = true }
            } else {
                HStack(spacing: 12) {
                    if let code = notification.code {
                        Button {
                            NotificationPlugin.copyToPasteboard(code)
                        } label: {
                            Label("Copy \(code)", systemImage: "doc.on.doc")
                                .font(.caption2.weight(.medium))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.tint)
                    }

                    if notification.replyId != nil {
                        Button {
                            withAnimation(.snappy) {
                                isReplying = true
                            }
                        } label: {
                            Label("Reply", systemImage: "arrowshape.turn.up.left.fill")
                                .font(.caption2.weight(.medium))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.tint)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func sendReply() {
        let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        device.reply(to: notification, text: trimmed)
        isReplying = false
        replyText = ""
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
