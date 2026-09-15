// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AuthoringLog.swift
//  claudeBlast
//
//  Records how a scene or page came to exist — and, when AI made it, the words
//  the caregiver used to ask for it.
//
//  ## Why the prompt is worth keeping
//
//  It is the only record of *why* a board looks the way it does. It lets a
//  caregiver re-run a brief instead of reconstructing it from memory, gives a
//  therapist receiving a board the question it was an answer to, and turns a
//  scene's refines into a changelog in the caregiver's own words.
//
//  ## Why it is kept HERE
//
//  On `MetricEvent`, which is device-local — see the note on `MetricEvent.detail`.
//  A prompt is the likeliest place a child's name, age, diagnosis or school ends
//  up, so the storage location has to make "never synced, never shared" the
//  default rather than a rule someone must remember on every future export.
//
//  Nothing in here is required for the app to work. A failure to log must never
//  fail the authoring action it describes, so every call site is fire-and-forget.
//

import Foundation
import SwiftData

enum AuthoringLog {
    /// `MetricEvent.subjectType` values this log writes.
    enum Subject: String {
        case scene
        case page
    }

    /// Record that something was created. `detail` is the prompt when AI wrote
    /// it, and empty when the caregiver did — the distinction the Activity tab
    /// draws between "Generated" and "Created".
    static func created(_ subject: Subject, key: String, prompt: String = "",
                        in context: ModelContext) {
        write(subject, key: key, eventType: .created, detail: prompt, in: context)
    }

    /// Record an AI refinement, keeping the instruction that drove it.
    static func refined(_ subject: Subject, key: String, instruction: String,
                        in context: ModelContext) {
        write(subject, key: key, eventType: .refined, detail: instruction, in: context)
    }

    private static func write(_ subject: Subject, key: String, eventType: MetricType,
                              detail: String, in context: ModelContext) {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        context.insert(MetricEvent(subjectType: subject.rawValue, subjectKey: key,
                                   eventType: eventType, detail: trimmed))
    }
}
