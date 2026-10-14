//
//  OneTimeCode.swift
//  Tether
//
//  Finds a one-time verification code in a phone notification, so it can be
//  copied with one click. Only text that talks about a code is considered,
//  and amounts, dates, years and phone numbers are skipped.
//

import Foundation

nonisolated enum OneTimeCode {
    /// Settings › General › "Copy verification codes automatically". Off by
    /// default: replacing the clipboard unasked can lose what was on it.
    static let autoCopyKey = "tether_copy_codes_automatically"

    private static let keywords = [
        "code", "otp", "verification", "verify", "passcode", "password", "pin",
        "one-time", "one time", "2fa", "two-factor", "authentication", "security",
        "login", "log in", "log-in", "sign in", "sign-in", "signin", "confirm",
    ]

    /// The code in `text`, digits only, or nil.
    static func find(in text: String) -> String? {
        let lower = text.lowercased()
        let keywordPositions = keywords.flatMap { keyword in
            lower.ranges(of: keyword).map { lower.distance(from: lower.startIndex, to: $0.lowerBound) }
        }
        guard !keywordPositions.isEmpty else { return nil }

        var candidates: [(code: String, position: Int)] = []

        // "G-123456": a short prefix that sites don't expect you to type.
        for (groups, position) in matches(#"\b[A-Z]{1,3}-(\d{4,8})\b"#, in: text) {
            candidates.append((groups[1], position))
        }
        // "123 456" or "123-456".
        for (groups, position) in matches(#"(?<![\d.,:/])(\d{3})[ -](\d{3})(?![\d:/%]|[.,]\d)"#, in: text) {
            candidates.append((groups[1] + groups[2], position))
        }
        // A plain 4 to 8 digit number, not part of an amount, date, time or longer
        // number. A full stop or comma after it only counts when a digit follows.
        for (groups, position) in matches(#"(?<![\d.,:/\-])\d{4,8}(?![\d:/%]|[.,]\d)"#, in: text) {
            let digits = groups[0]
            if isAmount(beforeOffset: position, in: text) { continue }
            if digits.count == 4, let year = Int(digits), (1950...2099).contains(year) { continue }
            candidates.append((digits, position))
        }

        // The candidate nearest a keyword wins; ties go to the earlier one.
        return candidates
            .min { lhs, rhs in
                let left = keywordPositions.map { abs($0 - lhs.position) }.min() ?? .max
                let right = keywordPositions.map { abs($0 - rhs.position) }.min() ?? .max
                return left == right ? lhs.position < rhs.position : left < right
            }?
            .code
    }

    /// Each match's capture groups (0 is the whole match) and character offset.
    private static func matches(_ pattern: String, in text: String) -> [(groups: [String], position: Int)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : nsText.substring(with: range)
            }
            guard let range = Range(match.range, in: text) else { return nil }
            return (groups, text.distance(from: text.startIndex, to: range.lowerBound))
        }
    }

    /// Whether a currency comes just before the number, as in "Rs 1299" or "₹ 5000".
    private static func isAmount(beforeOffset offset: Int, in text: String) -> Bool {
        let prefix = text.prefix(offset).suffix(5).lowercased()
            .trimmingCharacters(in: .whitespaces)
        return ["rs", "rs.", "inr", "₹", "$", "usd", "eur", "€", "£", "gbp"].contains { prefix.hasSuffix($0) }
    }
}
