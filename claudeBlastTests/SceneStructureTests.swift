// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneStructureTests.swift
//  claudeBlastTests
//
//  The structure step's builder. Carries forward the "New Scene from
//  Collections" coverage that used to live on `CollectionSource.buildScene`
//  (home page of nav links, uniquified keys, mixed pack + class sources) and
//  adds what the old code could not express: that adding structure is additive,
//  which is the property the retired Focused toggle violated.
//

import Testing
import Foundation
import SwiftData
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct SceneStructureTests {
    private func makeContext() throws -> ModelContext { TestStore.freshContext() }

    @discardableResult
    private func tile(_ key: String, _ wordClass: String, into ctx: ModelContext) -> TileModel {
        let t = TileModel(key: key, wordClass: wordClass)
        ctx.insert(t)
        return t
    }
    private func allSorted(_ ctx: ModelContext) throws -> [TileModel] {
        try ctx.fetch(FetchDescriptor<TileModel>(sortBy: [SortDescriptor(\.key)]))
    }
    private func build(_ plan: SceneStructurePlan, in ctx: ModelContext,
                       existingPageKeys: Set<String> = ["home"],
                       homeTileKeys: Set<String> = [],
                       packs: [VocabPack] = [],
                       donorScenes: [BlasterScene] = []) throws -> SceneStructureResult {
        SceneStructure.build(plan,
                             existingPageKeys: existingPageKeys,
                             homeTileKeys: homeTileKeys,
                             into: ctx,
                             allTiles: try allSorted(ctx),
                             packs: packs,
                             donorScenes: donorScenes)
    }

    // MARK: - Pages per selection

    @Test func onePagePerSelectedClass() throws {
        let ctx = try makeContext()
        tile("eat", "actions", into: ctx); tile("run", "actions", into: ctx)
        tile("mom", "people", into: ctx)
        try? ctx.save()

        var plan = SceneStructurePlan()
        plan.wordClasses = ["actions", "people"]
        let result = try build(plan, in: ctx)

        #expect(result.pages.count == 2)
        // One silent home-page link per page, pointing at it.
        #expect(Set(result.homeAdditions.map(\.link)) == Set(result.pages.map(\.key)))
        #expect(result.homeAdditions.allSatisfy { !$0.isAudible })
    }

    @Test func homeLinksResolveToRealPageLinkTiles() throws {
        let ctx = try makeContext()
        tile("eat", "actions", into: ctx); tile("mom", "people", into: ctx)
        try? ctx.save()

        var plan = SceneStructurePlan()
        plan.wordClasses = ["actions", "people"]
        let result = try build(plan, in: ctx)
        try? ctx.save()

        // Each link must be a real page_link TileModel targeting its own page —
        // otherwise the nav tiles render as gaps and go nowhere.
        let installed = Set((try ctx.fetch(FetchDescriptor<TileModel>())).map(\.key))
        for entry in result.homeAdditions {
            #expect(installed.contains(entry.key))
            #expect(entry.key == PageLink.key(forPage: entry.link))
        }
    }

    @Test func collidingPageKeysAreUniquified() throws {
        let ctx = try makeContext()
        tile("eat", "actions", into: ctx)
        try? ctx.save()

        var plan = SceneStructurePlan()
        plan.wordClasses = ["actions"]
        // The scene already has a page called "actions".
        let result = try build(plan, in: ctx, existingPageKeys: ["home", "actions"])
        #expect(result.pages.map(\.key) == ["actions_2"])
    }

    @Test func packAndClassSourcesMix() throws {
        let ctx = try makeContext()
        guard let pack = PackCatalog.all.first else { return }
        tile("eat", "actions", into: ctx); tile("run", "actions", into: ctx)
        try? ctx.save()

        var plan = SceneStructurePlan()
        plan.packIDs = [pack.id]
        plan.wordClasses = ["actions"]
        let result = try build(plan, in: ctx, packs: [pack])
        try? ctx.save()

        #expect(result.pages.count == 2)
        let installed = Set((try ctx.fetch(FetchDescriptor<TileModel>())).map(\.key))
        #expect(pack.words.allSatisfy { installed.contains($0.key) })
        let actionsPage = result.pages.first { $0.tiles.contains { $0.key == "eat" } }
        #expect(actionsPage?.tiles.map(\.key).sorted() == ["eat", "run"])
    }

    @Test func aSelectionThatYieldsNothingAddsNothing() throws {
        let ctx = try makeContext()
        tile("eat", "actions", into: ctx)
        try? ctx.save()

        var plan = SceneStructurePlan()
        plan.wordClasses = ["animal"]          // no animal words in this store
        #expect(try build(plan, in: ctx).isEmpty)
    }

    @Test func anEmptyPlanAddsNothing() throws {
        let ctx = try makeContext()
        tile("eat", "actions", into: ctx)
        try? ctx.save()
        #expect(try build(SceneStructurePlan(), in: ctx).isEmpty)
    }

    // MARK: - Core words

    /// A bundle places words and brings no pages. "Full core board" used to do
    /// both, which is the coupling the structure step exists to undo — pages are
    /// ticked separately, each with its own link tile.
    @Test func aCoreStripAddsWordsAndNoPages() throws {
        let ctx = try makeContext()
        for key in ["i", "you", "want", "help", "yes", "no"] { tile(key, "social", into: ctx) }
        tile("go", "actions", into: ctx)
        tile("pizza", "food", into: ctx)
        tile("mom", "people", into: ctx)
        try? ctx.save()

        var plan = SceneStructurePlan()
        plan.chrome = .core
        let result = try build(plan, in: ctx)

        #expect(result.pages.isEmpty)
        // Every addition is a plain word: no navigation, no page behind it.
        #expect(result.homeAdditions.allSatisfy { $0.link.isEmpty && $0.isAudible })
        let added = result.homeAdditions.map(\.key)
        #expect(added.contains("i") && added.contains("want") && added.contains("go"))
        // A food page is a separate tick, so no food word rode along.
        #expect(!added.contains("pizza"))
    }

    @Test func coreWordsAlreadyOnTheHomePageAreNotDuplicated() throws {
        let ctx = try makeContext()
        for key in ["i", "you", "want", "help"] { tile(key, "social", into: ctx) }
        try? ctx.save()

        var plan = SceneStructurePlan()
        plan.chrome = .core
        let result = try build(plan, in: ctx, homeTileKeys: ["i", "want"])
        let added = result.homeAdditions.map(\.key)
        #expect(!added.contains("i") && !added.contains("want"))
        #expect(added.contains("you") && added.contains("help"))
    }

    @Test func noChromeAddsNoCoreWords() throws {
        let ctx = try makeContext()
        for key in ["i", "you", "want"] { tile(key, "social", into: ctx) }
        tile("eat", "actions", into: ctx)
        try? ctx.save()

        var plan = SceneStructurePlan()
        plan.wordClasses = ["actions"]
        let result = try build(plan, in: ctx)
        // Only the one nav link for the page that was asked for.
        #expect(result.homeAdditions.count == 1)
        #expect(result.homeAdditions.allSatisfy { !$0.link.isEmpty })
    }

    // MARK: - Outline agrees with build

    /// The live preview draws from `outline`, which is pure; the scene is made by
    /// `build`, which is not. Two walks over one plan is exactly the shape that
    /// drifts, and a preview that lies about what a toggle does is worse than no
    /// preview — so hold them to each other on every kind of source at once.
    private func outline(_ plan: SceneStructurePlan, in ctx: ModelContext,
                         existingPageKeys: Set<String> = ["home"],
                         homeTileKeys: Set<String> = [],
                         packs: [VocabPack] = [],
                         donorScenes: [BlasterScene] = []) throws -> SceneStructureOutline {
        SceneStructure.outline(plan,
                               existingPageKeys: existingPageKeys,
                               homeTileKeys: homeTileKeys,
                               allTiles: try allSorted(ctx),
                               packs: packs,
                               donorScenes: donorScenes)
    }

    @Test func theOutlineMatchesWhatBuildProduces() throws {
        let ctx = try makeContext()
        guard let pack = PackCatalog.all.first else { return }
        for key in ["i", "you", "want", "help", "yes", "no"] { tile(key, "social", into: ctx) }
        tile("eat", "actions", into: ctx); tile("run", "actions", into: ctx)
        tile("drink", "actions", into: ctx)
        tile("pizza", "food", into: ctx); tile("milk", "drinks", into: ctx)
        tile("mom", "people", into: ctx); tile("arm", "body", into: ctx)
        try? ctx.save()

        let donor = BlasterScene(name: "Donor", descriptionText: "",
                                 homePageKey: "snacks", isDefault: false, isActive: false)
        donor.pages = [PageSpec(key: "snacks", tiles: [TileEntry(key: "pizza")])]
        ctx.insert(donor)
        try? ctx.save()

        var plan = SceneStructurePlan()
        plan.chrome = .core
        plan.packIDs = [pack.id]
        plan.wordClasses = ["actions"]
        plan.donorPages = [SceneStructurePlan.donorToken(sceneID: donor.sceneID, pageKey: "snacks")]

        let predicted = try outline(plan, in: ctx, packs: [pack], donorScenes: [donor])
        let actual = try build(plan, in: ctx, packs: [pack], donorScenes: [donor])

        // Same pages, same order, same titles, same sizes.
        #expect(predicted.pages.map(\.title) == actual.pages.map(\.title))
        #expect(predicted.pages.map(\.tileCount) == actual.pages.map { $0.tiles.count })
        // Same home-page additions: core words first, then one link per page.
        let actualWords = actual.homeAdditions.filter { PageLink.targetPage(forKey: $0.key) == nil }
        let actualLinks = actual.homeAdditions.filter { PageLink.targetPage(forKey: $0.key) != nil }
        #expect(predicted.homeWords == actualWords.map(\.key))
        #expect(predicted.homeLinks.count == actualLinks.count)
    }

    @Test func theOutlineOfAnEmptyPlanIsEmpty() throws {
        let ctx = try makeContext()
        tile("eat", "actions", into: ctx)
        try? ctx.save()
        #expect(try outline(SceneStructurePlan(), in: ctx).isEmpty)
    }

    @Test func theOutlineChangesNothing() throws {
        let ctx = try makeContext()
        guard let pack = PackCatalog.all.first else { return }
        tile("eat", "actions", into: ctx)
        try? ctx.save()
        let before = (try ctx.fetch(FetchDescriptor<TileModel>())).count

        var plan = SceneStructurePlan()
        plan.chrome = .core
        plan.packIDs = [pack.id]
        plan.wordClasses = ["actions"]
        _ = try outline(plan, in: ctx, packs: [pack])

        // The preview runs on every toggle. It must not install a pack, mint a
        // page link, or otherwise touch the store.
        #expect((try ctx.fetch(FetchDescriptor<TileModel>())).count == before)
    }

    // MARK: - Applying

    /// The regression the retired Focused toggle caused: it rebuilt a scene from
    /// its home-page words, so every other page the caregiver had made vanished.
    @Test func applyingStructureKeepsEveryExistingPage() throws {
        let ctx = try makeContext()
        tile("eat", "actions", into: ctx); tile("mom", "people", into: ctx)
        try? ctx.save()

        let scene = BlasterScene(name: "Mine", descriptionText: "",
                                 homePageKey: "home", isDefault: false, isActive: false)
        scene.pages = [
            PageSpec(key: "home", tiles: [TileEntry(key: "mom")]),
            PageSpec(key: "afternoon", tiles: [TileEntry(key: "eat")]),
            PageSpec(key: "bedtime", tiles: [TileEntry(key: "mom")]),
        ]
        ctx.insert(scene)
        try? ctx.save()

        var plan = SceneStructurePlan()
        plan.wordClasses = ["actions"]
        let result = try build(plan, in: ctx, existingPageKeys: Set(scene.pages.map(\.key)),
                               homeTileKeys: ["mom"])
        scene.applyStructure(result)

        let keys = scene.pages.map(\.key)
        #expect(keys.contains("afternoon") && keys.contains("bedtime"))
        #expect(keys.count == 4)
        // The hand-made home page keeps its own tile, first.
        let home = try #require(scene.pages.first { $0.key == "home" })
        #expect(home.tiles.first?.key == "mom")
        #expect(home.tiles.count == 2)
    }

    @Test func foldingAResultIntoAGeneratedSceneAppendsPagesAndLinks() throws {
        let ctx = try makeContext()
        tile("crab", "animal", into: ctx); tile("eat", "actions", into: ctx)
        try? ctx.save()

        let bare = GeneratedScene(name: "Tidepools", description: "",
                                  homePageKey: "home",
                                  pages: [GeneratedPage(key: "home",
                                                        tiles: [GeneratedTile(key: "crab", isAudible: true, link: "")])])
        var plan = SceneStructurePlan()
        plan.wordClasses = ["actions"]
        let dressed = bare.adding(try build(plan, in: ctx))

        #expect(dressed.pages.count == 2)
        let home = try #require(dressed.pages.first { $0.key == "home" })
        #expect(home.tiles.first?.key == "crab")           // the scene's own word stays first
        #expect(home.tiles.count == 2)
        #expect(home.tiles.last?.link == "actions")
    }
}
}
