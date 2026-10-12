//
//  MainWindowPreviews.swift
//  Tether
//
//  Previews for views built on a selectable List live apart from those views on
//  purpose: previewing such a List from the file that declares it trips a
//  fatalError inside SwiftUI's outline list (TableViewListCore_Mac2) under
//  Xcode 27's preview hot-reload. The same views render fine from any other
//  file and in the running app.
//

import SwiftUI

#if DEBUG
#Preview("Connected") {
    MainWindowView(appModel: .mock())
        .frame(width: 1000, height: 680)
}

#Preview("First run") {
    MainWindowView(appModel: .mockEmpty())
        .frame(width: 1000, height: 680)
}

#Preview("Pair request") {
    MainWindowView(appModel: .mockPairRequest())
        .frame(width: 1000, height: 680)
}

#Preview("Messages") {
    MessagesPane(device: .mockConnectedPhone())
        .frame(width: 820, height: 560)
}
#endif
