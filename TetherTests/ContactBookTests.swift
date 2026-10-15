//
//  ContactBookTests.swift
//  TetherTests
//

import Foundation
import Testing
@testable import Tether

struct ContactBookTests {
    @Test func parsesAndroidVCard21() throws {
        let card = """
            BEGIN:VCARD
            VERSION:2.1
            N:Rivera;Alex;;;
            FN:Alex Rivera
            TEL;CELL:+91 98765 43210
            TEL;HOME:080-2345-6789
            PHOTO;ENCODING=BASE64;JPEG:/9j/4AAQSkZJRgABAQ
             AAAQABAAD/2wBDAA==
            X-KDECONNECT-TIMESTAMP:1729000000000
            END:VCARD
            """
        let contact = try #require(VCard.parse(card))
        #expect(contact.name == "Alex Rivera")
        #expect(contact.numbers == ["+91 98765 43210", "080-2345-6789"])
        #expect(contact.photo?.prefix(2) == Data([0xFF, 0xD8]))
    }

    @Test func decodesQuotedPrintableNames() throws {
        let card = """
            BEGIN:VCARD
            VERSION:2.1
            FN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:=E0=A4=85=E0=A4=AE=E0=A4=BF=E0=A4=A4
            TEL;CELL:9876543210
            END:VCARD
            """
        #expect(try #require(VCard.parse(card)).name == "अमित")
    }

    @Test func fallsBackToStructuredName() throws {
        let card = "BEGIN:VCARD\nVERSION:3.0\nN:Kumar;Priya;;;\nTEL:+1 555 0100\nEND:VCARD"
        #expect(try #require(VCard.parse(card)).name == "Priya Kumar")
    }

    @Test func ignoresCardsWithoutAName() {
        #expect(VCard.parse("BEGIN:VCARD\nVERSION:3.0\nTEL:12345\nEND:VCARD") == nil)
    }

    @Test func matchesNumbersHoweverTheyAreWritten() {
        var book = ContactBook()
        book.set(Contact(name: "Alex", numbers: ["+91 98765 43210"], photo: nil), for: "1")
        book.set(Contact(name: "Bank", numbers: ["56767"], photo: nil), for: "2")
        #expect(book.contact(for: "9876543210")?.name == "Alex")
        #expect(book.contact(for: "+919876543210")?.name == "Alex")
        #expect(book.contact(for: "098765-43210")?.name == "Alex")
        #expect(book.contact(for: "56767")?.name == "Bank")
        #expect(book.contact(for: "156767") == nil)
        #expect(book.contact(for: "AX-HDFCBK") == nil)
    }

    @Test func forgetsRemovedContacts() {
        var book = ContactBook()
        book.set(Contact(name: "Alex", numbers: ["9876543210"], photo: nil), for: "1")
        book.set(nil, for: "1")
        #expect(book.contact(for: "9876543210") == nil)
        #expect(book.isEmpty)
    }
}

struct NowPlayingReaderTests {
    @Test func readsTheAdaptersPayload() throws {
        let state = try #require(NowPlayingReader.parse([
            "title": "Midnight City", "artist": "M83", "album": "Hurry Up, We're Dreaming",
            "playing": true, "duration": 241.5, "elapsedTime": 30.0, "timestamp": "2026-10-15T06:21:32Z",
        ]))
        #expect(state.title == "Midnight City")
        #expect(state.isPlaying)
        #expect(state.duration == 241.5)
        #expect(state.timestamp == ISO8601DateFormatter().date(from: "2026-10-15T06:21:32Z"))
    }

    @Test func ignoresNothingPlaying() {
        #expect(NowPlayingReader.parse([:]) == nil)
        #expect(NowPlayingReader.parse(["title": ""]) == nil)
    }
}
