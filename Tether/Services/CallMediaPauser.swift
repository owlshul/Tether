//
//  CallMediaPauser.swift
//  Tether
//
//  Pauses whatever is playing on the Mac while the phone rings or a call is
//  under way, and resumes it afterwards, like desktop KDE Connect's "Pause
//  media during calls". It only resumes what it paused itself.
//

import CoreAudio
import Foundation

@MainActor
final class CallMediaPauser {
    static let shared = CallMediaPauser()

    /// Settings › General › "Pause media during calls". On by default.
    static let settingKey = "tether_pause_media_during_calls"

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.settingKey) as? Bool ?? true
    }

    /// Calls under way, as "deviceId/event".
    private var activeCalls = Set<String>()
    private var pausedForCall = false
    private var resumeTask: Task<Void, Never>?

    func callStarted(_ key: String) {
        activeCalls.insert(key)
        resumeTask?.cancel()
        guard isEnabled, !pausedForCall, Self.isAudioPlaying() else { return }
        MediaRemote.send(.pause)
        pausedForCall = true
        TetherLog("[Calls] Paused media for a call")
    }

    func callEnded(_ key: String) {
        activeCalls.remove(key)
        guard activeCalls.isEmpty, pausedForCall else { return }
        // Ringing ends just before "talking" starts when a call is answered;
        // waiting a moment keeps the music from blipping back on in between.
        resumeTask?.cancel()
        resumeTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, activeCalls.isEmpty, pausedForCall else { return }
            pausedForCall = false
            MediaRemote.send(.play)
            TetherLog("[Calls] Resumed media after the call")
        }
    }

    /// Whether the Mac's sound output is in use, by any app.
    private static func isAudioPlaying() -> Bool {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else {
            return false
        }
        var running = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }
}

/// Play and pause through the system's Now Playing controls, the same path
/// as the keyboard's media keys, but as explicit commands rather than a
/// toggle, so a pause never starts anything.
private enum MediaRemote {
    enum Command: UInt32 {
        case play = 0
        case pause = 1
    }

    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool

    private static let sendCommand: SendCommand? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
              let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(symbol, to: SendCommand.self)
    }()

    static func send(_ command: Command) {
        _ = sendCommand?(command.rawValue, nil)
    }
}
