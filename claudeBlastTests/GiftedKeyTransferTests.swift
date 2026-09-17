// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  GiftedKeyTransferTests.swift
//  claudeBlastTests
//
//  Two implementations of one file format is the only real risk in this feature.
//

import Testing
import Foundation
import CryptoKit
@testable import claudeBlast

/// Not nested in `SerialTests`: no SwiftData container, no network, no clock.
struct GiftedKeyTransferTests {

    private func payload(key: String = "sk-test-0000000000000000000000000001",
                         label: String = "Brandi") -> GiftedKeyPayload {
        GiftedKeyPayload(key: key, label: label, issuer: "Mark Lucovsky",
                         issuedAt: "2026-09-16T00:00:00+00:00", expiresAt: nil)
    }

    // MARK: - Round trip

    @Test("A sealed key opens back to what went in")
    func roundTrip() throws {
        let original = payload()
        let opened = try GiftedKeyObfuscation.open(GiftedKeyObfuscation.seal(original))
        #expect(opened == original)
    }

    @Test("An expiry survives the round trip")
    func expirySurvives() throws {
        let original = GiftedKeyPayload(key: "sk-x", label: "Kurt", issuer: "Mark",
                                        issuedAt: "2026-09-16T00:00:00+00:00",
                                        expiresAt: "2026-12-31T00:00:00Z")
        let opened = try GiftedKeyObfuscation.open(GiftedKeyObfuscation.seal(original))
        #expect(opened.expiresAt == "2026-12-31T00:00:00Z")
    }

    /// Two files for the same key must not be byte-identical, or the nonce is
    /// doing nothing and identical payloads would be recognisable as such.
    @Test("Each sealing uses a fresh nonce")
    func nonceIsFresh() throws {
        let a = try GiftedKeyObfuscation.seal(payload())
        let b = try GiftedKeyObfuscation.seal(payload())
        #expect(a != b)
    }

    // MARK: - The cross-language seam
    //
    // The keystream is where Swift and Python agree or silently do not, and
    // "silently" is the problem: a mismatch shows up as a file that will not
    // open, on someone else's iPad, with no clue which side is wrong.

    /// Pinned against a value computed from the spec rather than from this code,
    /// so a change to byte order, counter width, or the seeding of the stream
    /// fails here instead of in the field.
    @Test("The first keystream block matches the stated construction")
    func keystreamMatchesSpec() {
        let nonce = Data((0..<16).map { UInt8($0) })

        // SHA256( SHA256(bundleID) ‖ nonce ‖ bigEndian UInt64(0) )
        var expectedInput = Data(SHA256.hash(data: Data(GiftedKeyObfuscation.bundleID.utf8)))
        expectedInput.append(nonce)
        expectedInput.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])
        let expected = Data(SHA256.hash(data: expectedInput))

        #expect(GiftedKeyObfuscation.keystream(nonce: nonce, count: 32) == expected)
    }

    /// A payload longer than one 32-byte block has to keep going, and the second
    /// block must differ from the first — a counter that never increments would
    /// repeat the same 32 bytes and make the scrambling worthless.
    @Test("The keystream extends past one block without repeating")
    func keystreamExtends() {
        let nonce = Data(repeating: 7, count: 16)
        let stream = GiftedKeyObfuscation.keystream(nonce: nonce, count: 96)
        #expect(stream.count == 96)
        #expect(stream.prefix(32) != stream.dropFirst(32).prefix(32))
    }

    /// The bundle identifier is the obfuscation input and is written down on both
    /// sides. If the app's identifier ever changes, every key file in the field
    /// stops opening — so the constant is pinned here as the reminder.
    @Test("The obfuscation input is the shipped bundle identifier")
    func bundleIDIsPinned() {
        #expect(GiftedKeyObfuscation.bundleID == "app.blasterai.ios")
    }

    // MARK: - The golden fixture
    //
    // Minted by `python3 tools/make_gifted_key.py --self-test`, checked in, and
    // opened here. This is the test that actually proves the Python and Swift
    // implementations agree; everything above proves Swift agrees with itself.

    @Test("The fixture minted by the Python tool opens")
    func goldenFixtureOpens() throws {
        let url = try #require(Bundle(for: BundleToken.self)
            .url(forResource: "gifted-key-golden", withExtension: "blasterkey"),
            "fixture missing from the test bundle")
        let opened = try GiftedKeyObfuscation.open(Data(contentsOf: url))

        #expect(opened.label == "Golden Fixture")
        #expect(opened.issuer == "Blaster Tests")
        #expect(opened.key == "sk-golden-fixture-not-a-real-key-0000")
        #expect(opened.expiresAt == nil)
    }

    // MARK: - Refusals

    @Test("A file that isn't JSON is refused")
    func notJSONIsRefused() {
        #expect(throws: GiftedKeyError.decodingFailed) {
            try GiftedKeyObfuscation.open(Data("not a file".utf8))
        }
    }

    @Test("A different Blaster format is refused by type")
    func wrongTypeIsRefused() throws {
        let body: [String: Any] = [
            "@type": BlasterColorwayFormat.mediaType, "version": "1.0.0",
            "_comment": "", "label": "x", "nonce": "AA==", "payload": "AA==",
            "checksum": "00",
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        #expect(throws: GiftedKeyError.invalidType) {
            try GiftedKeyObfuscation.open(data)
        }
    }

    @Test("A newer format version is refused by name")
    func futureVersionIsRefused() throws {
        let body: [String: Any] = [
            "@type": BlasterKeyFormat.mediaType, "version": "2.0.0",
            "_comment": "", "label": "x", "nonce": "AA==", "payload": "AA==",
            "checksum": "00",
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        #expect(throws: GiftedKeyError.unsupportedVersion("2.0.0")) {
            try GiftedKeyObfuscation.open(data)
        }
    }

    /// The checksum's actual job. It is not a MAC and cannot stop anyone who
    /// wants to edit the file — what it catches is a truncated download or a
    /// transfer that mangled the bytes, which is the failure that really happens.
    @Test("A damaged payload is refused rather than half-read")
    func damagedPayloadIsRefused() throws {
        let sealed = try GiftedKeyObfuscation.seal(payload())
        var body = try #require(try JSONSerialization.jsonObject(with: sealed) as? [String: Any])

        let original = try #require(body["payload"] as? String)
        var bytes = try #require(Data(base64Encoded: original))
        bytes[0] ^= 0xFF
        body["payload"] = bytes.base64EncodedString()

        let damaged = try JSONSerialization.data(withJSONObject: body)
        #expect(throws: GiftedKeyError.corrupted) {
            try GiftedKeyObfuscation.open(damaged)
        }
    }

    @Test("A file carrying no key is refused")
    func emptyKeyIsRefused() throws {
        let sealed = try GiftedKeyObfuscation.seal(payload(key: "   "))
        #expect(throws: GiftedKeyError.missingKey) {
            try GiftedKeyObfuscation.open(sealed)
        }
    }

    // MARK: - What the file looks like from outside

    /// The label is readable without opening the payload, so a sheet can say who
    /// the key is for before anything is decoded.
    @Test("The recipient is visible on the envelope")
    func labelIsOnTheEnvelope() throws {
        let sealed = try GiftedKeyObfuscation.seal(payload(label: "Brandi"))
        let body = try #require(try JSONSerialization.jsonObject(with: sealed) as? [String: Any])
        #expect(body["label"] as? String == "Brandi")
    }

    /// The whole point of scrambling: the key must not be findable by reading
    /// the file. It is recoverable by anyone who tries — that is the accepted
    /// trade — but not by looking.
    @Test("The key does not appear anywhere in the file as text")
    func keyIsNotInPlainText() throws {
        let secret = "sk-supersecret-abcdefghijklmnop"
        let sealed = try GiftedKeyObfuscation.seal(payload(key: secret))
        let text = try #require(String(data: sealed, encoding: .utf8))
        #expect(!text.contains(secret))
        #expect(!text.contains("sk-supersecret"))
    }

    @Test("Last four is what the dashboard shows")
    func lastFour() {
        #expect(GiftedKeyObfuscation.lastFour(of: "sk-abcdefgh8toA") == "8toA")
    }
}

/// Anchor for locating the test bundle's resources.
private final class BundleToken {}
