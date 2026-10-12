//
//  BundleSignature.swift
//  Tether
//
//  Proves a downloaded Tether is ours before it replaces the running one.
//
//  Releases are signed with the "Tether Self-Signed" certificate, whose private
//  key only the maintainer holds. A download is trusted when its signature is
//  intact, the Share extension included, and it was signed with exactly the
//  certificate the running app was signed with. A tampered or re-signed copy
//  fails one of the two.
//

import Foundation
import Security

nonisolated enum BundleSignature {
    static func isTrusted(_ bundleURL: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }

        // An unsealed bundle can claim anything, and a nested extension is where a
        // swapped binary would hide.
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(staticCode, flags, nil) == errSecSuccess else { return false }

        guard let running = runningCertificate(), let candidate = certificate(of: staticCode) else {
            return false
        }
        return running == candidate
    }

    /// Whether the running app is signed with a certificate at all. A local or
    /// ad-hoc build has none, so it can't check an update and doesn't offer to
    /// install one.
    static var canVerifyUpdates: Bool {
        runningCertificate() != nil
    }

    private static func runningCertificate() -> Data? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        return certificate(of: staticCode)
    }

    /// The leaf certificate's bytes.
    private static func certificate(of code: SecStaticCode) -> Data? {
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else { return nil }
        return SecCertificateCopyData(leaf) as Data
    }
}
