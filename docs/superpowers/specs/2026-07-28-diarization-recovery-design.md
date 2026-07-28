# Speaker Diarization Recovery and Duplicate-Name Crash Fix

**Date:** 2026-07-28
**Status:** Approved for implementation

## Background

Three pre-open-source pull requests worked on transcription and diarization quality. One merged
before the repository was published; two were closed unmerged during branch cleanup three days
before publication, and their work never reached this repository.

The merged branch introduced batch Parakeet TDT ASR plus Silero VAD, which replaces the streaming
transcript after recording stops. That work is present in `DiarizationManager+BatchASR.swift` and
`MeetingStore+Diarization.replaceTranscript(for:with:)`.

The two unmerged branches were parallel, not sequential — neither is a superset of the other:

- One rewrote transcript-to-speaker alignment and normalized Sortformer's raw output.
- One replaced Apple Speech with a FluidAudio streaming ASR engine for the live preview.

Both branches were stale enough that their diffs revert later `main` changes — they strip `Sendable`
from `Speaker`, `SpeakerSegment`, `ActionItem`, `DiarizationConfig`, and roughly ten other types, and
one downgrades `project.pbxproj` `objectVersion` from 77 to 63. That is branch drift, not work to
recover.

A separate bug report (issue #31) describes the app crashing after a user renamed two speakers to the
same name, and crashing again on every subsequent attempt to open that meeting. That crash is
unrelated to any of the three branches.

## Scope Decisions

**The streaming ASR engine is out of scope.** Batch Parakeet already overwrites the final transcript
after recording stops, so a streaming engine changes only the throwaway live preview. The cost is a
second ASR model download and roughly 600 lines of new heuristics — a pending volatile queue,
volatile-stable promotion, synthetic timeline generation — sitting directly on the recording hot path.
The benefit does not survive the batch pass that follows it.

**Hardcoded two-speaker collapsing is out of scope.** Both unmerged branches assume a two-speaker
world: one takes the top two speakers by total speech duration and remaps everyone else onto them;
the other collapses any third speaker into the temporally nearest of two. On a genuine three- or
four-person meeting these destroy correct output. The speaker-count-agnostic parts of that work
(minimum-duration filtering, same-speaker merging, alternation collapsing) are in scope; the top-two
remapping is not.

**No identifying information carries over.** The private Apple `DEVELOPMENT_TEAM` identifier that
appears in one branch's `project.pbxproj` is not ported — and is moot regardless, since this project
generates `project.pbxproj` via XcodeGen. Branch names, personal names, PR numbers, and
`Co-authored-by` trailers from the closed branches appear nowhere in code, comments, or commit
messages. All commits are authored as `westerosweb`.

## Part 1 — Duplicate-Speaker-Name Crash

### Root cause

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

### Fix

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

### Delivery

A standalone pull request closing issue #31, reviewable independently of Part 2 and shippable as a
patch release.

## Part 2 — Diarization Alignment and Timeline Recovery

### What the current code already does well

Parts of the unmerged branches are already superseded here and must not be re-introduced:

- `renumberSpeakers(for:)` in `RecordingSessionManager+Diarization.swift` already fixes
  non-contiguous speaker numbering ("Speaker 1" and "Speaker 3" for a two-speaker meeting) and
  additionally prunes speakers holding no transcript segments. It is strictly better than the
  contiguous-remap function one branch proposed.
- Live and periodic diarization are already inert: `DiarizationManager.startPeriodicProcessing` and
  `RecordingSessionManager+Diarization.applyDiarizationResult` have no callers anywhere in the
  codebase. The "switch from live to post-recording diarization" goal of one branch is already met,
  so its approach of wrapping the periodic path in `if false { ... }` is unnecessary.
- Sortformer diarization and batch Parakeet ASR already run concurrently over one buffer snapshot in
  `processSortformerDiarization`.

### Alignment rewrite

`MeetingStore+Diarization.updateSpeakerData` currently assigns speaker labels by taking each
transcript segment's midpoint and finding the nearest speaker segment within
`AppConstants.Diarization.speakerLabelTolerance` (3.5 seconds). A midpoint carries no information
about how much of the segment each speaker actually occupies, and a 3.5-second nearest-neighbour
window will label a segment from a speaker who was not talking during it.

A new pure type, `Logue/Engine/SpeakerAlignment.swift`, replaces that with:

- **Overlap-duration voting.** The speaker with the greatest temporal overlap wins, rather than the
  one nearest the midpoint.
- **Chunked weighted majority.** Transcript segments longer than `chunkThresholdSeconds` are divided
  into `chunkDurationSeconds` slices; each slice votes, weighted by its duration. A long segment
  spanning a speaker change no longer collapses to a single label chosen by its midpoint.
- **Continuity guard.** Switching away from the previous segment's speaker requires the new speaker's
  overlap to exceed the previous speaker's by at least `continuityThreshold`. This suppresses
  single-segment speaker flapping.
- **Ambiguity handling.** When a second speaker's overlap exceeds `ambiguityOverlapRatio` of the
  winner's, the previous speaker is preferred over an effectively arbitrary choice between two
  near-equal candidates.
- **Boundary splitting.** A transcript segment overlapping two or more speaker ranges by a meaningful
  margin is split at the boundaries, with its text distributed across the parts in proportion to
  their durations. Split parts are ordering- and duration-clamped, capped in count, and the original
  segment is kept intact whenever no valid split can be produced.
- **Island smoothing.** A single segment flanked on both sides by the same other speaker adopts that
  speaker.
- **Tight fallback.** When no speaker segment overlaps at all, the nearest-neighbour fallback window
  is capped at 0.5 seconds rather than 3.5. `speakerLabelTolerance` keeps its current value and its
  current role in `alignTranscriptionWithSpeakers`, which gathers text into speaker segments and is a
  different operation.

Two elements of the source branch are deliberately excluded: a file-scope
`var alignmentRunCounterByMeetingID` dictionary (mutable global state, unsynchronized, serving only
debug telemetry), and per-segment `Logger.info` calls, which would emit thousands of log lines per
meeting. Summary-level logging is retained.

`MeetingStore+Diarization.updateSpeakerData` keeps its signature and its early-out when every
transcript segment already carries a label; it delegates the algorithm to `SpeakerAlignment` and
remains responsible only for reading, writing, and persisting.

### Sortformer timeline normalization

Raw Sortformer output currently flows into speaker data unmodified. The source branch's own benchmark
note recorded three detected speakers for a two-speaker recording, with overlapping and fragmented
segments. A new pure type, `Logue/Engine/SortformerTimeline.swift`, normalizes the timeline before it
becomes `SpeakerSegment` data:

- Discard segments shorter than `minSpeakerSegmentDuration`.
- Merge adjacent segments from the same speaker separated by less than `sameSpeakerMergeGap`.
- Collapse rapid A-B-A alternations within `alternationWindowSeconds` to the dominant speaker by
  duration.
- Enforce timeline continuity: clamp overlapping starts forward, and cap gaps so a normalized
  timeline has no unexplained holes.

Called from `processSortformerDiarization` before `applySortformerUpdates`. Speaker-count-agnostic
throughout — no step assumes or enforces a speaker count.

### Model preload

`DiarizationManager` gains a `preloadModels()` entry point so Sortformer models are resident before
the first recording rather than loaded on demand at recording start.

Two problems in the source branch's version are corrected. Its guard
(`cachedSortformerModels == nil, !isModelReady`) admits concurrent callers, so two calls both
download. And a launch-time HuggingFace download changes behaviour for users who never record.

The implementation will therefore be idempotent via a stored in-flight `Task` handle, and the
launch-time preload will warm only models already present in the local HuggingFace cache; a first-run
network download still happens at recording start as it does today. If FluidAudio's API cannot
express a cache-only load, the preload is instead gated behind a persisted flag set once the user has
completed at least one recording. Either way, no user acquires a background download they did not
already implicitly request.

### Bounded wait for model initialization on stop

`RecordingSessionManager.stopRecording` sets `diarizationInitTask = nil` without awaiting it. The
decision not to *cancel* is correct and already documented in the code — cancelling would abort a
model download mid-flight. But not awaiting means that if models are still initializing when
recording stops, `diarizer.isStreamingActive` is `false` and `processDiarization` silently degrades
to the batch fallback.

`stopRecording` will await the captured init task with a bounded timeout before invoking
`processDiarization`, so post-recording AI is never blocked indefinitely. The timeout is a named
constant in `AppConstants.Delays`, not an inline literal.

### Resumed-recording correctness

This bug is not addressed by any of the three branches and was found while comparing them against
current code.

`RecordingSessionManager` sets `timeOffset` when recording resumes into an existing meeting, and
tags streaming transcript segments with it. Diarization and batch-ASR output are not offset:

- `applySortformerUpdates` and `mergeDiarizationResult` write Sortformer and batch-diarizer
  timestamps unmodified, and those are session-relative, starting at zero.
- `DiarizationManager.transcribeBuffer` returns batch-ASR segments derived from token timings over
  the current session's buffer, also starting at zero.
- `replaceTranscript(for:with:)` **assigns** `meetings[index].segments`, so on a resumed recording it
  discards every segment from earlier sessions.

The consequence is transcript loss on resume, plus speaker labels aligned against the wrong
timebase. One unmerged branch introduced a `timeOffset` parameter along this call chain, but it
predates the batch-ASR work and so does not cover the destructive replace.

The fix threads the session's `timeOffset` — captured in `stopRecording` before it is reset to zero —
through `processDiarization` into `applySortformerUpdates`, `mergeDiarizationResult`, and the
batch-ASR result, and narrows `replaceTranscript` to the current session's time range so
earlier-session segments survive. Delivered as its own commit within Part 2's pull request, since it
touches the same signatures.

### Dead code and stale documentation

The following are unreachable and will be removed:

- `DiarizationManager.startPeriodicProcessing(onUpdate:)` and its `periodicTask` storage
- `RecordingSessionManager+Diarization.applyDiarizationResult(_:for:isPeriodic:)`
- `RecordingSessionManager.isPeriodicDiarizationStopped` and `hasPeriodicDiarizationResults`, and the
  `isFinalizing || !isPeriodicDiarizationStopped` guard in `applySortformerUpdates` that reads them

Stale comments will be corrected, including the `RecordingSessionManager` comment describing
post-recording diarization via `processCompleteRecording()` — superseded by `processCompleteWith(_:)`
— and the `MeetingStore+Diarization` comment attributing existing labels to "periodic diarization",
a path that no longer runs.

`SpeakerDetectionStatus` keeps its current cases and its `.active` value during recording. That value
is defensible — audio is being accumulated for speaker detection — and changing it is UI churn
outside this work's purpose.

### New constants

Added to `AppConstants.Diarization`: `chunkThresholdSeconds`, `chunkDurationSeconds`,
`continuityThreshold`, `ambiguityOverlapRatio`, `minSpeakerSegmentDuration`, `sameSpeakerMergeGap`,
`alternationWindowSeconds`, `labelFallbackTolerance`, and the split-related bounds (minimum
subsegment duration, maximum split parts, meaningful overlap threshold). The source branch hardcoded
several of these inline. The model-init wait timeout goes in `AppConstants.Delays`.

## Architecture

Both new types are pure: value inputs, value outputs, no `MeetingStore`, no `RecordingSessionManager`,
no `Logger` dependency injected through a store, no global mutable state.

```text
RecordingSessionManager+Diarization.processSortformerDiarization
    │
    ├── DiarizationManager.takeAudioBuffer()
    ├── DiarizationManager.processCompleteWith(_:)   ─┐ concurrent
    ├── DiarizationManager.transcribeBuffer(_:)      ─┘
    │
    ├── SortformerTimeline.normalize(_:)              ← new, pure
    ├── applySortformerUpdates(_:for:isFinalizing:timeOffset:)
    ├── renumberSpeakers(for:)
    ├── MeetingStore.replaceTranscript(for:with:timeOffset:)
    │
    └── MeetingStore.updateSpeakerData(for:speakers:speakerSegments:)
            └── SpeakerAlignment.assignLabels(...)    ← new, pure
```

Keeping the algorithms out of the extension files matters for size as well as clarity.
`RecordingSessionManager+Diarization.swift` is 446 lines today; absorbing the timeline normalization
inline would push it past the project's ~500-line extension guideline.
`MeetingStore+Diarization.swift` is 71 lines and would stay under that ceiling at roughly 470, but it
would stop being a persistence extension and become an alignment engine with a store attached — the
concern the guideline exists to prevent.

## Testing

Swift Testing suites (`@Suite`, `@Test`, `#expect`) in `LogueTests/`. All three are pure logic — no
model downloads, no inference, seconds to run, unlike the `LogueTests/LLMIntegration` suites.

**`SpeakerAlignmentTests.swift`**

- Overlap voting picks the majority-overlap speaker where midpoint matching picks the wrong one
- A long segment spanning a speaker change splits at the boundary with text distributed by duration
- The continuity guard suppresses a single-segment flap on a marginal overlap gain
- Ambiguous overlap (second-best above the ratio) prefers the previous speaker
- Island smoothing rewrites a lone segment flanked by one other speaker
- No overlap beyond the 0.5s fallback window leaves the label `nil`
- Empty speaker segments, empty transcript, and a single speaker are all no-ops
- A split producing no valid parts returns the original segment unchanged

**`SortformerTimelineTests.swift`**

- Sub-threshold fragments are discarded
- Adjacent same-speaker segments within the merge gap combine
- A-B-A alternation inside the window collapses to the duration-dominant speaker
- Overlapping starts clamp forward; oversized gaps are capped
- A three-speaker timeline survives normalization with all three speakers intact — the regression
  guard against reintroducing two-speaker collapsing
- Empty input returns empty

**`SpeakerRenameTests.swift`**

- Renaming to an unused name renames in place
- Renaming to an existing speaker's name merges: segments relabeled, `speakerSegments.speakerId`
  remapped, duplicate `Speaker` row removed
- Building a name-keyed color map from a meeting holding duplicate names does not trap
- Empty and whitespace-only names, and renaming to the current name, are no-ops

## Verification

1. `xcodegen generate` — both new files land under `Logue/`, which the target discovers by path
2. `xcodebuild build -project Logue.xcodeproj -scheme Logue -destination 'platform=macOS'`
3. The three new suites, plus the existing non-LLM suites, pass
4. SwiftFormat and SwiftLint clean via the pre-commit hooks, with no new suppressions

## Known Limitation

Diarization accuracy cannot be measured from code review. The alignment and splitting changes are
well-reasoned, and the fragmentation they target is documented in the source branch's own benchmark
note — but "improves quality" is a claim that requires a real multi-speaker recording to confirm. The
unit tests verify the algorithms behave as specified on constructed inputs; they do not establish an
accuracy improvement on real audio. That verification is a manual step after implementation.
