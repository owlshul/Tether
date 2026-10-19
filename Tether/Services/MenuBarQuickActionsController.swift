//
//  MenuBarQuickActionsController.swift
//  Tether
//
//  Manages standalone clickable action icons in the macOS menu bar (top bar)
//  for quick access to Find Phone, Send Clipboard, Send Files, and Battery.
//

import AppKit
import SwiftUI
import Combine

public enum MenuBarQuickActionsSettings {
    public static let showQuickActionsKey = "TetherShowMenuBarQuickActions"
    public static let showSilencePhoneKey = "TetherShowMenuBarSilencePhone"
    public static let showMediaKey = "TetherShowMenuBarMedia"
    public static let showFindPhoneKey = "TetherShowMenuBarFindPhone"
    public static let showClipboardKey = "TetherShowMenuBarClipboard"
    public static let showSendFilesKey = "TetherShowMenuBarSendFiles"
    public static let showBatteryKey = "TetherShowMenuBarBattery"

    public static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showQuickActionsKey: true,
            showSilencePhoneKey: true,
            showMediaKey: true,
            showFindPhoneKey: true,
            showClipboardKey: true,
            showSendFilesKey: true,
            showBatteryKey: true
        ])
    }
}

@MainActor
public final class MenuBarQuickActionsController: NSObject {
    public static let shared = MenuBarQuickActionsController()

    private weak var appModel: TetherAppModel?
    private var cancellables = Set<AnyCancellable>()

    private var silenceItem: NSStatusItem?
    private var mediaItem: NSStatusItem?
    private var findPhoneItem: NSStatusItem?
    private var clipboardItem: NSStatusItem?
    private var sendFilesItem: NSStatusItem?

    private var isStarted = false

    private override init() {
        super.init()
        MenuBarQuickActionsSettings.registerDefaults()
    }

    public func start(with model: TetherAppModel) {
        self.appModel = model
        guard !isStarted else {
            updateItems()
            return
        }
        isStarted = true

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateItems()
            }
            .store(in: &cancellables)

        if NSApp != nil && NSApp.isRunning {
            setupStatusItems()
            updateItems()
        } else {
            NotificationCenter.default.publisher(for: NSApplication.didFinishLaunchingNotification)
                .first()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.setupStatusItems()
                    self?.updateItems()
                }
                .store(in: &cancellables)
        }
    }

    public func update(appModel: TetherAppModel) {
        self.appModel = appModel
        updateItems()
    }

    private func setupStatusItems() {
        // Silence Phone item
        let silence = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        silence.autosaveName = "com.subhashh.tether.action.silence"
        if let button = silence.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let img = NSImage(systemSymbolName: "bell.slash.fill", accessibilityDescription: "Silence Phone")?.withSymbolConfiguration(config)
            img?.isTemplate = true
            button.image = img
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleSilencePhone(_:))
            button.sendAction(on: [.leftMouseUp])
        }
        self.silenceItem = silence

        // Media (Music Play/Pause) item
        let media = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        media.autosaveName = "com.subhashh.tether.action.media"
        if let button = media.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let img = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Music")?.withSymbolConfiguration(config)
            img?.isTemplate = true
            button.image = img
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleMediaClick(_:))
            button.sendAction(on: [.leftMouseUp])
        }
        self.mediaItem = media

        // Find Phone item
        let find = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        find.autosaveName = "com.subhashh.tether.action.findphone"
        if let button = find.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let img = NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: "Find Phone")?.withSymbolConfiguration(config)
            img?.isTemplate = true
            button.image = img
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleFindPhone(_:))
            button.sendAction(on: [.leftMouseUp])
        }
        self.findPhoneItem = find

        // Send Clipboard item
        let clip = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        clip.autosaveName = "com.subhashh.tether.action.clipboard"
        if let button = clip.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let img = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Send Clipboard")?.withSymbolConfiguration(config)
            img?.isTemplate = true
            button.image = img
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleSendClipboard(_:))
            button.sendAction(on: [.leftMouseUp])
        }
        self.clipboardItem = clip

        // Send Files item
        let files = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        files.autosaveName = "com.subhashh.tether.action.sendfiles"
        if let button = files.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let img = NSImage(systemSymbolName: "arrow.up.doc", accessibilityDescription: "Send Files")?.withSymbolConfiguration(config)
            img?.isTemplate = true
            button.image = img
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleSendFiles(_:))
            button.sendAction(on: [.leftMouseUp])
        }
        self.sendFilesItem = files
    }

    public func updateItems() {
        guard isStarted else { return }

        let defaults = UserDefaults.standard
        let quickActionsEnabled = defaults.bool(forKey: MenuBarQuickActionsSettings.showQuickActionsKey)
        let showSilence = defaults.bool(forKey: MenuBarQuickActionsSettings.showSilencePhoneKey)
        let showMedia = defaults.bool(forKey: MenuBarQuickActionsSettings.showMediaKey)
        let showFind = defaults.bool(forKey: MenuBarQuickActionsSettings.showFindPhoneKey)
        let showClip = defaults.bool(forKey: MenuBarQuickActionsSettings.showClipboardKey)
        let showSend = defaults.bool(forKey: MenuBarQuickActionsSettings.showSendFilesKey)

        guard let device = appModel?.primaryDevice, quickActionsEnabled else {
            silenceItem?.isVisible = false
            mediaItem?.isVisible = false
            findPhoneItem?.isVisible = false
            clipboardItem?.isVisible = false
            sendFilesItem?.isVisible = false
            return
        }

        let name = device.name

        // Silence Phone (Toggle)
        silenceItem?.isVisible = showSilence
        let silenceIcon = device.isSilenced ? "bell.slash.fill" : "bell.fill"
        let silenceConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let silenceImg = NSImage(systemSymbolName: silenceIcon, accessibilityDescription: "Silence Phone")?.withSymbolConfiguration(silenceConfig)
        silenceImg?.isTemplate = true
        silenceItem?.button?.image = silenceImg
        silenceItem?.button?.toolTip = device.isSilenced ? "\(name) is Silenced (Click to Unsilence)" : "Silence \(name) (Click to Silence)"

        // Media (Music Play/Pause Toggle)
        mediaItem?.isVisible = showMedia
        let mediaIcon = device.nowPlayingIsPlaying ? "pause.fill" : "play.fill"
        let mediaConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let mediaImg = NSImage(systemSymbolName: mediaIcon, accessibilityDescription: "Music")?.withSymbolConfiguration(mediaConfig)
        mediaImg?.isTemplate = true
        mediaItem?.button?.image = mediaImg
        if let title = device.nowPlayingTitle, !title.isEmpty {
            let artist = device.nowPlayingArtist?.isEmpty == false ? " · \(device.nowPlayingArtist!)" : ""
            mediaItem?.button?.toolTip = device.nowPlayingIsPlaying ? "Playing: \(title)\(artist) (Click to Pause)" : "Paused: \(title)\(artist) (Click to Play)"
        } else {
            mediaItem?.button?.toolTip = "Music on \(name) (Click to Play)"
        }

        // Find Phone
        findPhoneItem?.isVisible = showFind
        findPhoneItem?.button?.toolTip = "Find \(name)"

        // Send Clipboard
        clipboardItem?.isVisible = showClip
        clipboardItem?.button?.toolTip = "Send Clipboard to \(name)"

        // Send Files
        sendFilesItem?.isVisible = showSend
        sendFilesItem?.button?.toolTip = "Send Files to \(name)"
    }

    // MARK: - Actions

    @objc private func handleSilencePhone(_ sender: Any?) {
        guard let device = appModel?.primaryDevice else { return }
        device.toggleSilence()
        updateItems()
    }

    @objc private func handleMediaClick(_ sender: Any?) {
        guard let device = appModel?.primaryDevice else { return }
        device.playPauseMedia()
        updateItems()
    }

    @objc private func handleFindPhone(_ sender: Any?) {
        guard let device = appModel?.primaryDevice else { return }
        device.findMyPhone()
    }

    @objc private func handleSendClipboard(_ sender: Any?) {
        guard let device = appModel?.primaryDevice else { return }
        device.sendClipboard()
    }

    @objc private func handleSendFiles(_ sender: Any?) {
        guard let device = appModel?.primaryDevice else { return }
        NSApp.activate(ignoringOtherApps: true)
        let files = FilePicker.chooseFiles(sendingTo: device.name)
        if !files.isEmpty {
            device.sendFiles(files)
        }
    }
}
