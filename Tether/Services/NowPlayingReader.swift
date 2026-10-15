//
//  NowPlayingReader.swift
//  Tether
//
//  What's playing on the Mac (a song in Music, a video in Safari), for the
//  phone's Multimedia control. Since macOS 15.4 only Apple-signed programs may
//  read Now Playing, so this runs MediaRemoteAdapter (Vendor/, BSD licence)
//  through /usr/bin/perl, which streams changes as JSON lines. If a future
//  macOS closes that door, the stream ends, the reader gives up after a few
//  tries, and the phone keeps the controls without a title.
//

import AppKit

nonisolated struct MacNowPlaying: Sendable, Equatable {
    var title = ""
    var artist = ""
    var album = ""
    var isPlaying = false
    /// Seconds.
    var duration: Double = 0
    /// Seconds into the track at `timestamp`.
    var elapsed: Double = 0
    var timestamp = Date()

    /// Where playback is now, estimated from the last report.
    var position: Double {
        let now = elapsed + (isPlaying ? Date().timeIntervalSince(timestamp) : 0)
        return duration > 0 ? min(now, duration) : now
    }
}

nonisolated final class NowPlayingReader: @unchecked Sendable {
    static let shared = NowPlayingReader()

    /// Called on the reader's queue whenever what's playing changes.
    var onChange: ((MacNowPlaying?) -> Void)?

    private let queue = DispatchQueue(label: "com.subhashh.tether.nowplaying")
    private var process: Process?
    private var buffer = Data()
    private var wanted = false
    private var failures = 0
    private(set) var current: MacNowPlaying?

    private init() {
        // The reader is a separate process; it would outlive Tether otherwise.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.sync {
                self?.wanted = false
                self?.process?.terminate()
            }
        }
    }

    private var script: URL? { Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl") }
    private var framework: URL? { Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework") }

    func start() {
        queue.async {
            self.wanted = true
            self.failures = 0
            self.launch()
        }
    }

    func stop() {
        queue.async {
            self.wanted = false
            self.process?.terminate()
            self.process = nil
        }
    }

    func state() -> MacNowPlaying? {
        queue.sync { current }
    }

    /// Moves playback to `seconds` into the track.
    func seek(to seconds: Double) {
        guard let script, let framework else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, framework.path, "seek", String(Int64(max(seconds, 0) * 1_000_000))]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // MARK: - Stream

    private func launch() {
        guard wanted, process == nil, let script, let framework else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, framework.path, "stream", "--no-diff", "--no-artwork", "--debounce=200"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let started = Date()

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.queue.async { self?.consume(data) }
        }
        process.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            self?.queue.async {
                guard let self else { return }
                self.process = nil
                guard self.wanted else { return }
                // A stream that dies right away won't work on this macOS.
                self.failures = Date().timeIntervalSince(started) < 10 ? self.failures + 1 : 0
                guard self.failures < 3 else {
                    TetherLog("[NowPlaying] The Now Playing reader keeps stopping; the phone will show controls only")
                    self.publish(nil)
                    return
                }
                self.queue.asyncAfter(deadline: .now() + 5) { self.launch() }
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            TetherLog("[NowPlaying] Couldn't start the Now Playing reader: \(error.localizedDescription)")
        }
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = object["payload"] as? [String: Any] else { continue }
            publish(Self.parse(payload))
        }
    }

    static func parse(_ payload: [String: Any]) -> MacNowPlaying? {
        guard let title = payload["title"] as? String, !title.isEmpty else { return nil }
        var state = MacNowPlaying()
        state.title = title
        state.artist = payload["artist"] as? String ?? ""
        state.album = payload["album"] as? String ?? ""
        state.isPlaying = payload["playing"] as? Bool ?? false
        state.duration = payload["duration"] as? Double ?? 0
        state.elapsed = payload["elapsedTime"] as? Double ?? 0
        if let stamp = payload["timestamp"] as? String, let date = ISO8601DateFormatter().date(from: stamp) {
            state.timestamp = date
        }
        return state
    }

    private func publish(_ state: MacNowPlaying?) {
        guard state != current else { return }
        current = state
        onChange?(state)
    }
}
