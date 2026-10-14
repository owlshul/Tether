//
//  ReleaseFeed.swift
//  Tether
//
//  Finds the newest release. It reads updates/latest.json from the repository
//  through raw.githubusercontent.com first: GitHub's API allows only 60
//  requests an hour per public IP address without an account, which a shared
//  network (a university, an office) uses up for everyone. The API is the
//  fallback. release.sh writes the manifest when it publishes a release.
//

import Foundation

/// A published release this Mac can install.
nonisolated struct AvailableRelease: Sendable, Equatable {
    let version: AppVersion
    let tag: String
    /// The changelog, without the download and install instructions.
    let notes: String
    let pageURL: URL
    /// The zip for this Mac's architecture.
    let archiveURL: URL
    let archiveSize: Int64
    /// SHA-256 that GitHub computed for the zip, lowercase hex, when it provides one.
    let archiveSHA256: String?
}

nonisolated enum ReleaseFeed {
    static let repository = "subhashhhhhh/Tether"
    static let releasesPage = URL(string: "https://github.com/\(repository)/releases/latest")!

    /// Release notes end the in-app changelog at this marker; what follows is for
    /// people downloading by hand.
    static let installMarker = "<!-- tether:install -->"

    /// `TETHER_UPDATE_FEED` points the updater at a test feed. Whatever it serves
    /// still has to pass the signature check before it is installed.
    private static var latestURL: URL {
        if let override = ProcessInfo.processInfo.environment["TETHER_UPDATE_FEED"],
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    /// The file name part that matches the running build: the Intel build stays
    /// on Intel builds even under Rosetta.
    static var architectureLabel: String {
        #if arch(arm64)
        return "AppleSilicon"
        #else
        return "Intel"
        #endif
    }

    enum FeedError: LocalizedError {
        case badResponse(Int)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .badResponse(403), .badResponse(429): "GitHub is limiting requests from this network. Try again later."
            case .badResponse(let status): "GitHub answered with status \(status)."
            case .unreadable: "The release information couldn't be read."
            }
        }
    }

    static let manifestURL = URL(string: "https://raw.githubusercontent.com/\(repository)/main/updates/latest.json")!

    /// The latest release, or nil when it has no zip for this Mac (such a
    /// release can only be installed by hand).
    static func latest() async throws -> AvailableRelease? {
        if ProcessInfo.processInfo.environment["TETHER_UPDATE_FEED"] == nil {
            do {
                let manifest = try JSONDecoder().decode(UpdateManifest.self, from: try await fetch(manifestURL))
                return available(from: manifest)
            } catch {
                TetherLog("[Updater] Manifest unavailable (\(error.localizedDescription)); asking GitHub's API")
            }
        }
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: try await fetch(latestURL, api: true)) else {
            throw FeedError.unreadable
        }
        return available(from: release)
    }

    private static func fetch(_ url: URL, api: Bool = false) async throws -> Data {
        // Generous timeout: a phone hotspot can be slow.
        var request = URLRequest(url: url, timeoutInterval: 45)
        if api { request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept") }
        // GitHub refuses requests without a User-Agent.
        request.setValue("Tether/\(AppVersion.current?.description ?? "0")", forHTTPHeaderField: "User-Agent")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw FeedError.badResponse(status) }
        return data
    }

    static func available(from manifest: UpdateManifest) -> AvailableRelease? {
        guard let version = AppVersion(manifest.version),
              let archive = manifest.archives[architectureLabel],
              let url = URL(string: "https://github.com/\(repository)/releases/download/\(manifest.tag)/\(archive.name)"),
              let page = URL(string: "https://github.com/\(repository)/releases/tag/\(manifest.tag)") else { return nil }
        return AvailableRelease(
            version: version,
            tag: manifest.tag,
            notes: manifest.notes,
            pageURL: page,
            archiveURL: url,
            archiveSize: archive.size,
            archiveSHA256: archive.sha256.lowercased()
        )
    }

    static func available(from release: GitHubRelease) -> AvailableRelease? {
        guard !release.draft, !release.prerelease,
              let version = AppVersion(release.tag_name) else { return nil }

        let archiveName = "Tether-\(version.description)-\(architectureLabel).zip"
        guard let asset = release.assets.first(where: { $0.name == archiveName }) else { return nil }

        var sha256: String?
        if let digest = asset.digest, digest.hasPrefix("sha256:") {
            sha256 = String(digest.dropFirst("sha256:".count)).lowercased()
        }

        return AvailableRelease(
            version: version,
            tag: release.tag_name,
            notes: changelog(from: release.body ?? ""),
            pageURL: release.html_url,
            archiveURL: asset.browser_download_url,
            archiveSize: asset.size,
            archiveSHA256: sha256
        )
    }

    /// Cuts the notes at the install marker. Older releases have no marker, so
    /// they are cut at the first horizontal rule, and their download picker is
    /// dropped: neither means anything to an app that updates itself.
    static func changelog(from body: String) -> String {
        var text = body
        if let marker = text.range(of: installMarker) {
            text = String(text[..<marker.lowerBound])
        } else if let rule = text.range(of: "\n---\n") {
            text = String(text[..<rule.lowerBound])
        }

        var kept: [Substring] = []
        var skipping = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("#") {
                skipping = line.localizedCaseInsensitiveContains("pick your download")
            }
            if !skipping { kept.append(line) }
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The parts of GitHub's release JSON the updater reads.
nonisolated struct GitHubRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let size: Int64
        let browser_download_url: URL
        let digest: String?
    }

    let tag_name: String
    let body: String?
    let html_url: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
}

/// updates/latest.json in the repository, written by scripts/release.sh.
nonisolated struct UpdateManifest: Decodable, Sendable {
    struct Archive: Decodable, Sendable {
        let name: String
        let size: Int64
        let sha256: String
    }

    let version: String
    let tag: String
    /// The changelog, without download and install instructions.
    let notes: String
    /// Keyed by architecture label: "AppleSilicon", "Intel".
    let archives: [String: Archive]
}
