# Diarization Alignment and Timeline Recovery

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
same name — the user was merging rows that the alignment problems below had split apart. That crash
is unrelated to any of the three branches and is designed and delivered separately, in
[2026-07-28-duplicate-speaker-name-crash.md](2026-07-28-duplicate-speaker-name-crash.md).

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

## What the current code already does well

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

## Alignment rewrite

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
- **Continuity under ambiguity.** When the runner-up speaker holds at least `ambiguityOverlapRatio`
  of the winner's overlap, the interval genuinely spans both speakers and picking the marginal
  winner is a coin flip, so the previous segment's speaker is kept instead. This suppresses
  single-segment speaker flapping.

  The source branch had two separate guards here — this one plus a `continuityThreshold` requiring
  a switch to beat the previous speaker's overlap by 5%. The second is unreachable: the previous
  speaker's overlap can never exceed the runner-up's (the runner-up is by definition the largest
  non-winner), so any case that would trip the continuity threshold trips the ambiguity check
  first. Only one guard is implemented.
- **Boundary splitting.** A transcript segment overlapping two or more speaker ranges by a meaningful
  margin is split at the boundaries, with its text distributed across the parts in proportion to
  their durations. Parts are butted against each other so the split covers the original span with no
  holes. Splitting is abandoned — the segment kept whole — whenever a faithful split is impossible:
  too many speakers, a part that would fall below `minSplitPartDuration`, or fewer words than parts.
  Splitting must never invent, duplicate, or drop text.
- **Island smoothing.** A single segment flanked on both sides by the same other speaker adopts that
  speaker, bounded to islands shorter than `maxSmoothedIslandDuration`. The source branch smoothed
  regardless of duration, which would erase a genuine short turn ("Yes", "I agree"); with timeline
  normalization already collapsing rapid alternations upstream, a two-second island is far more
  likely to be real speech than model flapping.
- **Tight fallback.** When no speaker segment overlaps at all, the nearest-neighbour fallback window
  is capped at 0.5 seconds rather than 3.5. `speakerLabelTolerance` keeps its current value and its
  current role in `alignTranscriptionWithSpeakers`, which gathers text into speaker segments and is a
  different operation.

Several elements of the source branch are deliberately excluded.

Two on style grounds: a file-scope `var alignmentRunCounterByMeetingID` dictionary (mutable global
state, unsynchronized, serving only debug telemetry), and per-segment `Logger.info` calls, which
would emit thousands of log lines per meeting. Summary-level logging is retained.

Two because they are defects:

- Its word-distribution routine reduces per-part word targets in a `while excess > 0` loop that only
  decrements a target already greater than one, and resets its cursor when it runs off the end. When
  every part needs one word but there are fewer words than parts, no target is reducible and the loop
  never terminates. Splitting a short segment across two speakers would hang the post-recording
  pipeline. The replacement allocates words by cumulative proportion and returns "do not split" when
  there are fewer words than parts.
- Its ordering clamp drops any segment shorter than 0.6 seconds, and it runs across the whole output
  rather than only over generated split parts — so short original segments ("Yes.", "Okay.") are
  silently deleted from the transcript. Ordering here never drops a segment: if a split would produce
  an undersized part, the split is abandoned and the original kept.

`MeetingStore+Diarization.updateSpeakerData` keeps its signature and its early-out when every
transcript segment already carries a label; it delegates the algorithm to `SpeakerAlignment` and
remains responsible only for reading, writing, and persisting.

## Sortformer timeline normalization

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

## Model preload — no change needed

This item was planned and then dropped: the current code already does it, and does more.

`DiarizationManager.prewarmGlobalCache()` runs from `RecordingSessionManager`'s initializer at app
launch and warms the Sortformer, Parakeet ASR, and Silero VAD caches. The source branch's
`preloadModels()` covered Sortformer only, so porting it would have been a regression in coverage and
a duplicate of existing behaviour. No preload work is included.

## Bounded wait for model initialization on stop

`RecordingSessionManager.stopRecording` sets `diarizationInitTask = nil` without awaiting it. The
decision not to *cancel* is correct and already documented in the code — cancelling would abort a
model download mid-flight. But not awaiting means that if models are still initializing when
recording stops, `diarizer.isStreamingActive` is `false` and `processDiarization` silently degrades
to the batch fallback.

`stopRecording` will await the captured init task with a bounded timeout before invoking
`processDiarization`, so post-recording AI is never blocked indefinitely. The timeout is a named
constant in `AppConstants.Delays`, not an inline literal.

## Resumed-recording correctness

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

## Dead code and stale documentation

The following are unreachable and will be removed:

- `DiarizationManager.startPeriodicProcessing(onUpdate:)`, `stopPeriodicProcessing()`,
  `processIncrementalChunk()`, `processRemainingChunk()`, and the `periodicTask`,
  `lastProcessedSampleIndex`, and `lastProcessedTime` state they carried
- `RecordingSessionManager+Diarization.applyDiarizationResult(_:for:isPeriodic:)`
- `RecordingSessionManager.isPeriodicDiarizationStopped` and `hasPeriodicDiarizationResults`, and the
  `isFinalizing || !isPeriodicDiarizationStopped` guard in `applySortformerUpdates` that reads them.
  With the guard gone, `applySortformerUpdates` no longer needs its `isFinalizing` parameter.
- `AppConstants.Delays.batchDiarizationInitialDelay`, used only by the periodic loop

Stale comments will be corrected, including the `RecordingSessionManager` comment describing
post-recording diarization via `processCompleteRecording()` — superseded by `processCompleteWith(_:)`
— and the `MeetingStore+Diarization` comment attributing existing labels to "periodic diarization",
a path that no longer runs.

`SpeakerDetectionStatus` keeps its current cases and its `.active` value during recording. That value
is defensible — audio is being accumulated for speaker detection — and changing it is UI churn
outside this work's purpose.

## New constants

Added to `AppConstants.Diarization`: `minSpeakerSegmentDuration`, `sameSpeakerMergeGap`,
`alternationWindowSeconds`, `timelineMaxGap`, `chunkThresholdSeconds`, `chunkDurationSeconds`,
`ambiguityOverlapRatio`, `labelFallbackTolerance`, `minSplitOverlap`, `minSplitPartDuration`,
`maxSplitParts`, and `maxSmoothedIslandDuration`. The source branch hardcoded most of these inline.
`continuityThreshold` is not added — see the unreachable second guard noted above. The model-init
wait timeout, `diarizationInitStopWait`, goes in `AppConstants.Delays`, replacing the
now-unused `batchDiarizationInitialDelay`.

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
    ├── MeetingStore.replaceTranscript(for:with:sessionStart:)
    │       └── final text is in place before any speaker is assigned
    │
    ├── SortformerTimeline.normalize(_:)              ← new, pure
    ├── applySortformerUpdates(_:for:sessionStart:)
    │       └── MeetingStore.updateSpeakerData(for:speakers:speakerSegments:)
    │               └── SpeakerAlignment.align(...)   ← new, pure
    │
    └── renumberSpeakers(for:)
```

Batch ASR replaces the transcript *before* speakers are assigned, so alignment runs against the final
text rather than the streaming draft it supersedes. The source branch ordered these the other way
round, which meant labels were computed against text that was about to be discarded.

Keeping the algorithms out of the extension files matters for size as well as clarity.
`RecordingSessionManager+Diarization.swift` is 446 lines today; absorbing the timeline normalization
inline would push it past the project's ~500-line extension guideline.
`MeetingStore+Diarization.swift` is 71 lines and would stay under that ceiling at roughly 470, but it
would stop being a persistence extension and become an alignment engine with a store attached — the
concern the guideline exists to prevent.

## Testing

Swift Testing suites (`@Suite`, `@Test`, `#expect`) in `LogueTests/`. Both are pure logic — no
model downloads, no inference, seconds to run, unlike the `LogueTests/LLMIntegration` suites.

**`SpeakerAlignmentTests.swift`** (21 tests)

- Overlap voting picks the majority-overlap speaker where midpoint matching picks the wrong one
- A near-tie keeps the previous speaker; a near-tie with no previous speaker takes the winner; a
  decisive overlap still switches
- A segment spanning two, then three, speakers splits at the boundaries, and every word survives the
  redistribution
- Splitting is declined when there are fewer words than parts, and when the second speaker's overlap
  is negligible
- A segment shorter than the split minimum is never dropped, and alignment never returns fewer
  segments than it received
- An already-labelled segment is neither relabelled, split, nor smoothed
- A brief island is smoothed; a two-second island keeps its own speaker
- The 0.5s fallback labels a segment just past a speaker's end and declines one far from every speaker
- Empty speaker segments, empty transcript, an unmapped speaker id, and a single speaker are handled

**`SortformerTimelineTests.swift`** (13 tests)

- Sub-threshold fragments are discarded, and input consisting only of fragments yields nothing
- Adjacent same-speaker segments within the merge gap combine; different speakers do not
- A-B-A alternation inside the window collapses to the duration-dominant speaker; a slow alternation
  is preserved
- Overlapping starts clamp forward, a fully swallowed segment is dropped rather than inverted, and
  output is ordered by start time
- A three-speaker timeline keeps all three speakers, including a quiet third speaker — the regression
  guard against reintroducing two-speaker collapsing
- Empty input returns empty; a single segment passes through unchanged

The three guards that carry the most judgement — the ambiguity check, the island-duration bound, and
splitting — were each verified by mutation: disabling the guard in the implementation must fail the
specific test written for it. Tests that cannot fail prove nothing, and a suite that passes on the
first implementation attempt deserves that check.

## Verification

1. `xcodegen generate` — both new files land under `Logue/`, which the target discovers by path
2. `xcodebuild build -project Logue.xcodeproj -scheme Logue -destination 'platform=macOS'`
3. The two new suites, plus the existing non-LLM suites, pass
4. SwiftFormat and SwiftLint clean via the pre-commit hooks, with no new suppressions

## Known Limitation

Diarization accuracy cannot be measured from code review. The alignment and splitting changes are
well-reasoned, and the fragmentation they target is documented in the source branch's own benchmark
note — but "improves quality" is a claim that requires a real multi-speaker recording to confirm. The
unit tests verify the algorithms behave as specified on constructed inputs; they do not establish an
accuracy improvement on real audio. That verification is a manual step after implementation.
