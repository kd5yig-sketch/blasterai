// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneImageBatchSheet.swift
//  claudeBlast
//
//  Generates art for a scene's newly-introduced caregiver words, one at a time
//  (image generation is ~10–20s each). The work is owned by an @Observable
//  controller held by the scene editor, not by this sheet — so the caregiver can
//  let it keep running in the background after dismissing the sheet, pause and
//  resume it, or cancel it outright. Reuses the per-tile generator
//  (TileImageGenerator) + commit (TilePhotoCommit) so results match generating
//  each tile by hand.
//

import SwiftUI
import SwiftData
import UIKit

/// App-level registry of per-scene art controllers. Held in the environment so a
/// background run survives the scene editor being dismissed and re-entered — the
/// editor reattaches to the same controller (and its in-flight task) by scene id
/// rather than spawning a fresh one.
@MainActor
@Observable
final class SceneArtCoordinator {
    @ObservationIgnored private var controllers: [String: SceneImageBatchController] = [:]

    func controller(for sceneID: String) -> SceneImageBatchController {
        if let existing = controllers[sceneID] { return existing }
        let controller = SceneImageBatchController()
        controllers[sceneID] = controller
        return controller
    }
}

/// Drives batch tile-art generation for one scene. Lives on the scene editor so
/// generation survives the progress sheet being dismissed ("continue in the
/// background"). Pause stops after the in-flight image and is resumable; cancel
/// abandons the run.
@MainActor
@Observable
final class SceneImageBatchController {
    enum Phase { case idle, running, paused, finished }

    private(set) var phase: Phase = .idle
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var currentName = ""
    private(set) var failures: [String] = []

    /// What this run is doing. Drawing new art and filling in a style's missing
    /// variants share every bit of the machinery around them — the queue, pause,
    /// resume, background survival, failure list — and differ only in the call
    /// made per word, so they are one controller with two modes rather than two
    /// near-identical controllers.
    enum Mode: Equatable {
        /// Draw art for words that have none, covering whatever `ArtPlan` says
        /// the caregiver's settings ask for.
        case newArt
        /// Transform existing art into the variants this style is missing.
        case fillVariants(TileStyle)
        /// Finish one named style for every word in the queue, doing per word
        /// whatever that word needs: draw a base where the style has nothing,
        /// transform where it has some.
        ///
        /// A style with no art at all could not be recovered before. `newArt`
        /// reads the active set and the "all styles" default out of
        /// `UserDefaults`, so it cannot be aimed; `fillVariants` has nothing to
        /// transform. Between them a word added on Classic could never get
        /// Playful 3D in bulk, which is the defect this mode exists for.
        case completeStyle(TileStyle)
    }

    private(set) var mode: Mode = .newArt

    /// What to make per word — see `ArtPlan`, which owns the whole decision so
    /// this sheet and the two per-word surfaces cannot drift apart.
    private var artPlan: [PlannedStyle] {
        ArtPlan.plan(activeSet: resolver?.activeSet ?? ImageSetID.defaultSet)
    }

    private var queue: [TileModel] = []
    private var task: Task<Void, Never>?
    /// Styles queued behind the one running, each with its own words.
    ///
    /// The controller is deliberately one run at a time — pause, resume and
    /// background survival all assume a single queue, and two concurrent runs
    /// would double the API concurrency for no benefit. But finishing Classic
    /// and then wanting Playful 3D *and* High Contrast meant coming back to tap
    /// a second row, which is the only thing that was actually annoying. So a
    /// sweep chains them: still one queue, drained style by style.
    private var pendingJobs: [(style: TileStyle, tiles: [TileModel])] = []
    private var pauseRequested = false
    /// True when generation was paused by the app going to the background, so we
    /// know to resume it (and only it) when the app returns to the foreground.
    private var autoPaused = false

    var remaining: Int { max(total - completed, 0) }

    // Captured at start so resume() needs no arguments.
    private var apiKey = ""
    private var context: ModelContext?
    private var resolver: TileImageResolver?

    var isActive: Bool { phase == .running || phase == .paused }

    /// Finish several styles in one run, one after another.
    ///
    /// `total` counts every word across every style, so the progress figure is
    /// the whole job rather than resetting at each style boundary.
    func startSweep(_ jobs: [(style: TileStyle, tiles: [TileModel])], apiKey: String,
                    context: ModelContext, resolver: TileImageResolver) {
        let work = jobs.filter { !$0.tiles.isEmpty }
        guard !isActive, let first = work.first, !apiKey.isEmpty else { return }
        pendingJobs = Array(work.dropFirst())
        start(tiles: first.tiles, mode: .completeStyle(first.style), apiKey: apiKey,
              context: context, resolver: resolver,
              total: work.reduce(0) { $0 + $1.tiles.count })
    }

    func start(tiles: [TileModel], mode: Mode = .newArt, apiKey: String,
               context: ModelContext, resolver: TileImageResolver,
               total: Int? = nil) {
        guard !isActive, !tiles.isEmpty, !apiKey.isEmpty else { return }
        // A plain start is its own whole job; only `startSweep` sets this first.
        if case .completeStyle = mode {} else { pendingJobs = [] }
        self.mode = mode
        self.apiKey = apiKey
        self.context = context
        self.resolver = resolver
        queue = tiles
        self.total = total ?? tiles.count
        completed = 0
        failures = []
        currentName = ""
        pauseRequested = false
        phase = .running
        runLoop()
    }

    /// Pause after the in-flight image, or resume a paused run.
    func togglePause() {
        switch phase {
        case .running: requestPause()
        case .paused:  resume()
        default: break
        }
    }

    /// Reflect "paused" immediately. The in-flight image finishes and is kept;
    /// the loop then halts before starting the next one (see runLoop).
    private func requestPause() {
        guard phase == .running else { return }
        pauseRequested = true
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        pauseRequested = false
        phase = .running
        // Restart the loop only if it actually halted; if the in-flight image is
        // still running, it will simply keep going now that pauseRequested is clear.
        if task == nil { runLoop() }
    }

    /// Abandon the run; tiles not yet generated keep their placeholder.
    func cancel() {
        task?.cancel()
        task = nil
        queue = []
        pendingJobs = []
        phase = .idle
    }

    /// Clear a finished/idle run so the next start begins fresh.
    func reset() {
        guard !isActive else { return }
        phase = .idle
        pendingJobs = []
        completed = 0
        total = 0
        currentName = ""
        failures = []
    }

    /// Leaving the app pauses an in-progress run; returning resumes it. Keeps
    /// "Continue in Background" predictable: it runs while Blaster is open and
    /// picks up where it left off when you come back.
    func appMovedToBackground() {
        if phase == .running {
            requestPause()
            autoPaused = true
        }
    }

    func appBecameActive() {
        if phase == .paused, autoPaused {
            autoPaused = false
            resume()
        }
    }

    private func existingArt(of style: TileStyle, for tile: TileModel) -> [ImageSetID: UIImage] {
        guard let resolver else { return [:] }
        return SceneImageBatch.existingArt(of: style, for: tile, resolver: resolver)
    }

    private func missingVariants(of style: TileStyle, for tile: TileModel) -> [ImageSetID] {
        guard let resolver else { return [] }
        return SceneImageBatch.missingVariants(of: style, for: tile, resolver: resolver)
    }

    private func runLoop() {
        task = Task { [weak self] in
            guard let self else { return }
            while !self.queue.isEmpty {
                if self.pauseRequested { self.phase = .paused; self.task = nil; return }
                if Task.isCancelled { return }

                let tile = self.queue.removeFirst()
                self.currentName = tile.displayName.isEmpty ? tile.value : tile.displayName

                let images: [ImageSetID: UIImage]
                var failed: Bool
                switch self.mode {
                case .newArt:
                    // One call for every style, rather than a per-set loop:
                    // variants in a style have to share a single generated
                    // figure, and a per-set loop produced a different picture
                    // for each.
                    let plan = self.artPlan
                    images = await TileImageGenerator.generate(
                        displayName: tile.displayName, wordClass: tile.wordClass,
                        plan: plan, apiKey: self.apiKey)
                    failed = images.count < ArtPlan.expectedSets(plan).count
                case .fillVariants(let style):
                    let missing = self.missingVariants(of: style, for: tile)
                    images = await TileImageGenerator.fillMissingVariants(
                        style: style, existing: self.existingArt(of: style, for: tile),
                        apiKey: self.apiKey)
                    failed = images.count < missing.count
                case .completeStyle(let style):
                    // Shared with the per-tile button in `TilePhotoSection`, so
                    // "finish this style" cannot mean two different things
                    // depending on which surface asked.
                    guard let resolver = self.resolver else {
                        // No resolver means the run was never configured; count
                        // the word as failed rather than silently as done.
                        self.failures.append(self.currentName)
                        self.completed += 1
                        continue
                    }
                    let work = TileArtCompletion.work(completing: style, for: tile,
                                                      resolver: resolver)
                    images = await TileArtCompletion.generate(
                        completing: style, for: tile, apiKey: self.apiKey, resolver: resolver)
                    failed = images.count < work.missing.count
                }
                if Task.isCancelled { return }

                for (set, image) in images {
                    if let context = self.context, let resolver = self.resolver,
                       TilePhotoCommit.applyVariant(image, to: tile, imageSet: set,
                                                    context: context, resolver: resolver) != nil {
                        failed = true
                    }
                }
                if failed { self.failures.append(self.currentName) }
                self.completed += 1

                // Style finished and another is waiting: refill and keep going,
                // rather than ending a run the caregiver would have to restart.
                if self.queue.isEmpty, !self.pendingJobs.isEmpty {
                    let next = self.pendingJobs.removeFirst()
                    self.mode = .completeStyle(next.style)
                    self.queue = next.tiles
                }
            }
            self.task = nil
            if !Task.isCancelled { self.phase = .finished }
        }
    }
}

struct SceneImageBatchSheet: View {
    let controller: SceneImageBatchController

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                if controller.phase == .finished {
                    summary
                } else {
                    progress
                }
                Spacer()
                actions
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(controller.isActive)
        }
    }

    /// Named for what the run is doing — "New Word Art" over a run that is
    /// recoloring existing pictures would misdescribe both the work and the bill.
    private var title: String {
        switch controller.mode {
        case .newArt: "New Word Art"
        case .fillVariants(let style): "Complete \(style.base.styleName)"
        case .completeStyle(let style): "Finish \(style.base.styleName)"
        }
    }

    private var progress: some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("\(controller.completed) of \(controller.total)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(controller.mode == .newArt ? "images created" : "words completed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(controller.completed), total: Double(max(controller.total, 1)))
                .progressViewStyle(.linear)
                .padding(.horizontal, 24)
            if controller.phase == .paused {
                Text("Paused · \(controller.remaining) still to go")
                    .font(.headline)
                    .foregroundStyle(.orange)
            } else if !controller.currentName.isEmpty {
                Text("Now creating: \(controller.currentName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Each image takes a few seconds.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var summary: some View {
        if controller.total == 0 {
            // Nothing was queued — show a neutral state rather than "0 of 0".
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green)
                Text("No new words needed art.").font(.headline)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: controller.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(controller.failures.isEmpty ? .green : .orange)
                Text("Created art for \(controller.total - controller.failures.count) of \(controller.total) word\(controller.total == 1 ? "" : "s").")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if !controller.failures.isEmpty {
                    Text("Couldn't generate: \(controller.failures.joined(separator: ", ")). Try those from each tile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if controller.phase == .finished {
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        } else if controller.phase == .paused {
            VStack(spacing: 12) {
                Button("Resume") {
                    controller.resume()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Cancel", role: .destructive) {
                    controller.cancel()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Text("Resume picks up where it left off. Cancel keeps the images already created. Both close this screen.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        } else {
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Button("Continue in Background") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Text("Keep creating images while you use Blaster. Leaving the app pauses it; it resumes when you return.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                HStack(spacing: 12) {
                    Button("Pause") {
                        controller.togglePause()
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("Cancel", role: .destructive) {
                        controller.cancel()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                Text("Pause stops after the current image. Cancel keeps the images already created. Both close this screen.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }
}
