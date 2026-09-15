// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CollectionSource.swift
//  claudeBlast
//
//  A unified "source of tiles" for seeding a page (or, later, a whole scene).
//  Page creation used to resolve packs, copied pages, and class/keys sets in
//  separate inline code paths; this collapses tile production into one place.
//  Each source resolves to a `Built` (tiles + a suggested page name + a cover
//  image); the caller uniquifies the key, appends the page, and mints the nav
//  link (see `SceneEditorView.commitBuilt`, and `SceneStructure.build` for the
//  many-sources-at-once case). AI generation is NOT a source — it produces its
//  own multi-page `GeneratedPageResult` and keeps its own path.
//

import Foundation
import SwiftData

enum CollectionSource {
    /// A vocabulary pack (its words are installed on build).
    case pack(VocabPack)
    /// A page copied from another scene (structural / nav tiles dropped).
    case copyPage(PageSpec)
    /// Every tile of the given word class(es), in vocabulary order.
    case wordClass(classes: [String], exclude: Set<String> = [], limit: Int? = nil)
    /// An explicit set of existing tile keys, with a page name.
    case keys([String], name: String)

    /// How the page's nav-link tile gets its image.
    enum Cover {
        case data(Data)      // explicit cover image (a pack icon / copied page's image)
        case key(String?)    // alias an existing tile's set art (nil → PageLink default)
    }

    struct Built {
        var baseKey: String       // suggested page key — caller uniquifies against the scene
        var displayName: String   // for the nav-link tile
        var tiles: [TileEntry]
        var cover: Cover
    }

    /// Resolve to a `Built` page, performing any needed side effects (installing a
    /// pack's words into `context`). `existing` is the key→tile lookup. Returns
    /// nil when the source yields no usable tiles.
    static func build(_ source: CollectionSource, into context: ModelContext,
                      allTiles: [TileModel], existing: [String: TileModel]) -> Built? {
        switch source {
        case .pack(let pack):
            PackInstaller.install(pack, context: context, existing: existing)
            let tiles = pack.words.map { TileEntry(key: $0.key, link: "", isAudible: true) }
            guard !tiles.isEmpty else { return nil }
            return Built(baseKey: pack.slug, displayName: pack.displayName,
                         tiles: tiles, cover: .key(PackCatalog.coverKey(for: pack)))

        case .copyPage(let page):
            let tiles = copyableTiles(from: page, lookup: existing)
            guard !tiles.isEmpty else { return nil }
            let displayName = page.key.replacingOccurrences(of: "_", with: " ").capitalized
            // Reuse the source page's page_link image so the copy looks the same;
            // fall back to a representative tile if the source had none.
            let srcLink = existing[PageLink.key(forPage: page.key)]
            let cover: Cover
            // NB: `srcLink?.userImageData` is non-optional through the chain, so it
            // must be tested for emptiness — a bare `if let` would bind to an empty
            // Data and dead-code the fallback below.
            if let data = srcLink?.userImageData, !data.isEmpty {
                cover = .data(data)
            } else {
                let aliased = (srcLink?.bundleImage).flatMap { $0.isEmpty ? nil : $0 }
                cover = .key(aliased ?? tiles.first?.key)
            }
            return Built(baseKey: page.key, displayName: displayName, tiles: tiles, cover: cover)

        case .wordClass(let classes, let exclude, let limit):
            let classSet = Set(classes)
            var keys = allTiles
                .filter { classSet.contains($0.wordClass) && !exclude.contains($0.key) && !$0.isRetired }
                .map(\.key)                                   // vocabulary order preserved
            if let limit { keys = Array(keys.prefix(limit)) }
            guard !keys.isEmpty else { return nil }
            let name = classes.map { $0.capitalized }.joined(separator: " & ")
            return Built(baseKey: TileModel.normalizeKey(classes.joined(separator: "_")),
                         displayName: name,
                         tiles: keys.map { TileEntry(key: $0, link: "", isAudible: true) },
                         cover: .key(keys.first))

        case .keys(let rawKeys, let name):
            let tiles = rawKeys
                .filter { existing[$0]?.isRetired == false }
                .map { TileEntry(key: $0, link: "", isAudible: true) }
            guard !tiles.isEmpty else { return nil }
            return Built(baseKey: TileModel.normalizeKey(name), displayName: name,
                         tiles: tiles, cover: .key(tiles.first?.key))
        }
    }

    /// Word tiles of `page` that exist in vocab and aren't structural (page-link /
    /// navigation) — as fresh terminal `TileEntry`s (links dropped).
    private static func copyableTiles(from page: PageSpec, lookup: [String: TileModel]) -> [TileEntry] {
        page.tiles.compactMap { entry in
            guard let t = lookup[entry.key], !t.isRetired,
                  !t.isStructuralChrome else { return nil }
            return TileEntry(key: t.key, link: "", isAudible: true)
        }
    }
}
