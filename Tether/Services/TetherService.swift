//
//  TetherService.swift
//  Tether
//

import Foundation
import Combine
import SwiftUI
import UserNotifications

@MainActor
public final class TetherService: ObservableObject, UDPDiscoveryDelegate, TCPListenerDelegate, DeviceConnectionDelegate {
    public static let shared = TetherService()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var discoveredDevices: [DeviceInfo] = []
    @Published public private(set) var connectedDevices: [String: DeviceConnection] = [:]
    @Published public var incomingPairRequest: (connection: DeviceConnection, info: DeviceInfo)?
    @Published public private(set) var tailscaleStatus: TailscaleStatus = .notInstalled

    public let trustStore = TrustStore.shared
    public let pingPlugin = PingPlugin()
    public let clipboardPlugin = ClipboardPlugin()
    public let notificationPlugin = NotificationPlugin()
    public let batteryPlugin = BatteryPlugin()
    public let mediaControlPlugin = MediaControlPlugin()
    public let findMyPhonePlugin = FindMyPhonePlugin()
    public let lockDevicePlugin = LockDevicePlugin()
    public let connectivityReportPlugin = ConnectivityReportPlugin()
    public let telephonyPlugin = TelephonyPlugin()
    public let remoteVolumePlugin = RemoteVolumePlugin()
    public let macVolumePlugin = MacVolumePlugin()
    public let macMediaPlugin = MacMediaPlugin()
    public let sharePlugin = SharePlugin()
    public let mousepadPlugin = MousepadPlugin()
    public let presenterPlugin = PresenterPlugin()
    public let smsPlugin = SMSPlugin()
    public let contactsPlugin = ContactsPlugin()
    public let runCommandPlugin = RunCommandPlugin()
    public let sftpPlugin = SftpPlugin()

    private let udpDiscovery = UDPDiscoveryService()
    private var tailscaleTimer: DispatchSourceTimer?
    private let tcpListener = TCPListenerService()
    private var discoveredDeviceEndpoints: [String: (host: String, port: Int)] = [:]
    private var connectingDeviceIds = Set<String>()
    private var pendingConnections: [String: DeviceConnection] = [:]
    private var plugins: [TetherPlugin] = []
    nonisolated(unsafe) private let connectionLock = NSLock()
    nonisolated(unsafe) private var activeDeviceIds = Set<String>()
    /// Address of each connected device, so discovery doesn't re-announce to it.
    nonisolated(unsafe) private var activeHosts: [String: String] = [:]
    /// The live connection to each device, readable from any thread.
    nonisolated(unsafe) private var activeConnections: [String: DeviceConnection] = [:]
    /// Connections whose plugins have been started, so each starts exactly once.
    private var activatedConnections = Set<ObjectIdentifier>()

    private init() {
        self.plugins = [
            pingPlugin,
            clipboardPlugin,
            notificationPlugin,
            batteryPlugin,
            mediaControlPlugin,
            findMyPhonePlugin,
            lockDevicePlugin,
            connectivityReportPlugin,
            telephonyPlugin,
            remoteVolumePlugin,
            macVolumePlugin,
            macMediaPlugin,
            sharePlugin,
            mousepadPlugin,
            presenterPlugin,
            smsPlugin,
            contactsPlugin,
            runCommandPlugin,
            sftpPlugin
        ]
        udpDiscovery.delegate = self
        tcpListener.delegate = self
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        tcpListener.start()
        udpDiscovery.start()
        startTailscaleDiscovery()
        TetherLog("[TetherService] Service started successfully.")
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false

        udpDiscovery.stop()
        tcpListener.stop()
        tailscaleTimer?.cancel()
        tailscaleTimer = nil

        for conn in connectedDevices.values {
            conn.disconnect()
        }
        for conn in pendingConnections.values {
            conn.disconnect()
        }
        pendingConnections.removeAll()
        connectedDevices.removeAll()
        discoveredDevices.removeAll()
        connectingDeviceIds.removeAll()
        connectionLock.withLock {
            activeDeviceIds.removeAll()
            activeHosts.removeAll()
            activeConnections.removeAll()
        }
        TetherLog("[TetherService] Service stopped.")
    }

    // MARK: - UDP Discovery Delegate
    nonisolated public func isDeviceConnected(deviceId: String) -> Bool {
        connectionLock.withLock {
            activeDeviceIds.contains(deviceId)
        }
    }

    /// The device's current connection. A phone that reconnects (switching
    /// from Wi-Fi to Tailscale, say) gets a new one, so long-running work such
    /// as a multi-file send looks it up again instead of keeping the first.
    nonisolated public func connection(for deviceId: String) -> DeviceConnection? {
        connectionLock.withLock { activeConnections[deviceId] }
    }

    nonisolated public func connectedHosts() -> Set<String> {
        connectionLock.withLock {
            Set(activeHosts.values)
        }
    }

    nonisolated public func didDiscoverDevice(host: String, port: Int, deviceInfo: DeviceInfo) {
        Task { @MainActor in
            self.discoveredDeviceEndpoints[deviceInfo.deviceId] = (host, port)

            if !self.discoveredDevices.contains(where: { $0.deviceId == deviceInfo.deviceId }) {
                self.discoveredDevices.append(deviceInfo)
            }

            if let conn = self.connectedDevices[deviceInfo.deviceId], !conn.isDisconnected {
                return
            }

            if !self.connectingDeviceIds.contains(deviceInfo.deviceId) {
                // Only auto-connect if device is already paired in trustStore
                if self.trustStore.isTrusted(deviceId: deviceInfo.deviceId) {
                    self.connect(to: deviceInfo.deviceId, host: host, port: port)
                }
            }
        }
    }

    // MARK: - TCP Listener Delegate
    nonisolated public func didAcceptConnection(socketFD: Int32, clientIP: String, clientPort: Int) {
        Task { @MainActor in
            let key = "in_\(clientIP):\(clientPort)"
            let connection = DeviceConnection(socketFD: socketFD, host: clientIP, port: clientPort)
            self.pendingConnections[key] = connection
            connection.delegate = self
            connection.connect()
        }
    }

    // MARK: - Connection Management
    public func connect(to deviceId: String, host: String, port: Int) {
        guard connectedDevices[deviceId] == nil else { return }
        let key = "out_\(deviceId)"
        guard pendingConnections[key] == nil else { return }

        connectingDeviceIds.insert(deviceId)
        TetherLog("[TetherService] Connecting to \(deviceId) at \(host):\(port)")

        let connection = DeviceConnection(host: host, port: port, targetDeviceId: deviceId, isOutgoing: true)
        self.pendingConnections[key] = connection
        connection.delegate = self
        connection.connect()
    }

    // MARK: - DeviceConnectionDelegate
    nonisolated public func deviceConnectionDidConnect(_ connection: DeviceConnection) {
        Task { @MainActor in
            guard let id = connection.peerDeviceInfo?.deviceId else { return }
            self.connectingDeviceIds.remove(id)
            self.pendingConnections.removeValue(forKey: "out_\(id)")
            self.pendingConnections.removeValue(forKey: "in_\(connection.host):\(connection.port)")

            self.connectionLock.withLock {
                self.activeDeviceIds.insert(id)
                self.activeHosts[id] = connection.host
                self.activeConnections[id] = connection
            }
            self.udpDiscovery.noteHost(connection.host, belongsTo: id)

            if let old = self.connectedDevices[id], old !== connection {
                TetherLog("[TetherService] Seamlessly replacing previous connection to \(id) with new active connection.")
                self.connectedDevices[id] = connection
                if let pairReq = self.incomingPairRequest, pairReq.info.deviceId == id {
                    self.incomingPairRequest = (connection: connection, info: pairReq.info)
                }
                self.activatePlugins(for: connection)
                self.deactivatePlugins(for: old)
                old.disconnect()
                return
            }

            self.connectedDevices[id] = connection
            AwayLock.shared.phoneConnected(id)

            // Only a verified, paired device gets its plugins started.
            self.activatePlugins(for: connection)
            TetherLog("[TetherService] Connected to \(connection.peerDeviceInfo?.deviceName ?? id)")
        }
    }

    nonisolated public func deviceConnectionDidDisconnect(_ connection: DeviceConnection, error: Error?) {
        Task { @MainActor in
            let id = connection.peerDeviceInfo?.deviceId ?? connection.targetDeviceId
            if let id = id {
                self.connectingDeviceIds.remove(id)
                self.pendingConnections.removeValue(forKey: "out_\(id)")
                if self.connectedDevices[id] === connection {
                    self.connectionLock.withLock {
                        self.activeDeviceIds.remove(id)
                        self.activeHosts[id] = nil
                        self.activeConnections[id] = nil
                    }
                    self.connectedDevices.removeValue(forKey: id)
                    self.deactivatePlugins(for: connection)
                    TetherLog("[TetherService] Disconnected from \(connection.peerDeviceInfo?.deviceName ?? id)")
                    if let info = connection.peerDeviceInfo, info.deviceType == .phone, connection.pairState == .paired {
                        AwayLock.shared.phoneDisconnected(id, name: info.deviceName)
                    }
                }
            }
            self.pendingConnections.removeValue(forKey: "in_\(connection.host):\(connection.port)")

            // If we dialled out and never completed a handshake, announce ourselves
            // directly to the peer so it can dial back. Upstream does the same on any
            // connection error, and it is what makes pairing work on networks where
            // inbound connections to one of the two devices are blocked.
            if connection.isOutgoing, connection.peerDeviceInfo == nil {
                let listenPort = self.tcpListener.activePort == 0
                    ? TCPListenerService.minPort
                    : self.tcpListener.activePort
                TetherLog("[TetherService] Outgoing connection to \(connection.host) failed; inviting a reverse connection on port \(listenPort)")
                self.udpDiscovery.sendDirectPresence(to: connection.host, tcpPort: Int(listenPort))
            }
        }
    }

    nonisolated public func deviceConnection(_ connection: DeviceConnection, didReceivePacket packet: NetworkPacket) {
        Task { @MainActor in
            for plugin in self.plugins {
                if plugin.supportedPacketTypes.contains(packet.type) {
                    plugin.handlePacket(connection: connection, packet: packet)
                }
            }
        }

        // A packet may announce a binary payload that follows on a separate TLS
        // connection. Fetch it in the background and deliver the bytes separately.
        guard let size = packet.payloadSize, size > 0 else { return }
        // Notification artwork is small. Reject oversized announcements before
        // opening a payload socket or consuming disk space; text still arrives.
        if packet.type == "kdeconnect.notification",
           size > NotificationImages.maximumPayloadSize { return }
        guard let rawPort = packet.payloadTransferInfo?["port"]?.value,
              let port = Self.payloadPort(from: rawPort) else {
            TetherLog("[TetherService] \(packet.type) announced \(size) bytes but no usable payload port: \(String(describing: packet.payloadTransferInfo))")
            return
        }
        TetherLog("[TetherService] \(packet.type) announced \(size) bytes; fetching from \(connection.host):\(port)")

        PayloadDownloader.download(
            host: connection.host,
            port: port,
            size: size,
            expectedPeerFingerprint: connection.peerCertificateFingerprint,
            onProgress: { [weak self] fraction in
                Task { @MainActor in
                    guard let self else { return }
                    for plugin in self.plugins where plugin.supportedPacketTypes.contains(packet.type) {
                        plugin.handlePayloadProgress(connection: connection, packet: packet, fraction: fraction)
                    }
                }
            },
            completion: { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    let interested = self.plugins.filter { $0.supportedPacketTypes.contains(packet.type) }
                    switch result {
                    case .success(let fileURL):
                        for plugin in interested {
                            plugin.handlePayload(connection: connection, packet: packet, fileURL: fileURL)
                        }
                        // Plugins have moved or copied what they want to keep.
                        try? FileManager.default.removeItem(at: fileURL)
                    case .failure(let error):
                        TetherLog("[TetherService] Payload transfer failed for \(packet.type): \(error.localizedDescription)")
                        for plugin in interested {
                            plugin.handlePayloadFailure(connection: connection, packet: packet, error: error)
                        }
                    }
                }
            }
        )
    }

    /// Payload ports are integers on the wire, but tolerate a stringified value.
    nonisolated private static func payloadPort(from value: Any) -> UInt16? {
        switch value {
        case let int as Int: return UInt16(exactly: int)
        case let int64 as Int64: return UInt16(exactly: int64)
        case let number as NSNumber: return UInt16(exactly: number.intValue)
        case let string as String: return UInt16(string)
        default: return nil
        }
    }

    nonisolated public func deviceConnection(_ connection: DeviceConnection, didUpdatePairState state: PairState) {
        Task { @MainActor in
            guard let info = connection.peerDeviceInfo else { return }
            TetherLog("[TetherService] Pair state updated to \(state) for \(info.deviceName)")

            if state == .requestedByPeer {
                self.incomingPairRequest = (connection: connection, info: info)
                self.showPairingRequestNotification(info: info, connection: connection)
            } else if state == .paired {
                if self.incomingPairRequest?.info.deviceId == info.deviceId {
                    self.incomingPairRequest = nil
                }
                self.dismissPairingRequestNotification(deviceId: info.deviceId)
                self.activatePlugins(for: connection)
            } else if state == .notPaired {
                if let req = self.incomingPairRequest, req.connection === connection {
                    self.incomingPairRequest = nil
                    self.dismissPairingRequestNotification(deviceId: info.deviceId)
                }
                self.deactivatePlugins(for: connection)
            }
        }
    }

    /// Starts plugins for a connection once: when it is the device's active
    /// connection and verified as paired. Both conditions can become true in
    /// either order, so both paths call this.
    private func activatePlugins(for connection: DeviceConnection) {
        guard connection.pairState == .paired,
              let id = connection.peerDeviceInfo?.deviceId,
              connectedDevices[id] === connection,
              activatedConnections.insert(ObjectIdentifier(connection)).inserted else { return }
        for plugin in plugins {
            plugin.onConnected(connection: connection)
        }
    }

    private func deactivatePlugins(for connection: DeviceConnection) {
        guard activatedConnections.remove(ObjectIdentifier(connection)) != nil else { return }
        for plugin in plugins {
            plugin.onDisconnected(connection: connection)
        }
    }

    // MARK: - Pairing & User Actions
    public func requestPair(with deviceInfo: DeviceInfo) {
        if let conn = connectedDevices[deviceInfo.deviceId], !conn.isDisconnected {
            conn.requestPairing()
        } else if let endpoint = discoveredDeviceEndpoints[deviceInfo.deviceId] {
            let key = "out_\(deviceInfo.deviceId)"
            let connection = DeviceConnection(host: endpoint.host, port: endpoint.port, targetDeviceId: deviceInfo.deviceId, isOutgoing: true)
            connection.pendingPairingRequest = true
            connection.delegate = self
            self.pendingConnections[key] = connection
            connectingDeviceIds.insert(deviceInfo.deviceId)
            connection.connect()
        }
    }

    public func acceptIncomingPairRequest() {
        guard let pairReq = incomingPairRequest else { return }
        dismissPairingRequestNotification(deviceId: pairReq.info.deviceId)
        pairReq.connection.acceptPairing()
        incomingPairRequest = nil
    }

    public func rejectIncomingPairRequest() {
        guard let pairReq = incomingPairRequest else { return }
        dismissPairingRequestNotification(deviceId: pairReq.info.deviceId)
        pairReq.connection.rejectPairing()
        incomingPairRequest = nil
    }

    public func unpair(deviceId: String) {
        contactsPlugin.forget(deviceId: deviceId)
        dismissPairingRequestNotification(deviceId: deviceId)
        connectionLock.withLock {
            activeDeviceIds.remove(deviceId)
            activeHosts[deviceId] = nil
            activeConnections[deviceId] = nil
        }
        if let conn = connectedDevices[deviceId] {
            conn.unpair()
            deactivatePlugins(for: conn)
            connectedDevices.removeValue(forKey: deviceId)
        }
        trustStore.remove(deviceId: deviceId, reason: "unpaired on this Mac")
    }

    public func sendPing(to deviceId: String) {
        if let conn = connectedDevices[deviceId] {
            pingPlugin.sendPing(to: conn)
        }
    }

    // MARK: - Remote device actions

    public func ringPhone(_ deviceId: String) {
        guard let conn = connectedDevices[deviceId] else { return }
        findMyPhonePlugin.ring(deviceId: deviceId, connection: conn)
    }

    public func lockPhone(_ deviceId: String) {
        guard let conn = connectedDevices[deviceId] else { return }
        lockDevicePlugin.lock(connection: conn)
    }

    public func dialPhone(number: String, deviceId: String) {
        let cleanNumber = number.filter { "+0123456789".contains($0) }
        guard let url = URL(string: "tel:\(cleanNumber)") else { return }

        let conn = connectedDevices[deviceId]
        let host = conn?.host ?? ""

        // Target ADB address: explicit override, or files ADB, or auto phone host:5555
        let customAdb = UserDefaults.standard.string(forKey: MenuBarQuickActionsSettings.kashishAdbKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        let filesAdb = PhoneFilesController.shared.adbAddress(for: deviceId)
        let adbAddress: String
        if !customAdb.isEmpty {
            adbAddress = customAdb
        } else if !filesAdb.isEmpty {
            adbAddress = filesAdb
        } else if !host.isEmpty {
            adbAddress = "\(host):5555"
        } else {
            adbAddress = ""
        }

        let adbExecutable = ADBTransport.executable

        Task.detached { [weak self] in
            var adbSucceeded = false
            if let adb = adbExecutable, !adbAddress.isEmpty {
                // Try connecting to ADB
                let connectProc = Process()
                connectProc.executableURL = URL(fileURLWithPath: adb)
                connectProc.arguments = ["connect", adbAddress]
                let connectPipe = Pipe()
                connectProc.standardOutput = connectPipe
                connectProc.standardError = connectPipe
                try? connectProc.run()
                connectProc.waitUntilExit()
                let connectOut = String(decoding: connectPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                TetherLog("[TetherService] ADB connect \(adbAddress): \(connectOut.trimmingCharacters(in: .whitespacesAndNewlines))")

                // Execute CALL intent directly via root/shell (bypasses "tap to open")
                let callProc = Process()
                callProc.executableURL = URL(fileURLWithPath: adb)
                callProc.arguments = ["-s", adbAddress, "shell", "am", "start", "-a", "android.intent.action.CALL", "-d", "tel:\(cleanNumber)"]
                let callPipe = Pipe()
                callProc.standardOutput = callPipe
                callProc.standardError = callPipe
                try? callProc.run()
                callProc.waitUntilExit()
                let callOut = String(decoding: callPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                TetherLog("[TetherService] ADB direct call result (\(callProc.terminationStatus)): \(callOut.trimmingCharacters(in: .whitespacesAndNewlines))")

                if callProc.terminationStatus == 0 && (callOut.contains("Starting: Intent") || (!callOut.contains("error") && !callOut.contains("Error") && !callOut.contains("failed"))) {
                    adbSucceeded = true
                }
            }

            if !adbSucceeded {
                // Only send share URL if ADB couldn't place the direct call
                if let conn = conn, let self = self {
                    self.sharePlugin.sendURL(url, to: conn)
                    TetherLog("[TetherService] Fallback to share URL for \(cleanNumber) (device showed 'tap to open')")
                }
            }

            await MainActor.run {
                let content = UNMutableNotificationContent()
                let name = self?.contactsPlugin.contact(for: number, on: deviceId)?.name ?? "Kashish"
                content.title = adbSucceeded ? "Calling \(name) Directly" : "Calling \(name)"
                content.body = adbSucceeded ? "Direct root call placed to \(number)" : "Dialing \(number) on your phone..."
                content.sound = .default
                let request = UNNotificationRequest(identifier: "tether-call-\(UUID().uuidString)", content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
            }
        }
    }

    public func mediaAction(_ action: String, deviceId: String) {
        guard let conn = connectedDevices[deviceId] else { return }
        mediaControlPlugin.sendAction(action, connection: conn)
    }

    public func seekMediaPosition(_ positionMs: Int, deviceId: String) {
        guard let conn = connectedDevices[deviceId] else { return }
        mediaControlPlugin.setPosition(positionMs, connection: conn)
    }

    public func selectMediaPlayer(_ player: String, deviceId: String) {
        guard let conn = connectedDevices[deviceId] else { return }
        mediaControlPlugin.selectPlayer(player, connection: conn)
    }

    /// KDE Connect for Android takes volume changes only through its media
    /// controls (`kdeconnect.mpris.request` with `setVolume`), applied to the
    /// active player's stream, so this needs a media app with a session.
    /// `systemvolume` is the other direction on Android (the phone controlling a
    /// computer); only desktops report sinks for it.
    public func setPhoneVolume(_ volume: Int, deviceId: String) {
        guard let conn = connectedDevices[deviceId] else { return }
        if !(mediaControlPlugin.players[deviceId] ?? []).isEmpty {
            mediaControlPlugin.setVolume(volume, connection: conn)
        } else if let sink = remoteVolumePlugin.sinks[deviceId]?.first(where: { $0.enabled })
                    ?? remoteVolumePlugin.sinks[deviceId]?.first {
            remoteVolumePlugin.setVolume(sinkName: sink.name, volume: volume, connection: conn)
        }
    }

    public func setSinkVolume(sinkName: String, volume: Int, deviceId: String) {
        guard let conn = connectedDevices[deviceId] else { return }
        remoteVolumePlugin.setVolume(sinkName: sinkName, volume: volume, connection: conn)
    }

    public func setSinkMuted(sinkName: String, muted: Bool, deviceId: String) {
        guard let conn = connectedDevices[deviceId] else { return }
        remoteVolumePlugin.setMuted(sinkName: sinkName, muted: muted, connection: conn)
    }

    public func silenceRinger(deviceId: String) {
        telephonyPlugin.muteRinger(deviceId: deviceId)
    }

    public func silenceAlarms(deviceId: String) {
        let activeNotifs = notificationPlugin.notifications[deviceId] ?? []
        for notif in activeNotifs {
            let app = notif.appName.lowercased()
            let title = notif.title.lowercased()
            let text = notif.text.lowercased()
            if app.contains("clock") || app.contains("alarm") || title.contains("alarm") || text.contains("alarm") || title.contains("timer") || text.contains("timer") {
                notificationPlugin.dismiss(notif)
            }
        }
        if let conn = connectedDevices[deviceId] {
            let sinks = remoteVolumePlugin.sinks[deviceId] ?? []
            for sink in sinks where sink.name.lowercased().contains("alarm") || sink.description.lowercased().contains("alarm") {
                remoteVolumePlugin.setMuted(sinkName: sink.name, muted: true, connection: conn)
                remoteVolumePlugin.setVolume(sinkName: sink.name, volume: 0, connection: conn)
            }
        }
        TetherLog("[TetherService] Silenced alarms for \(deviceId)")
    }

    public func silencePhone(deviceId: String) {
        // Silence ringer & incoming calls
        silenceRinger(deviceId: deviceId)

        // Silence / dismiss any alarms or timers
        silenceAlarms(deviceId: deviceId)

        // Mute system volume sinks
        if let conn = connectedDevices[deviceId] {
            let sinks = remoteVolumePlugin.sinks[deviceId] ?? []
            for sink in sinks {
                let name = sink.name.lowercased()
                let desc = sink.description.lowercased()
                if name.contains("ring") || desc.contains("ring") || name.contains("alarm") || desc.contains("alarm") || name.contains("notif") || desc.contains("notif") {
                    remoteVolumePlugin.setMuted(sinkName: sink.name, muted: true, connection: conn)
                    remoteVolumePlugin.setVolume(sinkName: sink.name, volume: 0, connection: conn)
                }
            }
        }
        TetherLog("[TetherService] Silenced phone (calls, alarms, notifications) for \(deviceId)")
    }

    public func unsilencePhone(deviceId: String) {
        if let conn = connectedDevices[deviceId] {
            let sinks = remoteVolumePlugin.sinks[deviceId] ?? []
            for sink in sinks {
                remoteVolumePlugin.setMuted(sinkName: sink.name, muted: false, connection: conn)
                if sink.volume == 0 {
                    let restoreVol = max(1, Int(0.6 * Double(sink.maxVolume)))
                    remoteVolumePlugin.setVolume(sinkName: sink.name, volume: restoreVol, connection: conn)
                }
            }
        }
        TetherLog("[TetherService] Unsilenced phone for \(deviceId)")
    }

    public func setPhoneSilenced(_ silenced: Bool, deviceId: String) {
        if silenced {
            silencePhone(deviceId: deviceId)
        } else {
            unsilencePhone(deviceId: deviceId)
        }
    }

    /// Re-reads media and volume state, e.g. when the popover opens.
    public func refreshRemoteState(deviceId: String) {
        guard let conn = connectedDevices[deviceId] else { return }
        mediaControlPlugin.requestState(connection: conn)
        remoteVolumePlugin.requestSinks(connection: conn)
    }

    /// `thorough` sweeps the whole subnet, as the "Look for Devices" buttons do.
    /// Otherwise it's the routine broadcast, which leaves connected phones
    /// alone: KDE Connect on Android answers any announcement by opening a new
    /// connection and dropping its current one.
    public func refreshDiscovery(thorough: Bool = true) {
        if thorough {
            udpDiscovery.broadcastPresence(sweepSubnet: true)
        } else {
            udpDiscovery.broadcastPresence(routine: true)
        }
        refreshTailscale()
    }

    /// Adds a peer by IPv4 address or host name (including Tailscale MagicDNS
    /// names). Returns false if the name doesn't resolve.
    public func addManualPeer(address: String) async -> Bool {
        let host = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let ip = await Task.detached { HostResolver.ipv4(for: host) }.value
        guard let ip else {
            TetherLog("[TetherService] Could not resolve \(host)")
            return false
        }
        TetherLog("[TetherService] Adding manual peer \(host) (\(ip))")
        udpDiscovery.addKnownTarget(ip: ip)
        udpDiscovery.sendDirectPresence(to: ip)
        udpDiscovery.broadcastPresence(sweepSubnet: false)
        return true
    }

    // MARK: - Tailscale

    private func startTailscaleDiscovery() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        // Peers come and go as phones sleep or switch networks; a minute keeps
        // reconnection quick without spawning the CLI constantly.
        timer.schedule(deadline: .now(), repeating: .seconds(60))
        timer.setEventHandler { [weak self] in
            Task { @MainActor in self?.refreshTailscale() }
        }
        timer.resume()
        tailscaleTimer = timer
    }

    /// Re-reads the tailnet and points discovery at the user's online phones.
    public func refreshTailscale() {
        let discovery = udpDiscovery
        Task.detached(priority: .utility) {
            let enabled = TailscaleDiscovery.isEnabled
            let status = TailscaleDiscovery.currentStatus()
            var targets = Set<String>()
            if enabled, case .running(_, let phones) = status {
                targets = Set(phones.map(\.ip))
            }
            await MainActor.run { [weak self] in
                discovery.setTailscaleTargets(targets)
                if self?.tailscaleStatus != status { self?.tailscaleStatus = status }
            }
        }
    }

    public func sendFiles(_ urls: [URL], to deviceId: String) {
        guard let conn = connectedDevices[deviceId] else { return }
        sharePlugin.sendFiles(urls, to: conn)
    }

    public func sendText(_ text: String, to deviceId: String) {
        guard let conn = connectedDevices[deviceId] else { return }
        sharePlugin.sendText(text, to: conn)
    }

    public func sendURL(_ url: URL, to deviceId: String) {
        guard let conn = connectedDevices[deviceId] else { return }
        sharePlugin.sendURL(url, to: conn)
    }

    // MARK: - Notifications
    private func showPairingRequestNotification(info: DeviceInfo, connection: DeviceConnection) {
        let content = UNMutableNotificationContent()
        content.title = "Pairing Request"
        content.subtitle = info.deviceName
        if let fp = connection.peerCertificateFingerprint {
            content.body = "Verification Key:\n\(fp.prefix(23))..."
        } else {
            content.body = "\(info.deviceName) wants to pair with this Mac."
        }
        content.sound = .default
        content.categoryIdentifier = "TETHER_PAIR_REQUEST_CATEGORY"
        content.userInfo = ["deviceId": info.deviceId]

        let request = UNNotificationRequest(
            identifier: "kde_pair_\(info.deviceId)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                TetherLog("[TetherService] Failed to post pairing notification: \(error)")
            }
        }
    }

    private func dismissPairingRequestNotification(deviceId: String) {
        let id = "kde_pair_\(deviceId)"
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
