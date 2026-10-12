//
//  TetherApp.swift
//  Tether
//

import SwiftUI

@main
struct TetherApp: App {
    @State private var appModel: TetherAppModel

    init() {
        #if DEBUG
        // `-TetherDemoData` fills the UI with sample devices for screenshots and
        // design work, without touching the network.
        if ProcessInfo.processInfo.arguments.contains("-TetherDemoData") {
            _appModel = State(initialValue: .mock())
            return
        }
        #endif

        _appModel = State(initialValue: .shared)
        // Eagerly initialize identity on main thread
        _ = DeviceIdentity.shared
        // Start background discovery and network services
        TetherService.shared.start()
    }

    var body: some Scene {
        MenuBarExtra("Tether", image: appModel.statusMenuBarImageName) {
            MenuBarView(appModel: appModel)
                .tetherMotionPreference()
        }
        .menuBarExtraStyle(.window)

        Window("Tether", id: "main") {
            MainWindowView(appModel: appModel)
                .tetherMotionPreference()
        }
        .defaultSize(width: 1040, height: 700)
        .windowToolbarStyle(.unified)
        .commands {
            TetherCommands(appModel: appModel)
        }

        Settings {
            SettingsView(viewModel: .shared)
                .tetherMotionPreference()
        }
    }
}
