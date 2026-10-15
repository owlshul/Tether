//
//  MacMediaPlugin.swift
//  Tether
//
//  This Mac as a media player in KDE Connect's Multimedia control on the
//  phone: play, pause, next and previous for whatever is playing on the Mac,
//  and its volume. Like desktop KDE Connect on Windows, it's one player that
//  drives the system's media controls rather than one per app. The phone's
//  volume tab for this Mac lives in that same screen, so it needs this player
//  to exist at all.
//
//  What's playing comes from NowPlayingReader. Where macOS won't tell, the
//  phone still gets the controls and the volume, without a title.
//
//  MediaControlPlugin is the other direction: this Mac controlling the phone.
//

import Foundation

public final class MacMediaPlugin: TetherPlugin, @unchecked Sendable {
    static let requestType = "kdeconnect.mpris.request"
    static let reportType = "kdeconnect.mpris"
    static let playerName = "This Mac"

    public let supportedPacketTypes = [requestType]

    private let queue = DispatchQueue(label: "com.subhashh.tether.macmedia")
    private var connections: [String: DeviceConnection] = [:]
    private let reader = NowPlayingReader.shared

    public init() {
        reader.onChange = { [weak self] state in
            guard let self else { return }
            self.queue.async {
                let packet = self.nowPlaying(state)
                for connection in self.connections.values { connection.send(packet: packet) }
            }
        }
    }

    /// The reader runs only while a phone is connected.
    public func onConnected(connection: DeviceConnection) {
        guard let id = connection.peerDeviceInfo?.deviceId else { return }
        queue.async {
            if self.connections.isEmpty { self.reader.start() }
            self.connections[id] = connection
        }
    }

    public func onDisconnected(connection: DeviceConnection) {
        guard let id = connection.peerDeviceInfo?.deviceId else { return }
        queue.async {
            guard self.connections[id] === connection else { return }
            self.connections[id] = nil
            if self.connections.isEmpty { self.reader.stop() }
        }
    }

    public func handlePacket(connection: DeviceConnection, packet: NetworkPacket) {
        guard packet.type == Self.requestType else { return }
        queue.async { self.handle(packet, from: connection) }
    }

    private func handle(_ packet: NetworkPacket, from connection: DeviceConnection) {
        if packet.bool(for: "requestPlayerList") || packet.string(for: "player") != Self.playerName {
            TetherLog("[MacMedia] \(connection.peerDeviceInfo?.deviceName ?? "Phone") asked for this Mac's players")
            connection.send(packet: NetworkPacket(type: Self.reportType, body: [
                "playerList": [Self.playerName],
                "supportAlbumArtPayload": false,
            ]))
            return
        }

        if let action = packet.string(for: "action") {
            let command: MediaRemote.Command? = switch action {
            case "Play": .play
            case "Pause": .pause
            case "PlayPause": .togglePlayPause
            case "Stop": .stop
            case "Next": .nextTrack
            case "Previous": .previousTrack
            default: nil
            }
            if let command {
                MediaRemote.send(command)
                // Report the new state once the player has reacted.
                queue.asyncAfter(deadline: .now() + 0.6) { connection.send(packet: self.nowPlaying(self.reader.state())) }
            }
        }

        // "SetPosition" is milliseconds into the track; "Seek" moves by microseconds.
        if packet.has("SetPosition") {
            reader.seek(to: Double(packet.int64(for: "SetPosition")) / 1000)
        } else if packet.has("Seek"), let state = reader.state() {
            reader.seek(to: state.position + Double(packet.int64(for: "Seek")) / 1_000_000)
        }

        if packet.has("setVolume"), let device = SystemAudio.defaultOutputDevice() {
            SystemAudio.setVolume(Float32(packet.int(for: "setVolume")) / 100, on: device)
        }

        if packet.bool(for: "requestNowPlaying") || packet.bool(for: "requestVolume") {
            connection.send(packet: nowPlaying(reader.state()))
        }
    }

    private func nowPlaying(_ state: MacNowPlaying?) -> NetworkPacket {
        let volume = SystemAudio.defaultOutputDevice().flatMap(SystemAudio.volume(of:)).map { Int(($0 * 100).rounded()) } ?? 0
        return NetworkPacket(type: Self.reportType, body: [
            "player": Self.playerName,
            "title": state?.title ?? "Media on this Mac",
            "artist": state?.artist ?? "",
            "album": state?.album ?? "",
            "isPlaying": state?.isPlaying ?? SystemAudio.isPlaying(),
            "canPause": true,
            "canPlay": true,
            "canGoNext": true,
            "canGoPrevious": true,
            "canSeek": (state?.duration ?? 0) > 0,
            // Milliseconds.
            "pos": Int64((state?.position ?? 0) * 1000),
            "length": Int64((state?.duration ?? 0) * 1000),
            "volume": volume,
        ])
    }
}
