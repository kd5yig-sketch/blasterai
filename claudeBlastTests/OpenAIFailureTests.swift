// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OpenAIFailureTests.swift
//  claudeBlastTests
//
//  Four refusals, two status codes, and the bodies that tell them apart.
//

import Testing
import Foundation
@testable import claudeBlast

/// Not nested in `SerialTests`: the classifier touches no SwiftData container,
/// no network and no clock, so it needs no serialization.
struct OpenAIFailureTests {

    // MARK: - Fixtures
    //
    // Both bodies below are verbatim from a live scoped, capped OpenAI project
    // on 2026-09-16 — captured in the debugger, not copied from documentation.
    // They are the entire reason this classifier matches the strings it does,
    // so they are pasted whole rather than reduced to the two fields we read.

    /// 403, model withheld from the project's allowlist.
    static let modelNotFound = """
    {
      "error": {
        "message": "Project `proj_p4FOChqbj0yR48zLzVTObGw9` does not have access to model `gpt-image-1`",
        "type": "invalid_request_error",
        "param": null,
        "code": "model_not_found"
      }
    }
    """

    /// 429, project spend limit reached.
    static let spendLimit = """
    {
      "error": {
        "message": "Your project has reached its configured enforced spend limit. Update your limit at https://platform.openai.com/settings/proj_p4FOChqbj0yR48zLzVTObGw9/limits.",
        "type": "insufficient_quota",
        "param": null,
        "code": "project_spend_limit_exceeded"
      }
    }
    """

    /// 429, ordinary throughput limiting. Must not be confused with the above.
    static let rateLimit = """
    {
      "error": {
        "message": "Rate limit reached for gpt-4o-mini in organization org-x on requests per min (RPM): Limit 3, Used 3, Requested 1.",
        "type": "requests",
        "param": null,
        "code": "rate_limit_exceeded"
      }
    }
    """

    /// 401, the classic dead key.
    static let invalidKey = """
    {
      "error": {
        "message": "Incorrect API key provided: sk-abc***xyz.",
        "type": "invalid_request_error",
        "param": null,
        "code": "invalid_api_key"
      }
    }
    """

    private func http(_ status: Int, _ body: String) -> Error {
        OpenAIError.httpError(statusCode: status, body: body)
    }

    // MARK: - The four measured cases

    @Test("A revoked key is a rejection")
    func invalidKeyIsRejection() {
        #expect(OpenAIFailure.classify(http(401, Self.invalidKey)) == .rejected)
    }

    /// The case that must never latch. A model withheld from the project says
    /// nothing about the key, and allowlist changes propagate with a lag — so a
    /// remembered verdict here keeps a newly-granted key broken until relaunch.
    @Test("A withheld model is a capability failure, not a dead key")
    func modelNotFoundIsCapability() {
        #expect(OpenAIFailure.classify(http(403, Self.modelNotFound))
                == .capability(model: "gpt-image-1"))
    }

    /// The one that was failing silently. A 429 did not latch, so a device whose
    /// money ran out kept trying and kept producing nothing, with no fallback
    /// and nothing said to anyone.
    @Test("A spend limit is exhaustion, not a rejection")
    func spendLimitIsExhaustion() {
        #expect(OpenAIFailure.classify(http(429, Self.spendLimit)) == .exhausted)
    }

    /// The reason exhaustion is matched on `type` and not on
    /// `project_spend_limit_exceeded`: ordinary rate limiting is also a 429, and
    /// condemning a working key over a burst is the failure the original
    /// `isKeyRejection` comment was written to avoid.
    @Test("A rate limit is transient")
    func rateLimitIsTransient() {
        #expect(OpenAIFailure.classify(http(429, Self.rateLimit)) == .transient)
    }

    // MARK: - Why `type` and not `code`

    /// `insufficient_quota` is equally what OpenAI returns when an ordinary BYOK
    /// account exhausts its own credit — no project, no spend limit, no
    /// `project_spend_limit_exceeded` code. Matching the narrower code would
    /// have left every family whose $5 ran out in the silent-failure state this
    /// change exists to remove.
    @Test("An account out of credit classifies the same as a capped project")
    func accountQuotaIsAlsoExhaustion() {
        let body = """
        {"error":{"message":"You exceeded your current quota, please check your plan and billing details.",
        "type":"insufficient_quota","param":null,"code":"insufficient_quota"}}
        """
        #expect(OpenAIFailure.classify(http(429, body)) == .exhausted)
    }

    // MARK: - The asymmetric defaults
    //
    // Both preserve the behaviour that existed before this type, which is what
    // makes the change purely additive precision rather than a re-tuning.

    @Test("An unrecognised 403 still condemns the key", arguments: [
        "", "not json at all", #"{"error":{"type":"something_new"}}"#,
    ])
    func unknown403Latches(_ body: String) {
        #expect(OpenAIFailure.classify(http(403, body)) == .rejected)
    }

    @Test("An unrecognised 429 still does not condemn the key", arguments: [
        "", "not json at all", #"{"error":{"type":"something_new"}}"#,
    ])
    func unknown429DoesNotLatch(_ body: String) {
        #expect(OpenAIFailure.classify(http(429, body)) == .transient)
    }

    // MARK: - Everything else is still a bad day, not a bad key

    @Test("Server errors are transient", arguments: [500, 502, 503, 504])
    func serverErrorsAreTransient(_ status: Int) {
        #expect(OpenAIFailure.classify(http(status, "")) == .transient)
    }

    @Test("Network failures are transient")
    func networkFailuresAreTransient() {
        #expect(OpenAIFailure.classify(URLError(.timedOut)) == .transient)
        #expect(OpenAIFailure.classify(URLError(.notConnectedToInternet)) == .transient)
    }

    @Test("A decoding failure is transient")
    func decodingFailureIsTransient() {
        #expect(OpenAIFailure.classify(OpenAIError.decodingError("nonsense")) == .transient)
    }

    // MARK: - Naming the model

    /// The model name is scraped out of prose, so it is worth pinning that the
    /// project id is not mistaken for it — both arrive backticked in the same
    /// sentence, and the project id is the one that looks like an identifier.
    @Test("The project id is never mistaken for the model name")
    func projectIdIsNotTheModel() {
        guard case .capability(let model) =
                OpenAIFailure.classify(http(403, Self.modelNotFound)) else {
            Issue.record("expected a capability failure")
            return
        }
        #expect(model == "gpt-image-1")
    }

    /// A degraded message beats a wrong one: if OpenAI rewords this, the caller
    /// says "a model" instead of naming the wrong thing.
    @Test("An unparseable message yields no model name rather than a guess")
    func unnamedModelIsNil() {
        let body = #"{"error":{"type":"invalid_request_error","code":"model_not_found","message":"no access"}}"#
        #expect(OpenAIFailure.classify(http(403, body)) == .capability(model: nil))
    }

    // MARK: - The error has to arrive as an httpError

    /// The regression this pins, found on device 2026-09-16.
    ///
    /// `TileImageGenerator.send` used to pull OpenAI's `message` out of the body
    /// and throw `.apiError(message)` — a case carrying no status and no
    /// structured fields. Classification only matches `.httpError`, so every art
    /// failure came back `.transient`, and a spend-limited key told the caregiver
    /// "Couldn't reach OpenAI just now. Check the connection" on a verified 429.
    ///
    /// The lesson generalises past the art path: any future service that
    /// "helpfully" unwraps a body before throwing blinds this classifier. That
    /// cannot be asserted from here, so this test states the trap instead.
    @Test("An apiError carries nothing to classify — services must throw httpError")
    func apiErrorCannotBeClassified() {
        #expect(OpenAIFailure.classify(OpenAIError.apiError("anything at all")) == .transient)
    }

    /// The same refusal reaching the classifier intact, which is the whole fix.
    @Test("An art-path spend limit classifies once the raw body survives")
    func artPathSpendLimitIsExhaustion() {
        #expect(OpenAIFailure.classify(http(429, Self.spendLimit)) == .exhausted)
        #expect(OpenAIFailure.caregiverMessage(for: http(429, Self.spendLimit))
                    .contains("out of credit"))
    }

    // MARK: - Refusals about the request, not the key

    /// Why keeping the raw body costs nothing: a content-policy refusal still
    /// reaches the caregiver in OpenAI's own words, which name what was objected
    /// to — something no paraphrase of ours could reconstruct.
    @Test("A content-policy refusal passes OpenAI's message through")
    func contentPolicyKeepsTheirWording() {
        let body = """
        {"error":{"message":"Your request was rejected as a result of our safety system.",
        "type":"invalid_request_error","param":null,"code":"content_policy_violation"}}
        """
        #expect(OpenAIFailure.classify(http(400, body))
                == .requestRefused(message: "Your request was rejected as a result of our safety system."))
    }

    /// A refusal with nothing to say is not worth inventing words for.
    @Test("A 400 with no message stays transient")
    func emptyBadRequestIsTransient() {
        #expect(OpenAIFailure.classify(http(400, "")) == .transient)
    }

    /// Every case must produce something a caregiver can read — a debug-shaped
    /// string here is how `HTTP 429: {"error"…}` used to reach a parent.
    @Test("Every classification has caregiver-facing copy")
    func everyCaseHasCopy() {
        let all: [OpenAIFailure] = [
            .rejected, .exhausted, .capability(model: "gpt-image-1"),
            .capability(model: nil), .requestRefused(message: "no"), .transient,
        ]
        for f in all {
            #expect(!f.caregiverMessage.isEmpty)
            #expect(!f.caregiverMessage.contains("HTTP "))
            #expect(!f.caregiverMessage.contains("{"))
        }
    }
}
