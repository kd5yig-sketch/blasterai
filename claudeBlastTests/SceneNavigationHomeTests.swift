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

        // `.core` explicitly: the default is `.none`, which adds nothing at all,
        // and a scaffolder with nothing to add cannot demonstrate that it
        // refrains from injecting home tiles. This is about what it does when it
        // IS placing words.
        let scaffolded = SceneNavigation.scaffold(raw, allTiles: allTiles, validKeys: validKeys,
                                                  chrome: .core)

        let homeLinks = scaffolded.pages.flatMap { page in
            page.tiles.filter { $0.link == SceneNavigation.homeLinkToken }
        }
        #expect(homeLinks.isEmpty)

        let homeKeyed = scaffolded.pages.flatMap { page in
            page.tiles.filter { $0.key == "home" }
        }
        #expect(homeKeyed.isEmpty)

        // Sanity: the strip really was placed, so an empty result isn't what made
        // the assertions above pass.
        #expect(scaffolded.pages.first?.tiles.count ?? 0 > 2)

    }

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

        // The same input WITH a strip is materially bigger — so the emptiness
        // above is the default doing its job, not the scaffolder failing.
        //
        // Still ONE page: a strip is words, never pages. "Full core board" used
        // to bring four category pages along with its words, and that coupling
        // is what the structure step replaced.
        let dressed = SceneNavigation.scaffold(raw, allTiles: allTiles, validKeys: validKeys,
                                               chrome: .core)
        #expect(dressed.pages.count == 1)
        let dressedKeys = Set(dressed.pages.flatMap { $0.tiles.map(\.key) })
        #expect(dressedKeys.count > 2)
        #expect(dressedKeys.isSuperset(of: ["crab", "starfish"]))

        withExtendedLifetime(result) {}
    }

}
}
