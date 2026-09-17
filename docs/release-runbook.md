# Release runbook

How a TestFlight build gets made. Written so the next one is a checklist rather
than a memory, and so someone who is not Mark can produce one.

**Status:** the preflight is automated. Bumping, archiving, exporting and
uploading are still manual — see *Not yet scripted* at the end for what is
planned and why it has not been written yet.

---

## 0. Before anything: is CloudKit promoted?

**A TestFlight build always uses the Production CloudKit environment.** Not the
Development one, whatever the scheme says — distribution builds get Production,
and that is the whole of gate 1.

Production currently has **no schema at all** (session 1 deferred phases 4–5), so
a build uploaded before promotion installs and runs but syncs nothing. If that
is not yet done, stop here and run `docs/cloudkit-promotion-runbook.md` first.

Promotion is irreversible in one direction: a Production schema is additive-only
forever. After it, a field can be added but never removed.

---

## 1. Preflight

    python3 tools/preflight_release.py

Refuses rather than warns, and reports every problem in one run rather than one
per round trip — each of these checks takes minutes.

| Check | Why it is there |
|---|---|
| Working tree clean, on `main` | An archive you cannot trace to a commit is not a release |
| Versions readable | They live in `project.pbxproj`, duplicated per configuration |
| Shared scheme, tracked, archives Release | Without it, only a machine that has run Xcode can build |
| Scheme carries no environment variables | The dev scheme holds a live `OPENAI_API_KEY`; a tracked one would leak it |
| **Gates 8 and 9** | `languageRaw`/`brownsStageRaw` present, `birthday` gone — both become impossible to change after promotion |
| Privacy manifest, export compliance | Submission requires the first; without the second every upload asks |
| Tile-set drift, model list | The existing audits, so preflight is one command and not four |
| **Debug *and Release* build** | Release stopped compiling on 2026-09-17 and nothing noticed |
| Full test suite, with a count | A filter matching nothing still prints `TEST SUCCEEDED` |

`--fast` skips the suite; everything else still runs.

### The Release check earns its place

On 2026-09-17 the app did not compile in Release. Three `@State` members were
inside `#if DEBUG` while two tabs used them unguarded. Nothing in the normal loop
touches that configuration — `xcodebuild build` and `test` both default to Debug
— so the first thing that would have failed was the archive for build 1.

---

## 2. Schemes

Two, and the split matters.

- **`claudeBlast`** — development. Holds `OPENAI_API_KEY` as an environment
  variable, which is why it is in `.gitignore` by name and must stay there.
- **`claudeBlastRetail`** — shipping. Every action builds **Release**, so running
  it on a device exercises what ships: no provider picker, no Mock, no
  DEBUG-only surfaces. Tracked in git. This is what the release builds.

Running the retail scheme on a device is the only way to see the RELEASE-only
behaviour before an archive exists.

---

## 3. Version and build number

Both live in `claudeBlast.xcodeproj/project.pbxproj`, **duplicated across the
Debug and Release configurations** of each target:

    MARKETING_VERSION = 0.9.0;          # the version testers see
    CURRENT_PROJECT_VERSION = 1;        # the build number

Rules App Store Connect enforces:

- A build number may never be reused for a given version, even for a build that
  was rejected or deleted. Always increment.
- The marketing version may repeat across builds; the pair must be unique.

Bump the **Release** pair of the app target. Missing that is the failure mode,
because a Debug-only bump looks right in Xcode and ships the old number.

---

## 4. Archive, export, upload

Currently manual, in Xcode: Product → Archive with the `claudeBlastRetail`
scheme, then Distribute App → App Store Connect → Upload.

The scripted equivalent, once written:

    xcodebuild -scheme claudeBlastRetail -configuration Release \
      -archivePath build/claudeBlast.xcarchive archive

    xcodebuild -exportArchive -archivePath build/claudeBlast.xcarchive \
      -exportOptionsPlist tools/ExportOptions-appstore.plist \
      -exportPath build/export

    xcrun altool --upload-app -f build/export/claudeBlast.ipa -t ios \
      --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

**Confirm the upload tool against the installed Xcode before relying on this.**
Apple has moved that surface more than once, and per `feedback_tool_lifetime` a
runbook that names a command should name one that currently works.

**The App Store Connect API key is a secret.** The `.p8` goes in
`~/.appstoreconnect/private_keys/`, never in the repo — same discipline as the
OpenAI keys, and for the same reason: a key in git history is a key you cannot
take back.

---

## 5. What no script can do

These are in App Store Connect, in a browser, and they are part of the loop:

- **What to Test** — the tester-facing notes for this build. Tell people what
  changed and what to look at, not what was refactored.
- **Tester group** — internal testers need App Store Connect accounts, which is
  why round 1 is Mark and Kurt and needs no Beta App Review. External testers
  do need review; see the external-invite prerequisites in
  `docs/final-countdown-plan.md`.
- **Export compliance** — answered from `ITSAppUsesNonExemptEncryption` in
  `Info.plist`, which is `false` and stays true: the gifted-key format uses a
  SHA-256 keystream, and a hash is not encryption.
- **Gifted evaluator keys** — before the first external invite, not before
  round 1. See `docs/gifted-keys.md`.

---

## 6. After the build is up

- Install from TestFlight on iPad, iPhone and Mac.
- Confirm **three-way Production CloudKit sync** between them. This is the thing
  build 1 exists to prove; everything else has already been proven in the
  simulator.
- Check the Activity tab reports usage and cost as expected on a real device.

---

## Not yet scripted, and why

The preflight was written first because it is the part that pays before a build
exists: it is independent of CloudKit, it catches problems now, and it encodes
the Release break that had already happened.

Bump, archive, export and upload are deliberately left for the session that
produces build 1, so every line is exercised the day it is written rather than
sitting unverified in git. The one step that genuinely cannot be tested before
promotion is the upload, because a TestFlight build with no Production schema
behind it is not a meaningful test of anything.
