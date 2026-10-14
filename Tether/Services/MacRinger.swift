//
//  MacRinger.swift
//  Tether
//
//  "Ring" in KDE Connect on the phone: the Mac plays a ringtone at full
//  volume until it's stopped here, rung again from the phone, or a minute
//  passes. The previous volume and mute setting come back afterwards.
//

import AppKit
import AudioToolbox
import CoreAudio
import SwiftUI

@MainActor
final class MacRinger {
    static let shared = MacRinger()

    private var sound: NSSound?
    private var panel: NSPanel?
    private var savedVolume: Float32?
    private var savedMute: UInt32?
    private var timeout: Task<Void, Never>?

    var isRinging: Bool { sound != nil }

    /// A ring request starts ringing; another one while ringing stops it, as on the phone.
    func toggle(from deviceName: String) {
        if isRinging {
            stop()
        } else {
            start(from: deviceName)
        }
    }

    func start(from deviceName: String) {
        guard !isRinging else { return }
        TetherLog("[Ring] \(deviceName) is ringing this Mac")

        let output = Self.defaultOutputDevice()
        if let output {
            savedVolume = Self.volume(of: output)
            savedMute = Self.mute(of: output)
            Self.setMute(0, on: output)
            Self.setVolume(1, on: output)
        }

        let sound = Self.ringtone()
        sound?.loops = true
        sound?.play()
        self.sound = sound ?? NSSound()

        showPanel(deviceName: deviceName)
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            if !Task.isCancelled { self?.stop() }
        }
    }

    func stop() {
        guard isRinging else { return }
        timeout?.cancel()
        timeout = nil
        sound?.stop()
        sound = nil
        if let output = Self.defaultOutputDevice() {
            if let savedVolume { Self.setVolume(savedVolume, on: output) }
            if let savedMute { Self.setMute(savedMute, on: output) }
        }
        savedVolume = nil
        savedMute = nil
        panel?.close()
        panel = nil
    }

    // MARK: - Panel

    private func showPanel(deviceName: String) {
        let view = RingingView(deviceName: deviceName) { [weak self] in self?.stop() }
        let hosting = NSHostingView(rootView: view)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .hudWindow, .utilityWindow],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = hosting
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel
    }

    // MARK: - Sound

    private static func ringtone() -> NSSound? {
        let ringtones = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/Ringtones/"
        for name in ["Opening.m4r", "Radar.m4r", "Alarm.m4r"] {
            if let sound = NSSound(contentsOfFile: ringtones + name, byReference: true) { return sound }
        }
        return NSSound(named: "Glass")
    }

    // MARK: - Output volume (Core Audio)

    private static func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func volume(of device: AudioObjectID) -> Float32? {
        var address = volumeAddress()
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func setVolume(_ value: Float32, on device: AudioObjectID) {
        var address = volumeAddress()
        var value = value
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    private static func mute(of device: AudioObjectID) -> UInt32? {
        var address = muteAddress()
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func setMute(_ value: UInt32, on device: AudioObjectID) {
        var address = muteAddress()
        var value = value
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}

private struct RingingView: View {
    let deviceName: String
    let stop: () -> Void
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.and.waves.left.and.right.fill")
                .font(.system(size: 42))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, options: .repeating, value: pulse)
            VStack(spacing: 4) {
                Text("Ringing this Mac")
                    .font(.title2.weight(.bold))
                Text("\(deviceName) asked to find this Mac.")
                    .foregroundStyle(.secondary)
            }
            Button(action: stop) {
                Text("Stop").frame(minWidth: 140)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .onExitCommand(perform: stop)
        .onAppear { pulse = true }
    }
}
