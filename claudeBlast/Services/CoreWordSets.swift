// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CoreWordSets.swift
//  claudeBlast
//
//  The core word sets — min-core and the full core board — as data.
//
//  ## Why they are a file
//
//  They were two `private` Swift arrays in `SceneNavigation`, read by exactly
//  one thing (`ChromeBundle`). The moment a second reader appeared — a filter in
//  the tile picker, so a therapist can see *"the words we consider core"*, which
//  is a cut the picker could not make — a literal in an enum became a list that
//  has to agree with itself in two places. One file, two readers.
//
//  It also matters for localization: `TileModel.key` is a language-neutral
//  concept id, never translated, so a localized build changes display names and
//  keeps the sets intact — but only if the sets are something you can ship and
//  edit, rather than a literal compiled into the binary.
//
//  ## Why `source` is not optional
//
//  Mark, 2026-09-15, asking the question every SLP reviewer will ask: *"for these
//  two sets, where did you get the list of words? Make them up? Or from research
//  and some reasonable sources?"*
//
//  The honest answer at the time: neither list had a citation. `full_core` is a
//  snapshot of this app's own Core-First home page; `min_core` was reduced from
//  it by hand. Both are plausible — high-frequency words are high-frequency — but
//  plausible is not provenance, and an AAC core vocabulary presented to a
//  clinician without a source invites exactly one question.
//
//  So every set carries where it came from, and the decoder **rejects a set with
//  an empty `source.label`**. A list whose origin nobody recorded is the failure
//  this field exists to prevent; making it merely optional would reproduce the
//  situation that prompted it. Published sets (Project Core's Universal Core,
//  Banajee et al. 2003, Boenisch & Soto 2015) can then be added as data with
//  their citation attached, rather than as a code change.
//

import Foundation

/// Where a set's words came from. Shown wherever the set is offered, so the
/// provenance travels with the list instead of living in someone's memory.
struct CoreWordSetSource: Codable, Hashable {
    /// `in_house` or `published` — what kind of claim this is.
    let kind: String
    /// Short caregiver-facing attribution ("BlasterAI, in-house").
    let label: String
    /// The honest long form, including what has *not* been checked.
    let detail: String
    /// Full reference when `kind == "published"`; empty otherwise.
    let citation: String

    var isPublished: Bool { kind == "published" }
}

/// A named set of core vocabulary keys.
struct CoreWordSet: Codable, Identifiable, Hashable {
    /// Stable id — `min_core`, `full_core`. Also the filter token in the picker.
    let id: String
    let displayName: String
    let summary: String
    let source: CoreWordSetSource
    /// Language-neutral concept ids, in board order.
    let keys: [String]
    /// Words that both speak and navigate, when the set is laid on a home page.
    /// Absent for sets that are purely a word list.
    var links: [CoreWordSetLink] = []

    var keySet: Set<String> { Set(keys) }

    init(id: String, displayName: String, summary: String, source: CoreWordSetSource,
         keys: [String], links: [CoreWordSetLink] = []) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.source = source
        self.keys = keys
        self.links = links
    }
}

extension CoreWordSet {
    private enum CodingKeys: String, CodingKey {
        case id, displayName, summary, source, keys, links
    }

    /// Hand-written for the same reason `PageSpec`'s and `GeneratedPage`'s are:
    /// Swift's synthesized decoder throws on a missing key rather than using the
    /// property's default, so a set with no `links` — which min-core has none of
    /// — would fail to decode and take the whole file down with it. It did,
    /// silently: `all` came back empty and every "for set in all" assertion
    /// passed vacuously.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  displayName: try c.decode(String.self, forKey: .displayName),
                  summary: try c.decodeIfPresent(String.self, forKey: .summary) ?? "",
                  source: try c.decode(CoreWordSetSource.self, forKey: .source),
                  keys: try c.decodeIfPresent([String].self, forKey: .keys) ?? [],
                  links: try c.decodeIfPresent([CoreWordSetLink].self, forKey: .links) ?? [])
    }
}

struct CoreWordSetLink: Codable, Hashable {
    let key: String
    /// Page key this tile navigates to.
    let to: String
}

enum CoreWordSets {
    private struct Manifest: Codable {
        let version: String
        let sets: [CoreWordSet]
    }

    /// Every set, in file order. Decoded once.
    ///
    /// A set with no `source.label` is dropped rather than shipped: see the note
    /// at the top of this file. Returning it anyway would let an unattributed
    /// word list reach a clinician, which is the one outcome this is here to
    /// prevent.
    static let all: [CoreWordSet] = {
        guard let url = Bundle.main.url(forResource: "core_sets", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return [] }
        return manifest.sets.filter { !$0.source.label.isEmpty && !$0.keys.isEmpty }
    }()

    static func set(id: String) -> CoreWordSet? { all.first { $0.id == id } }

    /// Keys of `id`, or empty when the set is absent — a missing file must leave
    /// the structure step adding nothing, never crash mid-authoring.
    static func keys(_ id: String) -> [String] { set(id: id)?.keys ?? [] }

    static func links(_ id: String) -> [CoreWordSetLink] { set(id: id)?.links ?? [] }

    // Ids used by `SceneNavigation.ChromeBundle`, named rather than spelled out
    // at each use so a rename in the JSON is one edit here.
    static let needsID = "needs_feelings"
    static let coreID = "core_words"
}
