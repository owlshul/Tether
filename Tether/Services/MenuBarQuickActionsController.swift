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
    public static let showCallKashishKey = "TetherShowMenuBarCallKashish"
    public static let kashishNameKey = "TetherQuickCallName"
    public static let kashishNumberKey = "TetherQuickCallNumber"

    public static let defaultKashishName = "Kashish"
    public static let defaultKashishNumber = "+919773747984"

    public static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showQuickActionsKey: true,
            showSilencePhoneKey: true,
            showMediaKey: true,
            showFindPhoneKey: true,
            showClipboardKey: true,
            showSendFilesKey: true,
            showBatteryKey: true,
            showCallKashishKey: true,
            kashishNameKey: defaultKashishName,
            kashishNumberKey: defaultKashishNumber
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
    private var callKashishItem: NSStatusItem?
    private var primaryStatusItem: NSStatusItem?
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
            schedulePrimaryRetries()
        } else {
            NotificationCenter.default.publisher(for: NSApplication.didFinishLaunchingNotification)
                .first()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.setupStatusItems()
                    self?.updateItems()
                    self?.schedulePrimaryRetries()
                }
                .store(in: &cancellables)
        }
    }

    private func schedulePrimaryRetries() {
        for delay in [0.05, 0.15, 0.35, 0.75, 1.5, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.updatePrimaryStatusItem()
            }
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

        // Call Kashish item
        let call = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        call.autosaveName = "com.subhashh.tether.action.callkashish"
        if let button = call.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let img = NSImage(systemSymbolName: "phone.fill", accessibilityDescription: "Call Kashish")?.withSymbolConfiguration(config)
            img?.isTemplate = true
            button.image = img
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleCallKashish(_:))
            button.sendAction(on: [.leftMouseUp])
        }
        self.callKashishItem = call
    }

    public func updateItems() {
        guard isStarted else { return }

        updatePrimaryStatusItem()

        let defaults = UserDefaults.standard
        let quickActionsEnabled = defaults.bool(forKey: MenuBarQuickActionsSettings.showQuickActionsKey)
        let showSilence = defaults.bool(forKey: MenuBarQuickActionsSettings.showSilencePhoneKey)
        let showMedia = defaults.bool(forKey: MenuBarQuickActionsSettings.showMediaKey)
        let showFind = defaults.bool(forKey: MenuBarQuickActionsSettings.showFindPhoneKey)
        let showClip = defaults.bool(forKey: MenuBarQuickActionsSettings.showClipboardKey)
        let showSend = defaults.bool(forKey: MenuBarQuickActionsSettings.showSendFilesKey)
        let showCallKashish = defaults.bool(forKey: MenuBarQuickActionsSettings.showCallKashishKey)

        guard let device = appModel?.primaryDevice, quickActionsEnabled else {
            silenceItem?.isVisible = false
            mediaItem?.isVisible = false
            findPhoneItem?.isVisible = false
            clipboardItem?.isVisible = false
            sendFilesItem?.isVisible = false
            callKashishItem?.isVisible = false
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

        // Call Kashish
        callKashishItem?.isVisible = showCallKashish
        let kashishName = device.kashishDisplayName
        let kashishNumber = device.kashishPhoneNumber
        callKashishItem?.button?.toolTip = "Call \(kashishName) (\(kashishNumber))"
    }

    private func findPrimaryStatusItem() -> NSStatusItem? {
        if let primary = primaryStatusItem { return primary }
        let known: Set<NSStatusItem> = Set([silenceItem, mediaItem, findPhoneItem, clipboardItem, sendFilesItem, callKashishItem].compactMap { $0 })
        guard let ivar = class_getInstanceVariable(NSStatusBar.self, "_items"),
              let pointerArray = object_getIvar(NSStatusBar.system, ivar) as? NSPointerArray else {
            return nil
        }
        for i in 0..<pointerArray.count {
            if let ptr = pointerArray.pointer(at: i) {
                let item = Unmanaged<NSStatusItem>.fromOpaque(ptr).takeUnretainedValue()
                if !known.contains(item) && item.button != nil {
                    primaryStatusItem = item
                    return item
                }
            }
        }
        return nil
    }

    public func updatePrimaryStatusItem() {
        guard let item = findPrimaryStatusItem(), let button = item.button else { return }

        guard let device = appModel?.primaryDevice else {
            button.image = NSImage(named: "MenuBarDisconnected")
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "Tether (Disconnected)"
            return
        }

        let isTablet = device.deviceType == .tablet
        let symbolName = isTablet ? "ipad" : "iphone"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Tether")?.withSymbolConfiguration(config)
        img?.isTemplate = true
        button.image = img

        if let percent = device.batteryPercent {
            let prefix = device.isCharging ? "⚡️" : ""
            button.title = "\(prefix)\(percent)%"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.imagePosition = .imageLeading
            button.toolTip = "\(device.name) (\(percent)%\(device.isCharging ? ", Charging" : ""))"
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "\(device.name)"
        }
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

    @objc private func handleCallKashish(_ sender: Any?) {
        guard let device = appModel?.primaryDevice else { return }
        device.callKashish()
    }
}
