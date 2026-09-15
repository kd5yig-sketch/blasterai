// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneArtCoverageTests.swift
//  claudeBlastTests
//
//  Per-style art coverage for a scene — the report that replaced two transient
//  offers a word could fall through.
//

import Testing
import Foundation
import SwiftData
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct SceneArtCoverageTests {

    /// The container has to outlive the body, or the context dies with it and
    /// every fetch crashes rather than failing an expectation.
    private func withResolver(_ body: (TileImageResolver, ModelContext) throws -> Void) throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: BlasterSchemaV1.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let resolver = TileImageResolver()
        resolver.configure(modelContext: container.mainContext)
        try body(resolver, container.mainContext)
        withExtendedLifetime(container) {}
    }

    /// A caregiver word with no art anywhere — `bundleImage` points at a key the
    /// bundle has nothing for, so nothing resolves in any style.
    @discardableResult
    private func artlessWord(_ key: String, into ctx: ModelContext) -> TileModel {
        let tile = TileModel(key: key, value: key.capitalized, wordClass: "animal")
        tile.isSystem = false
        ctx.insert(tile)
        return tile
    }

    private func scene(with keys: [String], into ctx: ModelContext) -> BlasterScene {
        let scene = BlasterScene(name: "Test", descriptionText: "",
                                 homePageKey: "home", isDefault: false, isActive: false)
        scene.pages = [PageSpec(key: "home", tiles: keys.map { TileEntry(key: $0) })]
        ctx.insert(scene)
        return scene
    }

    private func lookup(_ ctx: ModelContext) -> [String: TileModel] {
        let all = (try? ctx.fetch(FetchDescriptor<TileModel>())) ?? []
        return Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Every generatable style is reported

    /// The defect this whole report exists for: the scene editor used to ask
    /// about the active style only, so a word with Classic art was invisible to
    /// every scene-level surface even though Playful 3D and High Contrast had
    /// nothing for it. Coverage must name a row per generatable style whether or
    /// not the caregiver is standing in it.
    @Test func coverageReportsEveryGeneratableStyle() throws {
        try withResolver { resolver, ctx in
            artlessWord("wumpus", into: ctx)
            let s = scene(with: ["wumpus"], into: ctx)
            try ctx.save()

            let coverage = SceneImageBatch.coverage(in: s, tileLookup: lookup(ctx),
                                                    resolver: resolver)
            #expect(coverage.count == ImageSetCatalog.generationTargets.count)
            #expect(coverage.count > 1)          // otherwise this proves nothing
            #expect(coverage.allSatisfy { !$0.isComplete })
        }
    }

    /// Active style first, so the caregiver's own board is the row they reach for.
    @Test func theActiveStyleLeads() throws {
        try withResolver { resolver, ctx in
            artlessWord("wumpus", into: ctx)
            let s = scene(with: ["wumpus"], into: ctx)
            try ctx.save()

            let coverage = SceneImageBatch.coverage(in: s, tileLookup: lookup(ctx),
                                                    resolver: resolver)
            let active = ImageSetCatalog.style(for: resolver.activeSet)
            #expect(coverage.first?.style == active)
        }
    }

    // MARK: - The two jobs are separated

    /// A word with nothing in a style needs it *drawn*; a word with some of its
    /// variants needs a *recolour*. They cost differently and only one keeps the
    /// figure, so collapsing them into one number would let a caregiver ask for
    /// twenty fresh drawings believing they asked for twenty recolours.
    @Test func aWordWithNoArtInAStyleNeedsABase() throws {
        try withResolver { resolver, ctx in
            artlessWord("wumpus", into: ctx)
            let s = scene(with: ["wumpus"], into: ctx)
            try ctx.save()

            let coverage = SceneImageBatch.coverage(in: s, tileLookup: lookup(ctx),
                                                    resolver: resolver)
            for entry in coverage {
                #expect(entry.needsBase.map(\.key) == ["wumpus"])
                #expect(entry.needsVariants.isEmpty)
                #expect(entry.wordCount == 1)
            }
        }
    }

    /// Bundled vocabulary has real art in every shipped style, so a scene built
    /// only from it reports complete — the quiet state the section shows rather
    /// than disappearing.
    @Test func bundledWordsAreAlreadyCovered() throws {
        try withResolver { resolver, ctx in
            // `eat` ships art in every set; use the bundle rather than a stub so
            // this fails if shipped coverage ever regresses.
            let tile = TileModel(key: "eat", value: "eat", wordClass: "actions")
            ctx.insert(tile)
            let s = scene(with: ["eat"], into: ctx)
            try ctx.save()

            let coverage = SceneImageBatch.coverage(in: s, tileLookup: lookup(ctx),
                                                    resolver: resolver)
            #expect(coverage.allSatisfy { $0.isComplete })
        }
    }

    // MARK: - Per-tile completion agrees with the batch

    /// The scene batch and the per-tile button both finish a style through
    /// `TileArtCompletion`. If they disagreed, "finish Playful 3D" would mean one
    /// thing from the scene editor and another from Tile Settings.
    @Test func aWordWithNothingInAStyleIsDrawnNotRecolored() throws {
        try withResolver { resolver, ctx in
            let tile = artlessWord("wumpus", into: ctx)
            try ctx.save()

            for style in ImageSetCatalog.generationTargets {
                let work = TileArtCompletion.work(completing: style, for: tile,
                                                  resolver: resolver)
                #expect(work.needsDrawing)
                #expect(work.missing.count == style.variants.count)
                #expect(!work.isComplete)
            }
        }
    }

    /// A word the bundle covers has no gaps to offer, so the per-tile expander
    /// shows the quiet "art in every style" line rather than a list of actions.
    @Test func aCoveredWordOffersNoStylesToFill() throws {
        try withResolver { resolver, ctx in
            let tile = TileModel(key: "eat", value: "eat", wordClass: "actions")
            ctx.insert(tile)
            try ctx.save()
            let gaps = TileArtCompletion.incompleteStyles(for: tile, resolver: resolver)
            #expect(gaps.isEmpty)
        }
    }

    /// Per-tile gaps come in the same order the scene rows use, so the
    /// caregiver's own style is the first thing offered in both places.
    @Test func perTileGapsLeadWithTheActiveStyle() throws {
        try withResolver { resolver, ctx in
            let tile = artlessWord("wumpus", into: ctx)
            try ctx.save()
            let gaps = TileArtCompletion.incompleteStyles(for: tile, resolver: resolver)
            let active = ImageSetCatalog.style(for: resolver.activeSet)
            #expect(gaps.first?.style == active)
            #expect(gaps.count == ImageSetCatalog.generationTargets.count)
        }
    }

    // MARK: - Shape

    @Test func anEmptySceneReportsNothing() throws {
        try withResolver { resolver, ctx in
            let s = scene(with: [], into: ctx)
            try ctx.save()
            let coverage = SceneImageBatch.coverage(in: s, tileLookup: lookup(ctx),
                                                    resolver: resolver)
            #expect(coverage.isEmpty)
        }
    }

    /// A word placed on three pages is one word to illustrate, not three.
    @Test func aWordOnSeveralPagesIsCountedOnce() throws {
        try withResolver { resolver, ctx in
            artlessWord("wumpus", into: ctx)
            let s = scene(with: ["wumpus"], into: ctx)
            s.pages.append(PageSpec(key: "more", tiles: [TileEntry(key: "wumpus")]))
            try ctx.save()

            let coverage = SceneImageBatch.coverage(in: s, tileLookup: lookup(ctx),
                                                    resolver: resolver)
            #expect(coverage.allSatisfy { $0.wordCount == 1 })
        }
    }
}
}
