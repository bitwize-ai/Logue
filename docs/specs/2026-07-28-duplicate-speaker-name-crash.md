# Duplicate-Speaker-Name Crash Fix

**Date:** 2026-07-28
**Status:** Approved for implementation

## Background

Issue #31 reports the app crashing after a user renamed two speakers to the same name, and crashing
again on every subsequent attempt to open that meeting. The meeting becomes permanently unopenable.

The cause is a read-side trap rather than corrupt data, so the recovery is a code fix with no
migration. The diarization work that produced the split speaker rows in the first place is designed
separately in [2026-07-28-diarization-alignment-recovery.md](2026-07-28-diarization-alignment-recovery.md);
this document covers only the crash and the rename semantics around it.

## Root cause

`MeetingWorkspaceView.swift:142` builds the speaker color map keyed by speaker *name*:

```swift
speakerColors: Dictionary(
    uniqueKeysWithValues: meeting.speakers.map { ($0.name, $0.displayColor) }
)
```

`Dictionary(uniqueKeysWithValues:)` traps on a duplicate key. Two speakers named "John" therefore
raise `Fatal error: Duplicate values for key`. Because the expression sits in a view body, it traps
both when the rename is saved and on every subsequent attempt to open the meeting — matching the
reported behaviour exactly.

`MeetingSpeakersPanelView.renameSpeaker(from:to:)` permits the duplicate name because renaming a
speaker to an existing speaker's name is not treated as a merge.

Verified as *not* affected: `MeetingTools.swift:229` and `MeetingStore+Diarization.swift:14` key by
speaker `id`; `MeetingSpeakersPanelView`'s `ForEach(speakerStats, id: \.name)` iterates statistics
already grouped by name, so its keys are unique by construction.

## Fix

**Stop the trap.** Replace `Dictionary(uniqueKeysWithValues:)` with
`Dictionary(_:uniquingKeysWith:)`, keeping the first color. This is a read-side change, so meetings
already broken by the bug open again with no migration.

**Make the rename mean what the user meant.** The reporter renamed Speaker 2 to "John" because it was
John — diarization had split one person across two speaker rows. The intended operation is a merge.
Renaming a speaker to a name another speaker already holds will:

1. Relabel every transcript segment carrying the old name.
2. Remap every `SpeakerSegment.speakerId` from the renamed speaker's id to the surviving speaker's id.
3. Remove the now-redundant `Speaker` row.

Renaming to a name no other speaker holds keeps its current behaviour.

**Remove the duplicated rename logic.** Two call sites implement this rename today —
`MeetingSpeakersPanelView.swift:113` and an inline copy at `MeetingWorkspaceView.swift:130-133` — and
they can drift apart. Both will call one pure helper:

```swift
extension MeetingNote {
    func renamingSpeaker(from oldName: String, to newName: String) -> MeetingNote
}
```

Pure and value-typed, so it is testable without `MeetingStore`. Each call site performs a single
`store.updateMeeting(_:)` write, preserving the existing single-write behaviour.

Both call sites must also keep the unchanged-name early-out. `MeetingStore.updateMeeting` does not
compare before writing — it stamps `modifiedAt`, invalidates caches and persists unconditionally — so
a rename field committed without an edit would otherwise rewrite the meeting and reorder it in any
modified-date sort. Committing a field unchanged is ordinary behaviour, not an edge case.

## Testing

Swift Testing suite (`@Suite`, `@Test`, `#expect`) in `LogueTests/SpeakerRenameTests.swift`. Pure
logic — no model downloads, no inference.

- Renaming to an unused name renames in place, preserving the speaker's stable id
- Renaming to an existing speaker's name merges: segments relabeled, `speakerSegments.speakerId`
  remapped, duplicate `Speaker` row removed, segment timings and text preserved
- Merging into a name held by a speaker with no segments still collapses the rows
- Building a name-keyed color map from a meeting holding duplicate names does not trap, and covers
  every distinct name
- Empty and whitespace-only names, renaming to the current name, and renaming an unknown speaker are
  no-ops; surrounding whitespace is trimmed

## Verification

1. `xcodegen generate` — the new file lands under `Logue/`, which the target discovers by path
2. `xcodebuild build -project Logue.xcodeproj -scheme Logue -destination 'platform=macOS'`
3. `SpeakerRenameTests`, plus the existing non-LLM suites, pass
4. SwiftFormat and SwiftLint clean via the pre-commit hooks, with no new suppressions

## Delivery

A standalone pull request closing issue #31, reviewable independently of the diarization alignment
work and shippable as a patch release.

## Provenance

No identifying information carries over from the closed pre-open-source branches that motivated the
surrounding diarization work: no `DEVELOPMENT_TEAM` identifier, branch names, personal names, or
`Co-authored-by` trailers appear in code, comments, or commit messages. All commits are authored as
`westerosweb`.
