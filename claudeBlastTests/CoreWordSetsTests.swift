// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CoreWordSetsTests.swift
//  claudeBlastTests
//
//  The core word sets, now data rather than two literals in `SceneNavigation`.
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct CoreWordSetsTests {

    @Test func theBundledSetsDecode() {
        #expect(CoreWordSets.all.count >= 2)
        #expect(CoreWordSets.set(id: CoreWordSets.needsID) != nil)
        #expect(CoreWordSets.set(id: CoreWordSets.coreID) != nil)
    }

    /// Every set says where it came from.
    ///
    /// This is the point of the file. Mark asked where these word lists came
    /// from and the honest answer was "nowhere recorded" — plausible lists with
    /// no provenance, which is exactly what an SLP reviewer asks about first. A
    /// set that cannot answer is dropped by the loader rather than shipped, so
    /// this asserts the survivors can.
    @Test func everySetCarriesItsProvenance() {
        for set in CoreWordSets.all {
            #expect(!set.source.label.isEmpty, "\(set.id) has no source label")
            #expect(!set.source.detail.isEmpty, "\(set.id) has no source detail")
            #expect(!set.displayName.isEmpty)
            #expect(!set.summary.isEmpty)
            // A published set must cite; an in-house one must not pretend to.
            if set.source.isPublished {
                #expect(!set.source.citation.isEmpty, "\(set.id) claims published with no citation")
            }
        }
    }

    /// The words have to exist, or a filter chip offers an empty grid and the
    /// structure step silently adds less than it says.
    @Test func everyKeyIsALanguageNeutralConceptID() {
        for set in CoreWordSets.all {
            for key in set.keys {
                #expect(key == TileModel.normalizeKey(key), "\(set.id): \(key) is not a normalized key")
            }
        }
    }

    /// The two sets are different *kinds* of word, not more and less of one
    /// thing, and the audit is why: every needs word — `hungry`, `hurt`,
    /// `scared` — is absent from all four published core lists, because they are
    /// states to report rather than words that combine. They overlap only where
    /// a word is honestly both.
    @Test func theTwoSetsAreDifferentKindsOfWord() throws {
        let needs = try #require(CoreWordSets.set(id: CoreWordSets.needsID))
        let core = try #require(CoreWordSets.set(id: CoreWordSets.coreID))
        #expect(!needs.keySet.isSubset(of: core.keySet))
        #expect(!core.keySet.isSubset(of: needs.keySet))
        // The states we chose ourselves are in needs and nowhere else.
        for key in ["hungry", "thirsty", "hurt", "sick", "scared", "tired"] {
            #expect(needs.keySet.contains(key), "needs is missing \(key)")
            #expect(!core.keySet.contains(key), "\(key) is not core vocabulary")
        }
    }

    /// The words four independent published lists agree on. If one disappears
    /// from the set, that is a decision someone should have to make on purpose.
    @Test func coreCarriesTheConsensusWords() throws {
        let core = try #require(CoreWordSets.set(id: CoreWordSets.coreID))
        for key in ["i", "you", "want", "go", "more", "stop", "not", "help",
                    "look", "like", "on", "in", "up", "here", "that", "what",
                    "some", "all", "good", "same", "different", "make", "put",
                    "get", "do", "open", "off", "it", "yes", "no", "all_done"] {
            #expect(core.keySet.contains(key), "core is missing \(key)")
        }
    }

    @Test func aSetHasNoDuplicateKeys() {
        for set in CoreWordSets.all {
            #expect(set.keySet.count == set.keys.count, "\(set.id) repeats a key")
        }
    }

    // MARK: - The chrome bundles read the file

    /// `ChromeBundle` used to own these as private arrays. It now reads the same
    /// file the picker filters by, which is the whole reason for the move: two
    /// readers of one list must not become two copies of it.
    @Test func chromeBundlesResolveThroughTheData() {
        #expect(SceneNavigation.ChromeBundle.none.clusterKeys.isEmpty)
        #expect(SceneNavigation.ChromeBundle.needs.clusterKeys
                == CoreWordSets.keys(CoreWordSets.needsID))
        #expect(SceneNavigation.ChromeBundle.core.clusterKeys
                == CoreWordSets.keys(CoreWordSets.coreID))
    }

    /// A bundle is a strip of words and nothing else.
    ///
    /// "Full core board" used to both place words *and* bring the people / food /
    /// drinks / body-health pages — one control making two decisions, which is
    /// the coupling the whole structure step exists to undo. Pages are ticked
    /// separately now, each with its own link tile.
    @Test func aBundleAddsWordsAndNeverPages() {
        for bundle in SceneNavigation.ChromeBundle.allCases {
            let plan = SceneStructurePlan(chrome: bundle)
            #expect(plan.packIDs.isEmpty && plan.wordClasses.isEmpty
                    && plan.donorPages.isEmpty)
        }
        #expect(SceneNavigation.ChromeBundle.allCases.count == 3)
    }

    /// A bundle's title comes from the file, so renaming a set is one edit.
    @Test func bundleTitlesComeFromTheData() throws {
        let needs = try #require(CoreWordSets.set(id: CoreWordSets.needsID))
        #expect(SceneNavigation.ChromeBundle.needs.title == needs.displayName)
        #expect(SceneNavigation.ChromeBundle.none.title == "Nothing")
    }

    /// `can` was the one published core word our vocabulary could not put on a
    /// board at all — on Universal Core and the PRC-Saltillo 100, and the word a
    /// child needs to refuse or ask permission.
    ///
    /// Adding it was not a one-line change: `ImageSetCoverageTests` requires art
    /// in every shippable set, so the word could not land until all five sets had
    /// a picture. They do now.
    @Test func canIsInTheVocabularyAndInCore() throws {
        let url = try #require(Bundle.main.url(forResource: "vocabulary", withExtension: "json"))
        let data = try Data(contentsOf: url)
        // Raw JSON rather than [TileModel]: the model is a SwiftData @Model and
        // BootstrapLoader has its own decode path for it.
        let rows = try JSONSerialization.jsonObject(with: data) as? [[String: String]]
        #expect(rows?.contains { $0["key"] == "can" } == true)
        let core = try #require(CoreWordSets.set(id: CoreWordSets.coreID))
        #expect(core.keySet.contains("can"))
    }
}
}
