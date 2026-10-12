//
//  PluginProtocol.swift
//  Tether
//

import Foundation

public protocol TetherPlugin: AnyObject, Sendable {
    var supportedPacketTypes: [String] { get }
    func onConnected(connection: DeviceConnection)
    func onDisconnected(connection: DeviceConnection)
    func handlePacket(connection: DeviceConnection, packet: NetworkPacket)
}

public extension TetherPlugin {
    /// Called after a packet that announced a binary payload has finished downloading.
    ///
    /// Payloads travel over a separate TLS connection, so `handlePacket` fires first
    /// (with the announcement) and this fires later. The bytes are streamed to a
    /// temporary file rather than held in memory; a plugin that wants to keep it
    /// must move or copy it before returning; it is deleted afterwards.
    func handlePayload(connection: DeviceConnection, packet: NetworkPacket, fileURL: URL) {}

    /// Download progress for a payload announced by `packet`, from 0 to 1.
    func handlePayloadProgress(connection: DeviceConnection, packet: NetworkPacket, fraction: Double) {}

    /// The payload announced by `packet` could not be received.
    func handlePayloadFailure(connection: DeviceConnection, packet: NetworkPacket, error: Error) {}
}
