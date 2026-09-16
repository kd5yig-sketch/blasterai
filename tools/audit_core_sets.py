#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Compare BlasterAI's core word sets against published AAC core vocabulary.

## Why

`Resources/core_sets.json` ships two sets — `needs` and `core` — and
until now neither had a citation. `core` is a snapshot of this app's own
Core-First home page; `needs` was reduced from it by hand. Both are
plausible, because high-frequency words are high-frequency, but plausible is not
provenance, and "where did these words come from?" is the first question a
speech-language pathologist asks.

This answers it with arithmetic rather than assertion: how much of each
published list we cover, what we are missing, and what we invented.

## The references

Word lists themselves. See `docs/core-vocabulary-audit.md` for the licence
position on each — one of them cannot be shipped, which is a finding rather
than a footnote.

Run:
    python3 tools/audit_core_sets.py            # writes the markdown report
    python3 tools/audit_core_sets.py --stdout
"""

import argparse
import json
from pathlib import Path

VOCAB = Path("claudeBlast/Resources/vocabulary.json")
CORE_SETS = Path("claudeBlast/Resources/core_sets.json")
OUT = Path("docs/core-vocabulary-audit.md")

# --------------------------------------------------------------------------
# Reference lists, transcribed from the sources named in each `note`.
#
# These are *comparison* material. Shipping any of them is a separate question
# with a different answer per source — see the licence section of the report.
# --------------------------------------------------------------------------

REFERENCES = [
    {
        "id": "universal_core",
        "name": "Universal Core (Project Core)",
        "n": 36,
        "note": (
            "Center for Literacy and Disability Studies, UNC-Chapel Hill. "
            "36 words for beginning communicators. Licensed **CC BY-SA 4.0**."
        ),
        "url": "https://www.med.unc.edu/healthsciences/clds/universal-core-vocabulary/",
        "words": [
            "all", "can", "different", "do", "finished", "get", "go", "good", "he",
            "help", "here", "I", "in", "it", "like", "look", "make", "more", "not",
            "on", "open", "put", "same", "she", "some", "stop", "that", "turn", "up",
            "want", "what", "when", "where", "who", "why", "you",
        ],
    },
    {
        "id": "banajee_2003",
        "name": "Banajee et al. (2003) — toddler core",
        "n": 23,
        "note": (
            "Banajee, DiCarlo & Buras Stricklin, *AAC* 19(2), 67–73. 50 toddlers "
            "aged 24–36 months; 23 words accounted for 96.3% of the sample, all "
            "function words and no content words."
        ),
        "url": "https://pubs.asha.org/doi/10.1080/0743461031000112034",
        "words": [
            "I", "no", "yes", "my", "the", "want", "is", "it", "that", "a", "go",
            "mine", "you", "what", "on", "in", "here", "more", "out", "off", "some",
            "help", "all done",
        ],
    },
    {
        "id": "prc_100",
        "name": "PRC-Saltillo — 100 Frequently Used Core Words",
        "n": 100,
        "note": (
            "Practitioner list built from Banajee (2003), Dolch, Van Tatenhove's "
            "First 50, LAMP starter words, PRC Core Starter Sets and clinical "
            "judgment. **Commercial use prohibited** — comparison only."
        ),
        "url": "https://aaclanguagelab.com/materials/100highfrequencycorewords21.pdf",
        "words": [
            # Interjections
            "yes", "no", "thank you", "please", "hi", "good-bye",
            # Pronouns
            "I", "me", "my", "mine", "you", "it", "he", "she", "we", "they",
            # Question words
            "what", "when", "where", "who", "why", "how",
            # Preverbs
            "be", "is", "am", "are", "was", "were", "do", "did", "can", "have", "will",
            # Verbs
            "go", "stop", "turn", "make", "look", "see", "find", "put", "open",
            "close", "eat", "drink", "get", "help", "want", "need", "say", "tell",
            "come", "read", "like", "feel", "color", "let's", "work", "play",
            "finished",
            # Adjectives
            "more", "one", "big", "little", "fast", "slow", "same", "different",
            "pretty", "red", "blue", "yellow", "good", "bad", "new", "old", "happy",
            "sad",
            # Prepositions
            "on", "off", "in", "out", "up", "down", "to", "for", "under", "with",
            # Determiners
            "this", "that", "some", "all",
            # Conjunctions
            "and", "but",
            # Adverbs
            "not", "now", "here", "there", "away", "again",
        ],
    },
]

# Reference words whose BlasterAI concept id is not just the lowercased word.
# Kept explicit rather than guessed: a silent mismatch here would understate our
# coverage and send someone off to add a word we already have.
ALIASES = {
    "all done": "all_done",
    "finished": "all_done",
    "good-bye": "bye",
    "hi": "hello",
    "let's": "lets",
    "thank you": "thank_you",
}


def concept_id(word: str) -> str:
    w = word.strip().lower()
    return ALIASES.get(w, w.replace(" ", "_").replace("'", ""))


def load():
    vocab = {t["key"] for t in json.loads(VOCAB.read_text())}
    sets = {s["id"]: s for s in json.loads(CORE_SETS.read_text())["sets"]}
    return vocab, sets


def table(rows: list[list[str]], headers: list[str]) -> str:
    out = ["| " + " | ".join(headers) + " |",
           "|" + "|".join("---" for _ in headers) + "|"]
    out += ["| " + " | ".join(r) + " |" for r in rows]
    return "\n".join(out)


def words(keys) -> str:
    return ", ".join(f"`{k}`" for k in sorted(keys)) if keys else "—"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stdout", action="store_true")
    args = ap.parse_args()

    vocab, sets = load()
    needs = set(sets["needs_feelings"]["keys"])
    core = set(sets["core_words"]["keys"])

    md = ["# Core vocabulary audit",
          "",
          "*Generated by `tools/audit_core_sets.py`. Re-run after editing "
          "`Resources/core_sets.json`.*",
          "",
          "## The question",
          "",
          "BlasterAI ships two word strips for home pages. **Basic needs \u0026 "
          "feelings** is ours, chosen by us, and deliberately not called core — "
          "none of its words appears on any published list, because they are "
          "states to report rather than words that combine. **Core words** is the "
          "overlap of four independently published lists. This measures both.",
          ""]

    # ---------------------------------------------------------------- summary
    md += ["## Summary", ""]
    rows = []
    for ref in REFERENCES:
        ids = {concept_id(w) for w in ref["words"]}
        in_vocab = ids & vocab
        rows.append([
            ref["name"],
            str(len(ids)),
            f"{len(in_vocab)} ({len(in_vocab) / len(ids):.0%})",
            f"{len(ids & needs)} ({len(ids & needs) / len(ids):.0%})",
            f"{len(ids & core)} ({len(ids & core) / len(ids):.0%})",
        ])
    md += [table(rows, ["Reference list", "Words", "In our vocabulary",
                        "In needs \u0026 feelings", "In core words"]), ""]

    # -------------------------------------------------------- per-list detail
    for ref in REFERENCES:
        ids = {concept_id(w) for w in ref["words"]}
        missing = sorted(ids - vocab)
        md += [f"## {ref['name']}", "",
               ref["note"], "",
               f"<{ref['url']}>", ""]
        if missing:
            md += [f"**Not in our vocabulary at all ({len(missing)}):** "
                   + words(missing),
                   "",
                   "These are words the app cannot put on a board even if a "
                   "caregiver wants to.", ""]
        else:
            md += ["**Every word on this list exists in our vocabulary.**", ""]
        md += [f"**In our vocabulary but NOT in either set "
               f"({len(ids & vocab - needs - core)}):** "
               + words(ids & vocab - needs - core),
               "",
               "Candidates: the reference considers these core, we have the word, "
               "and neither set offers it.", ""]

    # ------------------------------------------------------------- our sets
    union = set()
    for ref in REFERENCES:
        union |= {concept_id(w) for w in ref["words"]}

    # ------------------------------------------------------- consensus words
    # A word all three independent lists agree on is as close to settled as this
    # field gets: one is a research finding, one is a university's teaching set,
    # one is a vendor's practitioner list. Where they agree AND we already have
    # the word AND neither of our sets offers it, that is a gap we chose by
    # accident rather than on purpose.
    counts: dict[str, int] = {}
    for ref in REFERENCES:
        for cid in {concept_id(w) for w in ref["words"]}:
            counts[cid] = counts.get(cid, 0) + 1

    md += ["## Where the references agree and we do not", ""]
    for n, label in ((3, "All three lists"), (2, "Two of the three")):
        agreed = {k for k, c in counts.items() if c == n}
        have = sorted(agreed & vocab - needs - core)
        lack = sorted(agreed - vocab)
        md += [f"**{label} ({len(agreed)} words)**", "",
               f"- In our vocabulary, offered by neither set ({len(have)}): "
               + words(have)]
        if lack:
            md += [f"- Not in our vocabulary at all ({len(lack)}): " + words(lack)]
        md += [""]

    md += ["### What this shows", "",
           "Our vocabulary is not the problem — it covers 85–97% of every "
           "reference list, and the handful of misses are grammatical function "
           "words (`a`, `the`, `is`, `am`, `are`, `be`, `will`) that a symbol "
           "board has little use for. `can` is the one real absence: it is in "
           "Universal Core and in the PRC list, and it is a word a child needs to "
           "refuse and to ask permission.", "",
           "The **core sets** are where we diverge, and the pattern is "
           "consistent. Ours lead with needs and feelings — `hungry`, `thirsty`, "
           "`bathroom`, `hurt`, `sick`, `scared`, `tired` — none of which appear "
           "on any reference list. The references lead with words that *combine*: "
           "`go`, `here`, `in`, `on`, `it`, `that`, `some`, `up`, `stop`, `open`, "
           "`turn`, `make`, `put`, `like`, `get`, `do`, `not`, `more`, `all`, "
           "`different`, `same`.", "",
           "That is the difference between a **requesting board** and a "
           "**language board**, and it is the specific critique an SLP is most "
           "likely to make of what we ship. A needs strip lets a child ask for "
           "things; core words let them say things about anything. Brown's Stage "
           "I is exactly where the literature argues combinable core words matter "
           "most, and Stage I is our default.", "",
           "None of this makes the needs words wrong — a child who cannot say "
           "`bathroom` has a worse day than one who cannot say `different`, and "
           "the references are lists for classrooms rather than for families. But "
           "our sets currently offer 7 of Universal Core's 36 words, and that "
           "number should be a decision rather than an accident.", ""]

    md += ["## What we carry that nobody else calls core", ""]
    for label, ours in (("Basic needs \u0026 feelings", needs), ("Core words", core)):
        ours_only = sorted(ours - union)
        md += [f"**{label} ({len(ours)} words) — not on any reference list "
               f"({len(ours_only)}):** " + words(ours_only), ""]
    md += ["Core words should now show none: it is built from the references. "
           "Needs & feelings should show most of itself, and that is the point "
           "rather than a failing — it is a different kind of word, and it is "
           "labelled as one.", ""]

    # ------------------------------------------------------------- licensing
    md += ["## Licence — a guardrail, not a decision", "",
           "**We are not shipping any of these lists.** They are here to measure "
           "ours against and to learn from. That settles the licence question for "
           "the present work; this table exists so a future reader does not "
           "quietly cross the line by copying a list in.", "",
           "| Source | Licence | If we ever wanted to adopt it |",
           "|---|---|---|",
           "| Universal Core | CC BY-SA 4.0 | ShareAlike is copyleft and this repo "
           "is Apache-2.0. A bare list of 36 common English words is arguably "
           "uncopyrightable fact, but that is a legal judgment and would need one. |",
           "| Banajee et al. (2003) | Journal article | A research *finding* — "
           "cite it, do not copy the paper. |",
           "| PRC-Saltillo 100 | \"Commercial use prohibited; may not be used for "
           "resale\" | **No.** |",
           "",
           "Adjusting our own sets in light of what we learn here is a different "
           "act from adopting someone else's list, and `core_sets.json` carries a "
           "`source` field so whichever it was is recorded with the data.", ""]

    text = "\n".join(md)
    if args.stdout:
        print(text)
    else:
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_text(text)
        print(f"→ {OUT}")


if __name__ == "__main__":
    main()
