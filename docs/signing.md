# Signing and updates

Releases are signed with a self-signed certificate called **Tether Self-Signed**,
the same one for every release. Tether isn't notarized (that needs a paid Apple
developer account), so this isn't about Gatekeeper. Signing with one fixed
certificate does two things:

- **The in-app updater can trust a download.** Before it replaces the running
  app, it checks that the downloaded Tether is intact, the Share extension
  included, and signed with exactly the certificate the running app was signed
  with. Only the private key in your keychain can produce that signature, so a
  tampered or substituted download is refused.
- **macOS keeps Tether's Accessibility permission across updates.** An ad-hoc
  signed app is identified by its exact build, so every update looked like a new
  app and the permission had to be granted again.

`scripts/release.sh` signs with it and refuses to run if it's missing.

## Back up the certificate

**If the private key is lost, every installed copy stops accepting updates:** a
release signed with a new certificate is refused, and people have to download it
by hand once. Export a backup and keep the file and its password somewhere safe,
such as a password manager:

```bash
security export -t identities -f pkcs12 -k ~/Library/Keychains/login.keychain-db \
  -P "choose-a-password" -o ~/Desktop/Tether-Self-Signed.p12
```

macOS asks for your login password to allow the export. The file holds the
private key, so don't commit it or leave it on the desktop.

To restore it on another Mac:

```bash
security import Tether-Self-Signed.p12 -k ~/Library/Keychains/login.keychain-db \
  -P "the-password" -T /usr/bin/codesign
```

## Creating it (once)

This was done once, in October 2026, and must **not** be repeated while the
original exists: a new certificate is a different identity.

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout key.pem -out cert.pem \
  -subj "/CN=Tether Self-Signed" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"
# -legacy: macOS can't import OpenSSL 3's default PKCS#12 encryption.
openssl pkcs12 -export -legacy -inkey key.pem -in cert.pem -name "Tether Self-Signed" \
  -out identity.p12 -passout pass:temporary
security import identity.p12 -k ~/Library/Keychains/login.keychain-db -P temporary -T /usr/bin/codesign
rm key.pem cert.pem identity.p12
```

`security find-identity -p codesigning` lists it as `CSSMERR_TP_NOT_TRUSTED`,
which is expected for a self-signed certificate and doesn't stop `codesign`.

## How an update is installed

1. Once a day (30 seconds after launch at the earliest), Tether asks
   `api.github.com` for the latest release. A newer version gets one
   notification; clicking it, the menu bar item or **Tether › Check for
   Updates…** opens the Software Update window.
2. The release must carry `Tether-<version>-AppleSilicon.zip` or
   `Tether-<version>-Intel.zip`, matching the running build. A release without
   the zip isn't offered. `release.sh` uploads both.
3. The zip is downloaded to `~/Library/Caches/TetherUpdate` and its SHA-256 is
   compared with the digest GitHub reports for the asset.
4. It's unzipped with `ditto`, and the app inside must have Tether's bundle ID,
   the advertised version, and a valid signature from the same certificate.
5. Only then is `/Applications/Tether.app` replaced, and Tether relaunches.

A local build signed ad hoc has no certificate to compare with, so it offers the
download page instead of installing. Homebrew's cask declares
`auto_updates true`, so `brew upgrade` leaves a self-updating Tether alone.

`scripts/test-updater.sh` builds signed and unsigned copies, serves them over
local HTTP, and checks that a signed update installs and that unsigned or
damaged downloads are refused.
