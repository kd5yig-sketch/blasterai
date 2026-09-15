// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneNavigationHomeTests.swift
//  claudeBlastTests
//
//  No authored board carries a back-to-home tile.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct SceneNavigationHomeTests {

    private func makeTestContainer() throws -> ModelContainer {
        TestStore.freshContainer()
    }

    /// The scaffolder used to inject a `<home>` tile at the head of every
    /// category page it built. `HomeGridCell` now occupies cell 0 of every page,
    /// so an authored one is a duplicate control that costs a word slot — and
    /// gives the child two things to learn for one action.
    ///
    /// This guards the *generator*: a bundled board can be fixed by editing
    /// JSON once, but a scaffolder that injects home tiles quietly re-creates
    /// them in every scene a caregiver generates from then on.
    @Test func scaffoldedScenesCarryNoHomeTile() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let result = BootstrapLoader.loadDefaultVocabulary(context: ctx)
        let allTiles = try ctx.fetch(FetchDescriptor<TileModel>())
        let validKeys = Set(allTiles.map(\.key))

        let raw = GeneratedScene(
            name: "Test Scene",
            description: "scaffolder input",
            homePageKey: "home",
            pages: [GeneratedPage(key: "home", tiles: [
                GeneratedTile(key: "mom", isAudible: true, link: ""),
                GeneratedTile(key: "pizza", isAudible: true, link: ""),
            ])]
        )

        // `.fullCore` explicitly: the default is now `.none`, which builds no
        // category pages at all — and a scaffolder with nothing to build cannot
        // demonstrate that it refrains from injecting home tiles. This test is
        // about what the scaffolder does when it IS building structure.
        let scaffolded = SceneNavigation.scaffold(raw, allTiles: allTiles, validKeys: validKeys,
                                                  chrome: .fullCore)

        let homeLinks = scaffolded.pages.flatMap { page in
            page.tiles.filter { $0.link == SceneNavigation.homeLinkToken }
        }
        #expect(homeLinks.isEmpty)

        let homeKeyed = scaffolded.pages.flatMap { page in
            page.tiles.filter { $0.key == "home" }
        }
        #expect(homeKeyed.isEmpty)

        // Sanity: the scaffolder still built category pages, so an empty result
        // isn't what made the assertions above pass.
        #expect(scaffolded.pages.count > 1)

        // And sibling cross-links survive — food ↔ drinks is a real shortcut
        // between two topic pages, not a duplicate of a control we supply. This
        // lives here rather than in its own test because `loadDefaultVocabulary`
        // is hash-based: a second call in the same run is a no-op, leaving an
        // empty store and a scaffolder with nothing to link. Sharing the one
        // live bootstrap removes that ordering dependency.
        let crossLinks = scaffolded.pages.flatMap { page in
            page.tiles.filter { !$0.link.isEmpty && $0.link != SceneNavigation.homeLinkToken }
        }
        #expect(!crossLinks.isEmpty)

        withExtendedLifetime(result) {}
    }

    /// Generation supplies NOTHING but the scene's own tiles.
    ///
    /// This is the contract the structure step depends on. Scenes used to arrive
    /// pre-wrapped in a core cluster and four category pages, which made a
    /// generated scene impossible to reason about — you could not tell what the
    /// model produced from what we had added — and the only control over it was
    /// a toggle that rebuilt the scene and dropped every hand-made page.
    ///
    /// If this regresses, the structure sheet starts double-adding chrome the
    /// scene already silently had.
    @Test func generationAddsNoChromeByDefault() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let result = BootstrapLoader.loadDefaultVocabulary(context: ctx)
        let allTiles = try ctx.fetch(FetchDescriptor<TileModel>())
        let validKeys = Set(allTiles.map(\.key))

        let raw = GeneratedScene(
            name: "Tide pools",
            description: "topical only",
            homePageKey: "home",
            pages: [GeneratedPage(key: "home", tiles: [
                GeneratedTile(key: "crab", isAudible: true, link: ""),
                GeneratedTile(key: "starfish", isAudible: true, link: ""),
            ])]
        )

        let bare = SceneNavigation.scaffold(raw, allTiles: allTiles, validKeys: validKeys)

        // One page, holding only the words the model asked for.
        #expect(bare.pages.count == 1)
        #expect(Set(bare.pages.flatMap { $0.tiles.map(\.key) }) == ["crab", "starfish"])

        // Nothing navigates anywhere, because there is nowhere to navigate to.
        #expect(bare.pages.allSatisfy { $0.tiles.allSatisfy { $0.link.isEmpty } })

        // The same input WITH chrome is materially bigger — so the emptiness
        // above is the default doing its job, not the scaffolder failing.
        let dressed = SceneNavigation.scaffold(raw, allTiles: allTiles, validKeys: validKeys,
                                               chrome: .fullCore)
        #expect(dressed.pages.count > bare.pages.count)

        withExtendedLifetime(result) {}
    }

}
}
