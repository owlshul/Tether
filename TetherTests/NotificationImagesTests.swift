import AppKit
import ImageIO
import Testing
@testable import Tether

@MainActor
struct NotificationImagesTests {
    private func png(width: Int = 32, height: Int = 32) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width,
            pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    /// A 32 px image drawn by `draw`, on transparency.
    private func drawnPNG(_ draw: (CGContext) -> Void) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32,
            pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        draw(context.cgContext)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    @Test func recognisesStatusBarGlyphsButNotPhotos() throws {
        // Tailscale-style: a white shape on transparency.
        let glyph = try drawnPNG { context in
            context.setFillColor(.white)
            context.fill(CGRect(x: 8, y: 8, width: 16, height: 16))
        }
        #expect(NotificationImages.isGlyph(glyph))

        // A round avatar with an initial: transparent corners, two colours.
        let avatar = try drawnPNG { context in
            context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
            context.fillEllipse(in: CGRect(x: 0, y: 0, width: 32, height: 32))
            context.setFillColor(.white)
            context.fill(CGRect(x: 12, y: 8, width: 8, height: 16))
        }
        #expect(!NotificationImages.isGlyph(avatar))

        // A square photo: no transparency at all.
        let photo = try drawnPNG { context in
            context.setFillColor(.white)
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        #expect(!NotificationImages.isGlyph(photo))
    }

    @Test func cachesOnlyByDeviceAndExplicitImageHash() throws {
        let images = NotificationImages()
        let data = try png()
        let stored = try #require(images.store(data, deviceId: "phone-a", hash: "avatar-1"))
        #expect(images.image(deviceId: "phone-a", hash: "avatar-1") == stored)
        #expect(images.image(deviceId: "phone-b", hash: "avatar-1") == nil)
        #expect(images.image(deviceId: "phone-a", hash: "avatar-2") == nil)
        #expect(images.image(deviceId: "phone-a", hash: nil) == nil)
        #expect(images.store(data, deviceId: "phone-a", hash: nil) != nil)
        images.removeAll()
        #expect(images.image(deviceId: "phone-a", hash: "avatar-1") == nil)
    }

    @Test func rejectsCorruptAndOversizedImagesAndDownsamplesValidPNGs() throws {
        let images = NotificationImages()
        #expect(images.store(Data("not an image".utf8), deviceId: "p", hash: "bad") == nil)
        #expect(images.store(Data(count: Int(NotificationImages.maximumPayloadSize) + 1), deviceId: "p", hash: "big") == nil)
        #expect(images.image(deviceId: "p", hash: "bad") == nil)
        let data = try #require(images.store(png(width: 512, height: 256), deviceId: "p", hash: "wide"))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 128)
        #expect(image.height == 64)
    }

    @Test func keepsAttachmentSourceUntilSchedulingCompletes() throws {
        let data = try png()
        let first = try #require(NotificationImages.attachment(data))
        let second = try #require(NotificationImages.attachment(data))
        defer { first.removeSource(); second.removeSource() }
        #expect(first.sourceURL != second.sourceURL)
        #expect(FileManager.default.fileExists(atPath: first.sourceURL.path))
        #expect(FileManager.default.fileExists(atPath: second.sourceURL.path))
        first.removeSource()
        #expect(!FileManager.default.fileExists(atPath: first.sourceURL.path))
        #expect(FileManager.default.fileExists(atPath: second.sourceURL.path))
    }

    @Test func delayedPayloadAndTimeoutCanDeliverOnlyOnce() {
        var tracker = NotificationImageTracker()
        let key = NotificationImageTracker.Key(deviceId: "p", notificationId: "chat")
        let token = tracker.begin(key, packetId: 1, waiting: true)
        let delivery1 = tracker.takeWaiting(key, token: token)
        #expect(delivery1)
        let delivery2 = !tracker.takeWaiting(key, token: token)
        #expect(delivery2)
        #expect(tracker.token(for: key, packetId: 1) == token) // list may still update
    }

    @Test func updateCancelDisconnectAndSilentSyncInvalidateDeferredAlerts() {
        var tracker = NotificationImageTracker()
        let key = NotificationImageTracker.Key(deviceId: "p", notificationId: "chat")
        let old = tracker.begin(key, packetId: 1, waiting: true)
        let silent = tracker.begin(key, packetId: 2, waiting: false)
        let delivery3 = !tracker.takeWaiting(key, token: old)
        #expect(delivery3)
        let delivery4 = !tracker.takeWaiting(key, token: silent)
        #expect(delivery4)
        #expect(tracker.token(for: key, packetId: 1) == nil)
        let cancelled = tracker.begin(key, packetId: 3, waiting: true)
        tracker.remove(key)
        let delivery5 = !tracker.takeWaiting(key, token: cancelled)
        #expect(delivery5)
        let disconnected = tracker.begin(key, packetId: 4, waiting: true)
        tracker.removeDevice("p")
        let delivery6 = !tracker.takeWaiting(key, token: disconnected)
        #expect(delivery6)
        #expect(tracker.token(for: key, packetId: 4) == nil)
    }

    @Test func acceptsAnEarlierPayloadOnlyWhenItsHashMatchesTheCurrentArtwork() {
        var tracker = NotificationImageTracker()
        let key = NotificationImageTracker.Key(deviceId: "p", notificationId: "chat")
        _ = tracker.begin(key, packetId: 1, hash: "avatar-a", waiting: true)
        let current = tracker.begin(key, packetId: 2, hash: "avatar-a", waiting: false)
        #expect(tracker.token(for: key, packetId: 1, hash: "avatar-a") == current)
        #expect(tracker.token(for: key, packetId: 1, hash: "avatar-b") == nil)
        _ = tracker.begin(key, packetId: 3, hash: "avatar-b", waiting: true)
        #expect(tracker.token(for: key, packetId: 1, hash: "avatar-a") == nil)
    }

    @Test func devicesWithTheSameAndroidIdStayIndependent() {
        var tracker = NotificationImageTracker()
        let a = NotificationImageTracker.Key(deviceId: "a", notificationId: "chat")
        let b = NotificationImageTracker.Key(deviceId: "b", notificationId: "chat")
        let first = tracker.begin(a, packetId: 1, waiting: true)
        let second = tracker.begin(b, packetId: 1, waiting: true)
        tracker.removeDevice("a")
        let delivery7 = !tracker.takeWaiting(a, token: first)
        #expect(delivery7)
        let delivery8 = tracker.takeWaiting(b, token: second)
        #expect(delivery8)
        #expect(NotificationPlugin.identifier(deviceId: "a", id: "chat") != NotificationPlugin.identifier(deviceId: "b", id: "chat"))
        #expect(NotificationPlugin.identifier(deviceId: "a", id: "bc") != NotificationPlugin.identifier(deviceId: "ab", id: "c"))
    }

    @Test func waitsOnlyForUsableImageAnnouncements() {
        func packet(_ size: Int64?, _ port: Any?) -> NetworkPacket {
            NetworkPacket(type: "kdeconnect.notification", payloadSize: size,
                          payloadTransferInfo: port.map { ["port": $0] })
        }
        #expect(NotificationPlugin.expectsImage(packet(100, 1739)))
        #expect(NotificationPlugin.expectsImage(packet(100, "1739")))
        #expect(!NotificationPlugin.expectsImage(packet(nil, 1739)))
        #expect(!NotificationPlugin.expectsImage(packet(0, 1739)))
        #expect(!NotificationPlugin.expectsImage(packet(NotificationImages.maximumPayloadSize + 1, 1739)))
        #expect(!NotificationPlugin.expectsImage(packet(100, nil)))
        #expect(!NotificationPlugin.expectsImage(packet(100, 65536)))
        #expect(!NotificationPlugin.expectsImage(packet(100, "bad")))
    }
}
