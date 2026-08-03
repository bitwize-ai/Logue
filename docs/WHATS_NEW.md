# What's New — what to do at every release

Logue tells people what a release changed. This is the runbook for keeping that true,
release after release. It is short on purpose: **appending one block to one Swift file is
the whole job for a normal release.**

Read [RELEASE_SETUP.md](RELEASE_SETUP.md) for the build, signing and notarization side.
This file covers only what a release owes the user in words.

## The two audiences, and why they get different lists

They are asking different questions, so nothing is derived from anything else. The two
lists live side by side in `Logue/Services/WhatsNewCatalog.swift`.

| | Fresh install | Upgrade |
| --- | --- | --- |
| Question | "What is this app for?" | "What changed since I last looked?" |
| Source | `WhatsNewCatalog.tour` | `WhatsNewCatalog.releases` |
| Contents | A hand-picked highlights reel | Only the releases they have not seen |
| Shown | Once, right after the onboarding wizard | On the first launch of a newer build |
| Changes when | Rarely — see below | Every release |

A newcomer has just clicked through seven pages of setup. Handing them a dozen cards of
features they have no context for is how a tour gets skipped, which is why the fresh-install
list is curated by us and short rather than being the release list. That is the split you
are looking at, and it is deliberate.

Both are reachable any time from **Help → What's New** and **Settings → General**.

## Every release: append one block

In `WhatsNewCatalog.releases`, append a block for the version being tagged. Ascending by
version — the newest goes last.

```swift
WhatsNewRelease(
    version: AppVersion(major: 1, minor: 2, patch: 0),
    features: [
        Feature.somethingWithArt,   // illustrated cards first
        Feature.somethingElse,
    ]
),
```

Features are defined once in the private `Feature` enum at the top of the file and composed
into both lists, so the copy cannot drift between them. Add new ones there.

**List only what this release added.** A user upgrading from the previous version has
already seen everything before it, and `WhatsNewGate` will hand a user who skipped three
releases all three decks at once, newest first, each card badged with the version that
brought it. Repeating older features means seeing them twice.

Four rules the tests enforce, so a slip fails CI rather than shipping:

- **Illustrated cards come first within a block.** A deck that opens on a symbol-only card
  reads as though the screenshots are broken. This is exactly the bug that was reported
  against the first version of this feature.
- **Every `screenshot:` name resolves to a file in the bundle.** A typo degrades silently
  to a symbol-only card, which is why it is a test and not a convention.
- **At most 12 cards in a block.** 1.1.0 is the only one that should ever come close.
- **Feature `id`s are unique within a block and never reused.** Tests and screenshots pin
  to them.

### The version is a clamp, not a label

`WhatsNewGate` never shows a release newer than the running build. So a 1.2.0 block
committed while `MARKETING_VERSION` still says 1.1.0 is invisible until the version is
bumped — a development build cannot advertise a release that does not exist.

That is a feature: **write the block as the work lands, not at tag time.** It stays dark
until the release is real.

To see it before then, use Help → What's New, which opens the newest catalogued release
this build actually is — falling back to the fresh-install tour when the build predates
every block.

## Every release: move `[Unreleased]` in the changelog

Move `## [Unreleased]` in `CHANGELOG.md` into `## [X.Y.Z] - <date>` **before tagging**.

That section is not just documentation. `scripts/extract_release_notes.py` reads it at tag
time and it becomes two things:

- Sparkle's "what's new" pane, so the update dialog says what the update contains before
  the user commits to downloading it.
- The GitHub Release body.

Forgetting falls back to `[Unreleased]`, which ships whatever happens to be sitting there —
including things that are not in the tag. The workflow warns on stderr when it falls back;
the warning is in the job log.

The changelog and the catalog are written for different readers and neither generates the
other. The changelog is a record — exhaustive, with issue numbers and attribution. The
catalog is a handful of cards someone reads once. Say the same things differently.

## Rarely: revisit the fresh-install tour

`WhatsNewCatalog.tour` is hand-picked and does **not** change when a release ships.

Revisit it only when something lands that changes what Logue *is* — not for every addition.
If you cannot say which existing card it should displace, it does not belong there. Keep it
at six cards or fewer; a test enforces that.

## Adding a screenshot

1. Put the PNG in `Logue/Resources/`, named `whatsnew-<slug>.png`.
2. Reference it by base name, no extension: `screenshot: "whatsnew-<slug>"`.
3. Run `xcodegen generate`. Resources are picked up from the folder, so there is nothing
   to add by hand.

Resize to **900px wide**. The card displays at roughly 340pt, so 900px is twice what a
Retina display needs and keeps the app around 200 KB per image rather than 500 KB.

```sh
sips --resampleWidth 900 Logue/Resources/whatsnew-<slug>.png
```

A feature without art renders its SF Symbol instead. That is the ordinary case, not a
degraded one — most cards have no screenshot. What is not ordinary is a name that no longer
matches a file, which is why the test walks the catalog.

## The stamp

`lastSeenWhatsNewVersion` in `UserDefaults` records the newest release a user has been
shown. Four properties, each of which cost something to learn:

- **Written when the sheet closes, not when it opens.** A crash in between costs a second
  showing rather than swallowing the notes permanently.
- **Only ever rises.** Re-opening the notes from the Help menu, or running an older build
  against a newer stamp, cannot make a release unseen again.
- **Survives "Reset Application Data".** A reset is drastic enough without replaying every
  release note ever written. Guarded by `TroubleshootingActions.preservedDefaultsKeys`.
- **Absent means one of two different things.** No stamp *and* onboarding done means an
  install predating this feature, which has been told nothing and is owed everything. No
  stamp *and* onboarding not done means a fresh install, which gets the tour. Telling those
  apart is the whole reason the gate reads `hasCompletedOnboarding`.

## Why 1.1.0 carries the whole back catalogue

1.1.0 is the release that introduces What's New, so every user arriving from 1.0.0 or 1.0.1
has been told nothing in-app — everything shipped so far is new *to them*. Its block is
therefore the full feature set rather than only what 1.1.0 added.

**It is a one-off. Do not copy it as the pattern.** Every release after it lists only its
own additions, which is a handful of cards. The 12-card cap exists to make an accidental
repeat fail the build.

## Checklist for cutting X.Y.Z

- [ ] `CHANGELOG.md`: `## [Unreleased]` → `## [X.Y.Z] - <date>`
- [ ] `WhatsNewCatalog.releases`: block for X.Y.Z, illustrated cards first, only what this
      release added
- [ ] `WhatsNewCatalog.tour`: only if this release changes what Logue is
- [ ] `project.yml`: `MARKETING_VERSION` → X.Y.Z, then `xcodegen generate`
- [ ] Tests pass: `xcodebuild test -only-testing:LogueTests/WhatsNewGateTests`
- [ ] Tag `vX.Y.Z` and let `.github/workflows/release.yml` do the rest

To see the whole thing as a first-time user would, on a build whose `MARKETING_VERSION` is
at or past the newest block:

```sh
defaults delete com.bitwize.logue hasCompletedOnboarding lastSeenWhatsNewVersion
```
