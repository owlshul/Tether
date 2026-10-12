//
//  UpdaterTests.swift
//  TetherTests
//

import Foundation
import Testing
@testable import Tether

struct AppVersionTests {
    @Test func parsesReleaseVersions() {
        #expect(AppVersion("1.5")?.components == [1, 5, 0])
        #expect(AppVersion("v1.5.1")?.components == [1, 5, 1])
        #expect(AppVersion("2")?.components == [2, 0, 0])
        #expect(AppVersion("v1.5.1")?.description == "1.5.1")
    }

    @Test func rejectsOddTags() {
        for tag in ["", "v", "1.", "1..2", "1.2.3.4", "1.5-beta", "latest", "1.5 ", "-1.2"] {
            #expect(AppVersion(tag) == nil, "\(tag) should not parse")
        }
    }

    @Test func comparesNumerically() throws {
        let v = { (s: String) in try #require(AppVersion(s)) }
        #expect(try v("1.5.1") > v("1.5"))
        #expect(try v("1.10") > v("1.9.9"))
        #expect(try v("1.5") == v("1.5.0"))
        #expect(try !(v("1.5") > v("1.5.0")))
    }
}

struct ReleaseFeedTests {
    private func release(tag: String = "v1.6", assets: [String], prerelease: Bool = false) -> GitHubRelease {
        GitHubRelease(
            tag_name: tag,
            body: "### New\n- A thing\n\n<!-- tether:install -->\n### Install\n- brew",
            html_url: URL(string: "https://github.com/subhashhhhhh/Tether/releases/tag/\(tag)")!,
            draft: false,
            prerelease: prerelease,
            assets: assets.map {
                .init(name: $0, size: 100, browser_download_url: URL(string: "https://example.com/\($0)")!,
                      digest: "sha256:ABCDEF")
            }
        )
    }

    @Test func picksTheZipForThisArchitecture() throws {
        let found = try #require(ReleaseFeed.available(from: release(assets: [
            "Tether-1.6-AppleSilicon.dmg", "Tether-1.6-AppleSilicon.zip", "Tether-1.6-Intel.zip",
        ])))
        #expect(found.archiveURL.lastPathComponent == "Tether-1.6-\(ReleaseFeed.architectureLabel).zip")
        #expect(found.archiveSHA256 == "abcdef")
        #expect(found.notes == "### New\n- A thing")
    }

    @Test func offersNothingWithoutAZip() {
        #expect(ReleaseFeed.available(from: release(assets: ["Tether-1.6-AppleSilicon.dmg", "Tether-1.6-Intel.dmg"])) == nil)
        #expect(ReleaseFeed.available(from: release(assets: ["Tether-1.6-AppleSilicon.zip", "Tether-1.6-Intel.zip"], prerelease: true)) == nil)
        #expect(ReleaseFeed.available(from: release(tag: "nightly", assets: ["Tether-nightly-AppleSilicon.zip"])) == nil)
    }

    @Test func dropsInstallSectionsFromOlderNotes() {
        let body = """
            ## What's New in Tether 1.5

            ### ⬇️ Pick your download
            - **Apple Silicon:** `Tether-1.5-AppleSilicon.dmg`

            ### 📤 Tether in the Share menu
            - Share from Finder.

            ---

            ### 📦 Installation & Gatekeeper Note
            Run xattr.
            """
        #expect(ReleaseFeed.changelog(from: body) == """
            ## What's New in Tether 1.5

            ### 📤 Tether in the Share menu
            - Share from Finder.
            """)
    }
}

/// Installs a real signed build over another, end to end. Needs fixtures that
/// scripts/test-updater.sh builds, so it's skipped otherwise:
///
///   TETHER_UPDATE_FIXTURE  folder with old.app, new.zip (1.5.1) and adhoc.zip
///   TETHER_UPDATE_SERVER   http:// URL serving that folder
@Suite(.serialized) struct UpdateInstallerTests {
    static let fixture = ProcessInfo.processInfo.environment["TETHER_UPDATE_FIXTURE"].map(URL.init(fileURLWithPath:))
    static let server = ProcessInfo.processInfo.environment["TETHER_UPDATE_SERVER"].flatMap(URL.init(string:))

    private func prepare() throws -> (UpdateInstaller, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let apps = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let installed = apps.appendingPathComponent("Tether.app")
        try FileManager.default.copyItem(at: Self.fixture!.appendingPathComponent("old.app"), to: installed)
        return (UpdateInstaller(bundleURL: installed, stagingDirectory: root.appendingPathComponent("Staging")), installed)
    }

    private func release(_ zip: String, sha256: String? = nil) throws -> AvailableRelease {
        let data = try Data(contentsOf: Self.fixture!.appendingPathComponent(zip))
        return AvailableRelease(
            version: AppVersion("1.5.1")!,
            tag: "v1.5.1",
            notes: "",
            pageURL: Self.server!,
            archiveURL: Self.server!.appendingPathComponent(zip),
            archiveSize: Int64(data.count),
            archiveSHA256: sha256
        )
    }

    private func version(at app: URL) -> String? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
    }

    @Test(.enabled(if: fixture != nil && server != nil))
    func installsASignedUpdate() async throws {
        let (installer, installed) = try prepare()
        let zip = try Data(contentsOf: Self.fixture!.appendingPathComponent("new.zip"))
        let digest = SHA256Hex.of(zip)
        try await installer.install(try release("new.zip", sha256: digest)) { _ in }
        #expect(version(at: installed) == "1.5.1")
    }

    @Test(.enabled(if: fixture != nil && server != nil))
    func refusesAnUnsignedUpdate() async throws {
        let (installer, installed) = try prepare()
        await #expect(throws: UpdateFailure.untrustedSignature) {
            try await installer.install(try release("adhoc.zip")) { _ in }
        }
        #expect(version(at: installed) == "1.5.0")
    }

    @Test(.enabled(if: fixture != nil && server != nil))
    func refusesADamagedDownload() async throws {
        let (installer, installed) = try prepare()
        await #expect(throws: UpdateFailure.checksumMismatch) {
            try await installer.install(try release("new.zip", sha256: String(repeating: "0", count: 64))) { _ in }
        }
        #expect(version(at: installed) == "1.5.0")
    }
}

import CryptoKit

private enum SHA256Hex {
    static func of(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
