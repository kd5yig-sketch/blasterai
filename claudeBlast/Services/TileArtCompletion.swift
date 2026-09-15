// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileArtCompletion.swift
//  claudeBlast
//
//  Finishing one word's art in one style, without touching the art it already
//  has.
//
//  ## Why this is its own thing
//
//  "Generate" draws a word from scratch, covering whatever `ArtPlan` says the
//  caregiver's settings ask for. That is the right call for a word with no
//  pictures and the wrong one for a word that has some: with *Generate all
//  styles* on it redraws every style, including the one whose picture the
//  caregiver chose and kept. There was no way to say "leave what I have and fill
//  the rest" — not per word, and until the scene editor's Art Coverage section,
//  not in bulk either.
//
//  Completion is the other verb. Per style it does whichever of two jobs that
//  style needs, and they are genuinely different work:
//
//  - **Transform**, when the style already has a picture. One call per missing
//    variant, derived from the art that exists, so the figure stays the same.
//  - **Draw**, when the style has nothing. A fresh picture plus its variants as a
//    single plan, so the whole style shares one figure the way a new word does.
//
//  Both the scene-level batch (`SceneImageBatchController.Mode.completeStyle`)
//  and the per-tile button in `TilePhotoSection` run through here, so the two
//  cannot answer the same question differently.
//

import Foundation
import UIKit

enum TileArtCompletion {
    /// What finishing one style for one word will take.
    struct Work {
        let style: TileStyle
        /// Sets that have no art yet.
        let missing: [ImageSetID]
        /// True when the style has nothing at all, so it must be drawn rather
        /// than transformed — the caller says so, because it is a new picture
        /// rather than a recolour of a familiar one.
        let needsDrawing: Bool

        var isComplete: Bool { missing.isEmpty }
    }

    /// What `style` still owes `tile`.
    @MainActor
    static func work(completing style: TileStyle, for tile: TileModel,
                     resolver: TileImageResolver) -> Work {
        let missing = SceneImageBatch.missingVariants(of: style, for: tile, resolver: resolver)
        let have = style.variants.count - missing.count
        return Work(style: style, missing: missing, needsDrawing: have == 0)
    }

    /// Every generatable style this tile is not complete in, active style first.
    @MainActor
    static func incompleteStyles(for tile: TileModel,
                                 resolver: TileImageResolver) -> [Work] {
        ImageSetCatalog.generationTargets(preferring: resolver.activeSet)
            .map { work(completing: $0, for: tile, resolver: resolver) }
            .filter { !$0.isComplete }
    }

    /// Produce the images that finish `style` for `tile`.
    ///
    /// Returns what was generated; the caller commits. An empty result means the
    /// style was already complete or every call failed — compare against
    /// `work(completing:)`'s `missing` to tell those apart rather than assuming.
    @MainActor
    static func generate(completing style: TileStyle, for tile: TileModel,
                         apiKey: String, resolver: TileImageResolver) async -> [ImageSetID: UIImage] {
        let existing = SceneImageBatch.existingArt(of: style, for: tile, resolver: resolver)
        guard existing.isEmpty else {
            return await TileImageGenerator.fillMissingVariants(
                style: style, existing: existing, apiKey: apiKey)
        }
        // Nothing to transform: draw the base and its variants as one plan, so
        // every variant of this style derives from a single figure.
        let plan = [PlannedStyle(style: style, variants: style.variants)]
        return await TileImageGenerator.generate(
            displayName: tile.displayName, wordClass: tile.wordClass,
            plan: plan, apiKey: apiKey)
    }
}
