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
//  macOS doesn't let other apps read what's playing, so the phone sees the
//  controls and whether something is playing, but no track title.
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

    public init() {}

    public func onConnected(connection: DeviceConnection) {}
    public func onDisconnected(connection: DeviceConnection) {}

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
                queue.asyncAfter(deadline: .now() + 0.6) { connection.send(packet: self.nowPlaying()) }
            }
        }

        if packet.has("setVolume"), let device = SystemAudio.defaultOutputDevice() {
            SystemAudio.setVolume(Float32(packet.int(for: "setVolume")) / 100, on: device)
        }

        if packet.bool(for: "requestNowPlaying") || packet.bool(for: "requestVolume") {
            connection.send(packet: nowPlaying())
        }
    }

    private func nowPlaying() -> NetworkPacket {
        let volume = SystemAudio.defaultOutputDevice().flatMap(SystemAudio.volume(of:)).map { Int(($0 * 100).rounded()) } ?? 0
        return NetworkPacket(type: Self.reportType, body: [
            "player": Self.playerName,
            "title": "Media on this Mac",
            "artist": "",
            "album": "",
            "isPlaying": SystemAudio.isPlaying(),
            "canPause": true,
            "canPlay": true,
            "canGoNext": true,
            "canGoPrevious": true,
            "canSeek": false,
            "pos": 0,
            "length": 0,
            "volume": volume,
        ])
    }
}
