// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CollectionSourceTests.swift
//  claudeBlastTests
//
//  The unified page-seed source (P2). Covers each variant's tile production.
//

import Testing
import Foundation
import SwiftData
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct CollectionSourceTests {
    private func makeContext() throws -> ModelContext { TestStore.freshContext() }

    @discardableResult
    private func tile(_ key: String, _ wordClass: String, into ctx: ModelContext) -> TileModel {
        let t = TileModel(key: key, wordClass: wordClass)
        ctx.insert(t)
        return t
    }
    private func lookup(_ ctx: ModelContext) -> [String: TileModel] {
        let all = (try? ctx.fetch(FetchDescriptor<TileModel>())) ?? []
        return Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }
    private func allSorted(_ ctx: ModelContext) throws -> [TileModel] {
        try ctx.fetch(FetchDescriptor<TileModel>(sortBy: [SortDescriptor(\.key)]))
    }

    // MARK: - wordClass

    @Test func wordClassKeepsOnlyThatClass() throws {
        let ctx = try makeContext()
        tile("eat", "actions", into: ctx); tile("run", "actions", into: ctx); tile("dog", "animal", into: ctx)
        try? ctx.save()
        let built = CollectionSource.build(.wordClass(classes: ["actions"]),
                                           into: ctx, allTiles: try allSorted(ctx), existing: lookup(ctx))
        #expect(built?.tiles.map(\.key) == ["eat", "run"])   // vocab order, animal dropped
    }

    @Test func wordClassExcludeAndLimit() throws {
        let ctx = try makeContext()
        tile("eat", "actions", into: ctx); tile("jump", "actions", into: ctx); tile("run", "actions", into: ctx)
        try? ctx.save()
        let all = try allSorted(ctx)   // eat, jump, run
        let excluded = CollectionSource.build(.wordClass(classes: ["actions"], exclude: ["run"]),
                                              into: ctx, allTiles: all, existing: lookup(ctx))
        #expect(excluded?.tiles.map(\.key) == ["eat", "jump"])
        let limited = CollectionSource.build(.wordClass(classes: ["actions"], limit: 2),
                                             into: ctx, allTiles: all, existing: lookup(ctx))
        #expect(limited?.tiles.count == 2)
    }

    @Test func wordClassNoMatchesReturnsNil() throws {
        let ctx = try makeContext()
        tile("eat", "actions", into: ctx)
        try? ctx.save()
        #expect(CollectionSource.build(.wordClass(classes: ["animal"]),
                                       into: ctx, allTiles: try allSorted(ctx), existing: lookup(ctx)) == nil)
    }

    @Test func wordClassCombinesMultipleClassesInOrder() throws {
        let ctx = try makeContext()
        tile("eat", "actions", into: ctx); tile("dog", "animal", into: ctx); tile("run", "actions", into: ctx)
        try? ctx.save()
        let all = try allSorted(ctx)   // dog, eat, run (sorted by key)
        let built = CollectionSource.build(.wordClass(classes: ["actions", "animal"]),
                                           into: ctx, allTiles: all, existing: lookup(ctx))
        #expect(built?.tiles.map(\.key) == ["dog", "eat", "run"])   // both classes, allTiles order
        #expect(built?.displayName == "Actions & Animal")
    }

    // MARK: - keys

    @Test func keysKeepsOnlyExistingAndNamesThePage() throws {
        let ctx = try makeContext()
        tile("eat", "actions", into: ctx)
        try? ctx.save()
        let built = CollectionSource.build(.keys(["eat", "nope"], name: "My Set"),
                                           into: ctx, allTiles: [], existing: lookup(ctx))
        #expect(built?.tiles.map(\.key) == ["eat"])
        #expect(built?.displayName == "My Set")
    }

    // MARK: - copyPage

    @Test func copyPageStripsStructuralTiles() throws {
        let ctx = try makeContext()
        tile("eat", "actions", into: ctx)
        tile(PageLink.key(forPage: "food"), PageLink.wordClass, into: ctx)
        tile("back", "navigation", into: ctx)
        try? ctx.save()
        let page = PageSpec(key: "topic", tiles: [
            TileEntry(key: "eat", link: "", isAudible: true),
            TileEntry(key: PageLink.key(forPage: "food"), link: "food", isAudible: false),
            TileEntry(key: "back", link: "", isAudible: true),
        ])
        let built = CollectionSource.build(.copyPage(page), into: ctx, allTiles: [], existing: lookup(ctx))
        #expect(built?.tiles.map(\.key) == ["eat"])   // page_link + navigation dropped
        #expect(built?.baseKey == "topic")
    }

    @Test func copyPageReusesSourceCoverImage() throws {
        let ctx = try makeContext()
        tile("eat", "actions", into: ctx)
        let link = tile(PageLink.key(forPage: "food"), PageLink.wordClass, into: ctx)
        link.userImageData = Data([0x1, 0x2, 0x3])     // source page has a custom cover
        try? ctx.save()
        let page = PageSpec(key: "food", tiles: [
            TileEntry(key: "eat", link: "", isAudible: true),
            TileEntry(key: PageLink.key(forPage: "food"), link: "food", isAudible: false),
        ])
        let built = CollectionSource.build(.copyPage(page), into: ctx, allTiles: [], existing: lookup(ctx))
        if case .data(let data)? = built?.cover {
            #expect(data == Data([0x1, 0x2, 0x3]))     // .data cover arm: image carried through
        } else {
            Issue.record("expected a .data cover reusing the source page image")
        }
    }

    // MARK: - pack

    /// Regression for "adding a pack page lands only one tile".
    ///
    /// The page-commit path filters the preview's tiles through a key→tile
    /// lookup. Building a pack INSERTS tiles as a side effect, so a lookup
    /// captured before the build is missing every newly installed word — which
    /// silently committed a whole pack as a one-tile page (the single word that
    /// already existed in core vocabulary), while the preview looked correct
    /// because it renders from the generated result, not the lookup.
    ///
    /// This pins the mechanism the fix relies on: a `ModelContext` fetch made
    /// after the build sees the pending, still-unsaved inserts. If that ever
    /// stops being true, `SceneEditorView.currentTileLookup` is unsound and this
    /// test fails rather than the bug silently returning.
    @Test func packWordsAreVisibleOnlyToALookupTakenAfterTheBuild() throws {
        let ctx = try makeContext()
        guard let pack = PackCatalog.all.first, pack.words.count > 1 else { return }

        let staleLookup = lookup(ctx)          // before install — what the bug used
        guard let built = CollectionSource.build(.pack(pack), into: ctx,
                                                 allTiles: [], existing: staleLookup) else {
            Issue.record("pack build returned nil"); return
        }
        // Deliberately NOT saved — the fix depends on seeing pending inserts.
        let freshLookup = lookup(ctx)          // after install — what the fix uses

        let keptByStale = built.tiles.filter { staleLookup[$0.key] != nil }
        let keptByFresh = built.tiles.filter { freshLookup[$0.key] != nil }

        #expect(keptByStale.count < built.tiles.count)      // words WOULD be dropped
        #expect(keptByFresh.count == built.tiles.count)     // all words survive
    }

    @Test func packBuildsFromWordsAndInstallsThem() throws {
        let ctx = try makeContext()
        guard let pack = PackCatalog.all.first else { return }
        let built = CollectionSource.build(.pack(pack), into: ctx, allTiles: [], existing: [:])
        #expect(built?.baseKey == pack.slug)
        #expect(built?.tiles.map(\.key) == pack.words.map(\.key))
        try? ctx.save()
        let installed = Set((try ctx.fetch(FetchDescriptor<TileModel>())).map(\.key))
        #expect(pack.words.allSatisfy { installed.contains($0.key) })
    }
}
}
