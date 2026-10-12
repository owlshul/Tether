//
//  AppVersion.swift
//  Tether
//
//  A release version such as "1.5" or "1.5.1". Anything else parses to nil, so
//  an oddly named tag is never offered as an update.
//

import Foundation

nonisolated struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    /// Always three numbers; "1.5" is stored as 1.5.0.
    let components: [Int]
    /// As written in the tag or Info.plist, without a leading "v".
    let description: String

    init?(_ string: String) {
        let text = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }

        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber),
                  let number = Int(part) else { return nil }
            numbers.append(number)
        }
        while numbers.count < 3 { numbers.append(0) }
        components = numbers
        description = text
    }

    /// The version of the running app.
    static var current: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.components == rhs.components
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}
