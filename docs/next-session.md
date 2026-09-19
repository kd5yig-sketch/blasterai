<!-- SPDX-License-Identifier: Apache-2.0 -->
# Handoff — the App Store Connect Distribution tab

Written 2026-09-18 at the close of session 6. Read this first; it is the whole
of what is outstanding.

## Where things stand

`main` @ session 6 close. **Gate 1 is closed** — CloudKit is promoted and
three-way Production sync is verified on real devices: a word added on one
device arrived on two others, its art followed, and a device on a different
image set fell back to the art that existed rather than showing a placeholder.

**TestFlight build 0.9.0 (3) is up**, uploaded with the App Store Connect method
so it is eligible for external testing. Mark's wife is being added as an external
tester deliberately, to start Beta App Review early — the first review is the
slow one and its latency cannot be compressed later.

Releases are scripted: `tools/preflight_release.py` (ten checks) then
`tools/release.py` (bump, archive, export, upload). The next `--bump build` lands
on 4.

## What this session is for

The **Distribution tab**, and the App Store metadata that goes with it.

### 1. Privacy — review before filling anything in

`blasterai.app/privacy` exists and is live, and the URL can go in the TestFlight
field immediately. **The content has not been re-read since the app gained AI
features**, and that is the first job.

The question to answer: does it say plainly that adding an OpenAI key sends the
selected words to OpenAI, under the user's own account and OpenAI's terms?

`docs/openai-tos-memo-2026-07-21.md` establishes the legal shape — under BYOK the
*user* is OpenAI's Customer, owns the outputs, and no BlasterAI server is in the
path. The privacy policy should say the same thing in a parent's words.

### 2. Privacy nutrition labels

Answer them against `PrivacyInfo.xcprivacy` rather than from memory. The expected
answer is **Data Not Collected**, and it should be checked rather than assumed —
a mismatch between the manifest and the questionnaire is a rejection.

### 3. App Review Information → Notes

The same text as the beta review notes:

    python3 tools/make_tester_notes.py     # writes build/review-notes.txt

Apple is asked nothing in either. An honest, superficial walk, and the facts that
stop a keyless app reading as a broken one.

### 4. Licence

**Apple's standard EULA.** Settled 2026-09-18:

- Apache-2.0 does not conflict with it. Unlike GPL, Apache has no clause
  forbidding further restrictions on redistribution — §4 permits distribution
  under different terms provided attribution and `NOTICE` survive. Shipping the
  binary under Apple's EULA takes nothing from anyone's rights to the source.
- No custom terms are needed for the AI, because BlasterAI does not provide an
  AI service. Under BYOK the user contracts with OpenAI directly.

A custom EULA would add legal surface and a review step for no benefit on an app
with no accounts, no backend and no data collection.

### 5. Screenshots

iPad, iPhone and Mac, via the existing TileScript `shots_*.yaml` capture path.
Carried from S5.5 and never started.

### 6. Description, keywords, category

Category is **Education**, never Kids — the Kids Category's parental-gate rule
forbids leaving the app without a gate, which would break the in-flow "Get a
key" link BYOK onboarding depends on.

For the description, the order of the pitch in `docs/final-countdown-plan.md`
applies: lead with what it does for a child. Do not lead with coverage, patterns,
the usage report, OBF/OBZ, packs, Fitzgerald colours or Brown's Stages.

## Also outstanding, smaller

- **The keyless walk on a retail build.** The iPhone is genuinely keyless and
  nobody has walked it. It is the configuration a reviewer lands in and the one
  most families will run. `docs/beta-review-notes.md` §2 is the script.
- **Patient mode.** Everyone is told to choose Caregiver, so the locked-down
  state a child's device actually runs in is untested by anyone who was not
  expecting it to hold. Kurt is to do this pass, standing in for Brandi.
- **Kurt's App Store Connect account**, whenever internal testing widens.
- **The SLP invite emails.** A skeleton is in `docs/beta-review-notes.md` §3 —
  the placeholder-board framing and the attribution offer are the parts worth
  keeping. Everything around them should be written per person, after approval.
  A form letter to someone being asked to do design work undercuts the ask.

## Carried from S5.5, still not started

`docs/positioning-2026-09.md`, the claims refresh (`docs/claims-audit-2026-09.md`),
and the onboarding copy. None of it blocks testing.
