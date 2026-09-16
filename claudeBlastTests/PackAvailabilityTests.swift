// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PackAvailabilityTests.swift
//  claudeBlastTests
//
//  A vocabulary pack must be offerable before anyone has used it.
//

import Testing
import Foundation
import SwiftData
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct PackAvailabilityTests {
    private func makeContext() throws -> ModelContext { TestStore.freshContext() }

    private func lookup(_ ctx: ModelContext) -> [String: TileModel] {
        let all = (try? ctx.fetch(FetchDescriptor<TileModel>())) ?? []
        return Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// The catalogue knows its packs with nothing in the store at all.
    ///
    /// The picker used to answer "which packs can I offer?" by scanning
    /// materialized `TileModel`s, so a pack nobody had adopted filtered itself
    /// out of the surface whose job is to let you adopt it. Availability is a
    /// property of the catalogue, not of the current board.
    @Test func packsAreKnownBeforeAnyWordExists() throws {
        let ctx = try makeContext()
        #expect((try ctx.fetch(FetchDescriptor<TileModel>())).isEmpty)
        #expect(!PackCatalog.available(in: ctx).isEmpty)
    }

    /// Selecting a pack materializes its words, so the grid has something to show.
    @Test func installingAPackMakesItsWordsReal() throws {
        let ctx = try makeContext()
        guard let pack = PackCatalog.all.first else { return }

        let added = PackInstaller.install(pack, context: ctx, existing: lookup(ctx))
        try? ctx.save()

        #expect(added == pack.words.count)
        let keys = Set((try ctx.fetch(FetchDescriptor<TileModel>())).map(\.key))
        #expect(pack.words.allSatisfy { keys.contains($0.key) })
    }

    /// Tapping the same chip twice must not double anything — the picker installs
    /// on every selection rather than tracking what it has already done.
    @Test func installingTwiceAddsNothingTheSecondTime() throws {
        let ctx = try makeContext()
        guard let pack = PackCatalog.all.first else { return }

        _ = PackInstaller.install(pack, context: ctx, existing: lookup(ctx))
        try? ctx.save()
        let after = PackInstaller.install(pack, context: ctx, existing: lookup(ctx))
        try? ctx.save()

        #expect(after == 0)
        let all = try ctx.fetch(FetchDescriptor<TileModel>())
        #expect(Set(all.map(\.key)).count == all.count, "a key was duplicated")
    }

    /// Pack words are shipped vocabulary arriving by another road, not words the
    /// caregiver invented. The art pipeline and Vocab Manager both read this.
    @Test func packWordsAreSystemVocabulary() throws {
        let ctx = try makeContext()
        guard let pack = PackCatalog.all.first, let first = pack.words.first else { return }

        _ = PackInstaller.install(pack, context: ctx, existing: lookup(ctx))
        try? ctx.save()

        let tile = try #require(lookup(ctx)[first.key])
        #expect(tile.isSystem)
        #expect(tile.wordClass == first.wordClass)
    }
}
}
