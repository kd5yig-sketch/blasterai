// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AuthoringLogTests.swift
//  claudeBlastTests
//
//  The authoring history: how a scene or page was made, and the prompt that
//  asked for it.
//

import Testing
import Foundation
import SwiftData
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct AuthoringLogTests {
    private func makeContext() throws -> ModelContext { TestStore.freshContext() }

    private func events(_ ctx: ModelContext) throws -> [MetricEvent] {
        try ctx.fetch(FetchDescriptor<MetricEvent>())
    }

    @Test func aGeneratedSceneKeepsItsPrompt() throws {
        let ctx = try makeContext()
        AuthoringLog.created(.scene, key: "abc/dentist",
                             prompt: "a first visit to the dentist", in: ctx)
        try? ctx.save()

        let event = try #require(try events(ctx).first)
        #expect(event.subjectType == "scene")
        #expect(event.subjectKey == "abc/dentist")
        #expect(event.eventType == .created)
        #expect(event.detail == "a first visit to the dentist")
        #expect(event.isAuthoringRecord)
    }

    @Test func aHandBuiltSceneRecordsTheEventWithNoPrompt() throws {
        let ctx = try makeContext()
        AuthoringLog.created(.page, key: "snacks", in: ctx)
        try? ctx.save()

        let event = try #require(try events(ctx).first)
        #expect(event.detail.isEmpty)
        // Drives the Created / Generated distinction in the Activity tab.
        #expect(!event.isAuthoringRecord)
    }

    @Test func refinementsRecordTheirInstruction() throws {
        let ctx = try makeContext()
        AuthoringLog.refined(.scene, key: "abc/farm",
                             instruction: "  add a fish pond  ", in: ctx)
        try? ctx.save()

        let event = try #require(try events(ctx).first)
        #expect(event.eventType == .refined)
        #expect(event.detail == "add a fish pond")     // trimmed
    }

    @Test func anEmptySubjectKeyIsNotLogged() throws {
        let ctx = try makeContext()
        // A scene that failed to build has no identity to hang history on; a row
        // keyed to nothing would be unreadable in the Activity tab forever.
        AuthoringLog.created(.scene, key: "", prompt: "something", in: ctx)
        try? ctx.save()
        #expect(try events(ctx).isEmpty)
    }

    // MARK: - Compaction must not eat the text

    /// Two refines of ONE scene share subject type, subject key and event type —
    /// every field the fold key used to be built from. Without `detail` in the
    /// key they would merge into a single `count: 2` row and both instructions,
    /// the only reason those rows exist, would be gone.
    @Test func distinctPromptsNeverFoldTogether() throws {
        let a = MetricEvent(subjectType: "scene", subjectKey: "abc/farm",
                            eventType: .refined, detail: "add a fish pond")
        let b = MetricEvent(subjectType: "scene", subjectKey: "abc/farm",
                            eventType: .refined, detail: "remove the tractor")
        #expect(MetricCompactor.foldKey(for: a) != MetricCompactor.foldKey(for: b))
    }

    @Test func identicalPromptsStillFold() throws {
        // Asking twice for the same thing IS a count, so these may merge.
        let a = MetricEvent(subjectType: "scene", subjectKey: "abc/farm",
                            eventType: .refined, detail: "add a fish pond")
        let b = MetricEvent(subjectType: "scene", subjectKey: "abc/farm",
                            eventType: .refined, detail: "add a fish pond")
        #expect(MetricCompactor.foldKey(for: a) == MetricCompactor.foldKey(for: b))
    }

    @Test func promptsDoNotDisturbOrdinaryMetricFolding() throws {
        // Every existing event carries no detail, so the added key component is
        // constant for them and folding behaves exactly as it did.
        let a = MetricEvent(subjectType: "tile", subjectKey: "eat", eventType: .selected)
        let b = MetricEvent(subjectType: "tile", subjectKey: "eat", eventType: .selected)
        #expect(MetricCompactor.foldKey(for: a) == MetricCompactor.foldKey(for: b))
    }
}
}
