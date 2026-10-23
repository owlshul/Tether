//
//  ArtworkTests.swift
//  TetherTests
//

import AppKit
import ImageIO
import Testing
@testable import Tether

struct ArtworkTests {
    private func bitmap(_ side: Int) throws -> NSBitmapImageRep {
        try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    }

    private func pixelSize(_ data: Data) throws -> Int {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)).width
    }

    /// Safari's video artwork is TIFF, which Android can't decode.
    @Test func convertsTIFFToJPEG() throws {
        let tiff = try #require(bitmap(64).tiffRepresentation)
        let (data, mimeType) = try #require(NowPlayingReader.phoneReadable(tiff))
        #expect(mimeType == "image/jpeg")
        #expect(data.starts(with: [0xFF, 0xD8]))
    }

    @Test func keepsSmallJPEGsAndShrinksLargeImages() throws {
        let jpeg = try #require(bitmap(300).representation(using: .jpeg, properties: [:]))
        let kept = try #require(NowPlayingReader.phoneReadable(jpeg))
        #expect(kept.0 == jpeg)

        let large = try #require(bitmap(2000).representation(using: .png, properties: [:]))
        let shrunk = try #require(NowPlayingReader.phoneReadable(large))
        #expect(shrunk.1 == "image/jpeg")
        #expect(try pixelSize(shrunk.0) == 1024)
    }

    @Test func rejectsNonImages() {
        #expect(NowPlayingReader.phoneReadable(Data("not an image".utf8)) == nil)
    }
}
