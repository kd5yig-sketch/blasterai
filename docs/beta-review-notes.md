<!-- SPDX-License-Identifier: Apache-2.0 -->
# Beta review notes & tester instructions

Two audiences, two App Store Connect fields, written differently.

- **Beta App Review Information** — Apple's reviewer. Required before *external*
  testing. Internal testers need none of it.
- **What to Test** — the testers, attached to each build.

Paste the sections below into those fields. Keep this file as the source, so the
next build's notes are an edit rather than a rewrite.

---

## 1. Beta App Review Information

**Sign-in required:** No. The app has no accounts and no backend.

**Contact:** Mark Lucovsky · support@blasterai.app

### Review notes

> BlasterAI is an AAC (augmentative and alternative communication) app for
> non-verbal children. A child touches picture tiles; the app speaks for them.
>
> **No account, no sign-in, no server.** Everything is stored on the device and
> synced through the user's own iCloud. Nothing reaches a server we operate.
>
> **Nothing needs configuring to review it.** First launch loads a complete
> 492-word vocabulary and working boards. Tap a tile and the app speaks.
>
> **AI sentence generation is optional and bring-your-own-key.** A caregiver may
> add their own OpenAI API key so a child's tile selection becomes a spoken
> sentence instead of separate words. It is off by default. Without a key the app
> speaks each word as it is tapped — how a conventional AAC device behaves, and
> how we expect most families to use it. **You do not need a key to review the
> app**, and the onboarding key step offers Skip.
>
> A five-minute walkthrough that needs no key:
>
> 1. At onboarding choose **Caregiver**, then **Skip** at the API key step.
> 2. Tap tiles on the home board — each speaks immediately.
> 3. Tap a tile with a small arrow badge to open another page; the first cell of
>    every page returns home.

> 4. **Touch and hold the Home tile for about half a second** — longer than the
>    taps above, which speak instantly. That opens the caregiver menu; choose
>    **Admin**. Admin is a row of tabs: Now, Profiles, Scenes, Device, Activity.
> 5. **Scenes** → tap the board we ship. It will offer to make you an editable
>    copy and switch to it; accept. The boards we supply are read-only so an app
>    update can never overwrite a caregiver's work.
> 6. In your copy: open a page → **Select Tiles** → tick a few → **Conceal**.
>    Concealed words stay on the board for the caregiver and disappear for the
>    child.
> 7. **Scenes** → touch and hold a board → **Share** → **Printable PDF**. The
>    same board as paper, which is what many classrooms still run on.
> 8. **Device** → **Image Set** → switch styles. Every word is drawn in every
>    style; the whole board changes and nothing goes missing.
> 9. **Activity** → what was said, and which words have never been used.
>
> **Listed under Education, not Kids.** The person who installs, configures and
> maintains the app is an adult caregiver or speech-language pathologist. The
> child is who it is *for*, not who sets it up. Caregiver settings sit behind an
> optional Face ID / PIN gate, and a device can be put in a patient mode that
> keeps a child inside the board.
>
> **Privacy: no data collected.** A child's words and usage stay on the device
> and in the user's own iCloud. https://blasterai.app/privacy
>
> If you would like to exercise the AI path, we can supply a funded API key —
> contact us and we will send one.

---

## 2. What to Test

> Thanks for looking at this. About half an hour, and you can stop anywhere.
>
> At onboarding, choose **Caregiver** as the device role, and **Skip** the API
> key step. Most of this needs no key, and that is the configuration most
> families will run.
>
> ### The child's side
>
> 1. **Tap tiles on the home board.** Each word should speak the instant you
>    touch it — no wait, no spinner.
> 2. **Follow a page link** into another page and back. Home is the first cell of
>    every page, always in the same place — that is deliberate, and we want to
>    know whether it feels obvious or hidden.
>
> ### Getting to the caregiver side
>
> 3. **Touch and hold the Home tile** → caregiver menu → **Admin**. Tell us
>    whether you would have found that on your own.
>
> ### Making a board of your own
>
> 4. **Scenes → New Scene.** Take either route:
>    - a ready-made example, or
>    - **Build from Collections** — tick vocabulary packs and word classes and
>      let it assemble a board.
> 5. Open your new board, open a page, and tap **Select Tiles**. With several
>    ticked, try **Conceal** and **Delete**. Conceal keeps a word on the board for
>    you and hides it from the child; delete removes it. We would like to know
>    whether that distinction is clear without being told.

> 6. Rename a page, and move tiles between pages.
>
> Nothing above needs the guides, but they exist if you want them — and we would
> like to know whether you needed them:
>
> - **blasterai.app/guides/make-your-first-scene**
> - **blasterai.app/guides/pages-and-navigation**
> - **blasterai.app/guides/adding-vocabulary**
>
> ### Taking a board off the device
>
> 7. **Scenes → touch and hold a board → Share.** Try **Printable PDF** — pick a
>    layout and paper size. Plenty of classrooms still run on paper, and a board
>    that cannot be printed is only half a board.

> 8. Same Share sheet, two other destinations worth a look:
>    - **Tile images** — the pictures as ordinary image files, for a worksheet, a
>      label maker, or anything that is not this app.
>    - **Blaster scene** — the board as a file. Text or email it to another
>      device with BlasterAI on it and tapping it there rebuilds the board,
>      artwork included. That is how a therapist hands a board to a family, with
>      no account and nothing in between.
>
> ### Looking at how it is used
>
> 9. **Device → Image Set.** Switch styles. Every word is drawn in every style.
> 10. **Activity.** The log of what was said, and **Coverage** — which of the
>     board's words have and have not been used. Does that screen answer a
>     question you would actually ask about a child?
>
> ### Now add a key
>
> Add an OpenAI key in **Admin → Device**, or open the key file if one was sent
> to you.
>
> First, the tray. Tiles you tap collect along the top. **There is no back
> button — tap a tile in the tray to take it back out.** Beside them are **Play**
> and **Clear**.
>
> 11. **Start deliberately.** Tap three tiles, then press **Play**. You decide
>     when it speaks. Press **Clear** and do it again with different words.
> 12. **Now let it decide.** Tap four and pause without pressing anything — it
>     generates on its own once you stop. Try: **mom**, then the **places** page
>     link, then **park**, then **slide**. Note that walking to another page
>     mid-sentence does not lose what you already picked.
> 13. **Ask again, more urgently.** With a sentence on screen, press **Play**
>     again — or re-tap the last tile. Either repeats the request, and the
>     phrasing escalates rather than repeating verbatim, the way a child who was
>     not heard the first time would ask again. Try: from **home**, tap **dad**,
>     tap **chocolate**, press **Play**, then tap **chocolate** again.
> 14. **Add a new word** to one of your boards and let it draw a picture for it.
> 15. **Go back to Activity.** It should now show the sentences, and what they
>     cost.
>
> ### What we most want to hear
>
> - Did anything feel broken, slow or confusing **before** you added a key?
> - Is the child-facing screen calm enough to hand to a child?
> - Did anything in Admin look like it needs a manual?
> - What did you expect to find and could not?
>
> TestFlight feedback, or support@blasterai.app.

---

## Notes for us, not for them

**Keyless first, and most of the walk is keyless.** Gate 6 was originally framed
defensively — "verify the app is usable with no key", as though keyless were a
review workaround to survive. It is not: it is the majority configuration on a
child's device, and it is also exactly the road a reviewer takes. Ordering the
walk this way puts the most eyes on the path most families live on.

**The reviewer walk is deliberately complete without a key.** A reviewer who
never adds one should still have seen the child surface, the board editor,
conceal, PDF export, image sets and Activity — enough to judge the app as what
it claims to be rather than as a demo waiting for a credential. The offer of a
funded key is at the end, as an option rather than a prerequisite.

**No feature list.** The order-of-the-pitch discipline in
`docs/final-countdown-plan.md` applies here too: no OBF/OBZ, packs by name,
Fitzgerald colours or Brown's Stages. A tester told to look at everything looks
at nothing. Coverage appears once, as a question rather than a feature.

**Patient mode is missing from the walk on purpose**, and is asked for
separately. Everyone here is told to choose Caregiver, so nobody exercises the
locked-down configuration a child's device actually runs in — Admin gated, the
caregiver menu restricted, no way out of the board by accident.

Mark is asking Kurt to do that pass specifically, standing in for Brandi: set a
device to Patient and then try to get out of it without knowing the PIN. It is a
safety property, it has only ever been tested by people who expected it to hold,
and the person best placed to break it is a UX researcher who did not build it.

**Round 1 is internal only**, so section 1 is not needed yet. It becomes required
at the first external invite, alongside Beta App Review and the gifted evaluator
keys.
