#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""The same tiles in a different order must produce the same sentence.

    Usage:
        export OPENAI_API_KEY=sk-...
        python3 tools/check_prompt_order.py                 # the shipping prompt
        python3 tools/check_prompt_order.py --quiet          # exit code only
        python3 tools/check_prompt_order.py --prompt old.json  # compare a variant

Exits non-zero if any selection produces more than one distinct sentence across
orderings.

WHY
---
`CacheKeyPolicy.key` is deliberately order-independent: it sorts and dedupes, so
two orders of the same tiles share one cache entry. The prompt, meanwhile, passes
tiles in tap order — `SentencePromptBuilder.formatUserPrompt` preserves it — and
until 2026-09 nothing told the model whether that order meant anything.

So the model guessed, and guessed differently per phrasing: "dad, i, thirsty"
became "Dad, I am thirsty." while "hungry, i, dad" became "I am hungry, Dad."
Worse, the cache then froze whichever order was generated first, making the
inconsistency invisible on every later tap of the same words.

Reported from the Activity Log on 2026-09-17. Measured here at **1 of 4**
selections consistent before the rule was added, and 4 of 4 after.

The fix was one system-prompt rule declaring tap order incidental and fixing the
vocative at the start of the sentence, not sorting the tiles — sorting throws the
information away rather than deciding what it means.

This is a live-model check, not a unit test: it costs a few cents and needs a
key, which is why it lives here rather than in the suite. Run it after any change
to `sentence_prompt.json`.
"""

import argparse
import itertools
import json
import os
import subprocess
import sys

PROMPT = "claudeBlast/Resources/sentence_prompt.json"
MODEL = "gpt-4o-mini"

# Stage IV+, because a one-word answer cannot disagree about word order.
STAGE = "building sentences of four or more words, with grammar a young child uses"

# Each case is one selection. A person tile is present in most of them because
# the vocative is where the disagreement showed up — it is the part of the
# sentence that can legitimately sit at either end.
CASES = [
    [("dad", "people"), ("i", "core"), ("thirsty", "feeling")],
    [("hungry", "feeling"), ("i", "core"), ("dad", "people")],
    [("mom", "people"), ("cookie", "food"), ("want", "actions")],
    [("park", "places"), ("go", "actions"), ("sister", "people")],
    [("i", "core"), ("tired", "feeling"), ("mom", "people")],
]

# Orderings tried per case. Four is enough to catch a positional dependency
# without paying for all six permutations of a three-tile selection.
ORDERINGS = 4


def ask(system: str, tiles: list[tuple[str, str]], key: str) -> str:
    """One generation, shaped exactly as `SentencePromptBuilder` shapes it."""
    body = json.dumps({
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": ", ".join(f"{w} ({c})" for w, c in tiles)},
        ],
        "temperature": 0.7,
    })
    # curl rather than urllib: a python.org interpreter ships no CA bundle, and
    # this should not depend on which Python someone happens to have.
    out = subprocess.run(
        ["curl", "-sS", "https://api.openai.com/v1/chat/completions",
         "-H", f"Authorization: Bearer {key}",
         "-H", "Content-Type: application/json", "-d", "@-"],
        input=body, capture_output=True, text=True)
    try:
        payload = json.loads(out.stdout)
    except json.JSONDecodeError:
        sys.exit(f"unreadable response: {out.stdout[:200]} {out.stderr[:200]}")
    if "error" in payload:
        sys.exit(payload["error"].get("message", "OpenAI refused the request"))
    return payload["choices"][0]["message"]["content"].strip()


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Check that tap order does not change the generated sentence.")
    ap.add_argument("--prompt", default=PROMPT,
                    help="prompt JSON to test (default: the shipping one)")
    ap.add_argument("--quiet", action="store_true", help="exit code only")
    args = ap.parse_args()

    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key:
        sys.exit("OPENAI_API_KEY is not set — this check calls the real model.")

    messages = json.load(open(args.prompt))
    system = "\n\n".join(m.replace("{stage}", STAGE) for m in messages)

    inconsistent = 0
    for tiles in CASES:
        answers = {}
        for order in list(itertools.permutations(tiles))[:ORDERINGS]:
            words = ", ".join(w for w, _ in order)
            answers[words] = ask(system, list(order), key)
            if not args.quiet:
                print(f"  {words:<30} → {answers[words]}")
        if len(set(answers.values())) == 1:
            if not args.quiet:
                print("  ✓ consistent\n")
        else:
            inconsistent += 1
            if not args.quiet:
                print("  ✗ DIFFERS across orderings\n")

    if not args.quiet:
        ok = len(CASES) - inconsistent
        print(f"{ok}/{len(CASES)} selections produced one sentence regardless of tap order")
        if inconsistent:
            print("\nThe prompt does not pin word order. See the TILE ORDER rule in")
            print(f"{PROMPT}, and bump `CacheKeyPolicy.promptVersion` with any change")
            print("so entries generated under the old wording are swept.")
    return 1 if inconsistent else 0


if __name__ == "__main__":
    sys.exit(main())
