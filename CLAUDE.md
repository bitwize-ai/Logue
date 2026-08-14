# Logue — Development Guidelines

## Project Overview

macOS app (macOS 26+ / Tahoe): AI-powered meeting notes + document editing. Privacy-first — all AI inference, transcription, and data processing runs locally on-device via MLX. By default nothing leaves the laptop; the only network calls are on-device model downloads, Sparkle update checks, and opt-in features the user explicitly enables (web search, external AI providers).

- **Bundle ID:** `com.bitwize.logue`
- **Source:** `Logue/`, **Tests:** `LogueTests/`
- **Swift 5.9 + SwiftUI + AppKit**
- **Build system:** XcodeGen — run `xcodegen generate` after adding new `.swift` files or changing `project.yml`
- **Build:** `xcodebuild build -project Logue.xcodeproj -scheme Logue -destination 'platform=macOS'`
- **MLX prerequisite:** `xcodebuild -downloadComponent MetalToolchain`
- **Test (LLM integration):** `xcodebuild test -project Logue.xcodeproj -scheme Logue -destination 'platform=macOS' -only-testing:LogueTests/<SuiteName>`

## Dependencies

| Dependency | Source | Purpose |
| ---------- | ------ | ------- |
| `mlx-swift-lm` (`MLXLLM`, `MLXLMCommon`) | remote SPM | On-device MLX LLM inference on Apple Silicon |
| `swift-transformers-mlx` (`MLXLMTransformers`) | remote SPM | Tokenizers / model plumbing for MLX |
| `swift-hf-api-mlx` (`MLXLMHFAPI`) | remote SPM | Hugging Face model download / hub cache |
| `LangGraph` | `Vendor/LangGraph-Swift` (submodule) | Agent graph framework (used by `WritingAgentGraph`) |
| `Markdown` | `Vendor/swift-markdown` (submodule) | Markdown parsing |
| `FluidAudio` | remote SPM | Speaker diarization — streaming Sortformer + batch fallback |
| `Textual` | remote SPM | Rich-text rendering |
| `Sparkle` | remote SPM | In-app auto-update (GitHub-hosted appcast) |
| Apple `Speech` framework | system SDK | `SpeechTranscriber` for real-time transcription (macOS 26+) |

## Architecture

### Audio Pipeline (live capture streams directly; the post-recording pass chunks)

- `AudioRecorder` — mic capture, raw `AVAudioPCMBuffer` via callback
- `SystemAudioCapture` — ScreenCaptureKit system audio, `CMSampleBuffer` → `AVAudioPCMBuffer`
- `BufferConverter` — `AVAudioConverter` wrapper for format conversion
- `SpeechTranscriberEngine` — streams raw audio → `SpeechAnalyzer` → `TranscriptSegment`
- `RecordingSessionManager` — orchestrates engines + diarization; uses `RecordingState` enum (`.idle`, `.starting`, `.recording`, `.stopping`)
- `AudioTimelineMixer` — the session's audio on one 16 kHz timeline; each source writes at its own
  cursor and overlaps are summed, so an hour of meeting is an hour of buffer however many sources run
- `DiarizationManager` — FluidAudio wrapper; streaming Sortformer (primary) + batch accumulation
  fallback. Past what memory holds, the post-recording pass reads the saved file back in chunks
  (`+LongRecording`) instead of stopping

### Recording invariants

Two rules the recording path depends on, both learned the hard way:

- **A pass may only speak for the audio it actually heard.** The post-recording batch transcription
  replaces the live transcript, so it is bounded to the stretch it covered (`TranscriptReplacement`).
  Covering the session means *both* that the file lines up with it and that it is long enough to be
  it — alignment alone let a truncated file delete an hour of correct live transcript.
- **The saved audio file is the meeting's timeline.** A source records only while it runs, so its
  raw file is shorter than the meeting after a mute or a late join. `CaptureSegmentTimeline` records
  where each activation belongs and the file is rewritten to match. Whether that succeeded is
  *reported* by `persistRecordingAudio` (`SavedRecording`), never re-derived afterwards — a capture
  device's clock resets on every toggle, so anything inferred from it is wrong in exactly the cases
  that produce a misaligned file.

### LLM Engine

- `LLMEngine` (actor) — centralized inference, serialized via `inferenceGate`. Core: `complete(system:prompt:)`. Convenience: `generate()`, `chat()`, `analyzeRaw()`, `rephrase()` (in extension files). Also hosts LangGraph writing-agent nodes and streaming analysis. All extension methods MUST route through `complete()`/`completeStream()`.
- `LLMEngineStatus` (@MainActor @Observable) — singleton busy flag (`isBusy`) driven by `LLMEngine.inferenceQueueDepth`. UI views use `.disabled(LLMEngineStatus.shared.isBusy)` to prevent concurrent AI operations.
- `ModelManager` (@MainActor @Observable) — model downloads, activation, endpoint scanning (split: +Download, +Discovery, +HuggingFace)

### Ask Logue invariants (two surfaces, one assistant)

Ask Logue is reachable from two places — the pane in the main window and the Command
Center island floating over another app. They were built separately and drifted: the island
was a bare `chatStream` call with no tools, no memory, no attachments and nothing kept, while
the same question asked from the app got the full agent. **Which window you asked from
decided what Logue was.** These rules exist so that cannot happen again.

- **Which pipeline answers a question is decided in one pure place.** `AskRouter.route(for:)`
  returns agent loop, Deep Research or ImagePlayground. It is a pure function of its inputs —
  no SwiftUI, no `UserDefaults`, no classifier call — so the matrix is testable without a
  view or a model. A decision made inside a `View` is a decision the other surface cannot
  reach, which is exactly how the island ended up with no routing at all.
- **A route is never a function of the surface.** `AskSurface` says which window asked, and
  it is deliberately not an input to `route`. `AskRouteTests` asserts this, so adding it
  later fails the suite rather than silently reintroducing the split.
- **Live run state belongs to a conversation, not to the app.** `AgentRunState` scopes
  `isProcessing`, `isStreaming`, `streamingText`, `activeToolCalls` and `lastError` to the
  conversation that started the run. A global flag means a run on one surface paints its
  spinner, its streaming text and its tool cards onto the other's thread.
- **An error outlives its run but never its owner.** `lastError` persists after the run ends,
  so the banner survives until acknowledged — which is why `conversationID` survives
  `finish()` too. An error with no owner paints on every surface.
- **Anything added to one surface is added to both.** The composer, the conversation view and
  the error banner are *mounted* by both, never redrawn per surface. A feature that exists in
  one window and not the other is the bug this section is about.

### Data Layer

- `MeetingStore` (@MainActor @Observable) — encrypted JSON persistence (split: +AI, +Diarization, +Metadata, +Persistence, +Search, +SeedData, +WelcomeMeeting, Protocols)
- `MeetingNote` (struct, Codable, Sendable) — segments, speakers, speakerSegments, hasSpeakerData
- `EncryptionManager` — AES-256-GCM at rest, 7-day migration window for legacy unencrypted data
- `DocumentStorage` (@MainActor @Observable) — the only thing that knows *where* documents live: encrypted JSON, or plain `.md` files in `~/Logue` (split: +Rescan)

### Document Storage Modes

Documents have two storage modes; meetings only ever have one (encrypted). Off by default,
opt-in under Settings → Privacy.

**When plain markdown storage is on, the file IS the document.** There is no second copy and
nothing to reconcile. Rules that follow from that, all of which have bitten:

- **A scan updates the app and writes nothing back.** A write would produce a filesystem event,
  which produces a scan, which produces a write. The only exception is stamping `_logue_id` into
  a file dropped in by hand, without which every scan adopts it again.
- **A space's folder is found by its identity, never by recomputing a path from its name.**
  `SpaceFolderMap` resolves both directions from the `_logue_space_id` in `_space.md`. Deriving
  paths from names meant a folder the app spells differently (`-Work`, >60 chars) never matched
  its own space, which read as "no folder", which deleted the space and everything in it.
- **A living folder must never read as deleted.** `vanishedSpaceIDs` requires the folder to be
  absent by *both* the identity index and a path check, because anything that stops us reading
  `_space.md` is not evidence the folder is gone.
- **Nothing hard-deletes a file the user can see.** `trashItem`, never `removeItem` — a wrong
  decision should cost a trip to the Trash, not their text.
- **Ambiguity is never resolved by guessing.** Two files claiming one document means nothing is
  applied to that document at all; two folders claiming one space keeps the one the space is
  named after. Both are logged.
- **A plan is diffed against a snapshot, so re-check before applying.** Reading happens off the
  main actor and the user can type during it; `discardingUpdatesThatMovedOn` holds back anything
  that changed.
- **Structural changes made in the app write to disk immediately** (create/rename/move/delete a
  space). That is what earns a scan the right to read a missing folder as a deletion.
- **A missing root folder means do nothing.** An unmounted drive, a moved folder and an
  unfinished sync are indistinguishable from "everything was deleted".

### Tests (Swift Testing framework — @Suite, @Test, #expect, NOT XCTest)

- 94 `@Test` methods across 9 files in `LogueTests/LLMIntegration/`
- `LLMTestHarness.swift` — shared harness with `LenientSuggestionItem`, `repairTruncatedJSON()`, `stripMarkdownFences()`
- Tests run real inference against local MLX model
- Grammar suite uses 10-minute timeout; all others 5 minutes

## Code Standards (Enforced by Review)

### Security

- **Never use `[0]` on FileManager URL arrays.** Use `.first ?? URL.temporaryDirectory` — the array can be empty on edge-case system configurations.
- **Always wrap user content in XML delimiters** when injecting into LLM prompts:
  - Meeting transcripts → `<transcript>...</transcript>`
  - Document content → `<content>...</content>`
  - PII categories → `<categories>...</categories>`
  - This applies to ALL prompt construction — summaries, titles, chat, search, fact-check, vocabulary, PII detection, space suggestions. No exceptions.
- **Require HTTPS for all user-supplied endpoints** (except localhost/127.0.0.1). Validate before saving.
- **Sanitize all user-provided strings** (titles, keywords, model names, space names) before embedding in LLM prompts — truncate length, strip control characters. Use the pattern: `String($0.prefix(N)).filter { !$0.isNewline && $0.asciiValue != 0 }`
- **Use regex validation for structured input** (email, OTP, API keys) — never rely on `contains("@")` or length-only checks.
- **Log URLs with `url.host` only** — never log `url.absoluteString` anywhere in the codebase. This includes error handlers (`didFailProvisionalNavigation`, `didFail`), not just success paths.
- **URL-encode user-supplied path parameters** before interpolating into API endpoint strings. Use `.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)` to prevent path traversal.
- **Keychain is only for secrets.** Store only sensitive data in Keychain (user-supplied external-API keys). Public keys and non-secret configuration go in `UserDefaults` — simpler and no Keychain permission issues. All AI inference is on-device; external API providers are optional and their keys are user-supplied.
- **Sparkle EdDSA private key** lives only in the GitHub Actions secret `SPARKLE_PRIVATE_KEY` — never store it in the repo. The public key (`SUPublicEDKey`) is embedded in `Info.plist` via `project.yml`. Updates are served entirely from GitHub (appcast in-repo, assets on GitHub Releases) — there is no backend.
- **Use typed constants for notification userInfo keys** — never string literals like `"success"` in `userInfo` dictionaries.
- **Entitlements:**
  - **App Sandbox is OFF in both Debug and Release — do not re-enable it.** A sandboxed process cannot be an Accessibility API client, so macOS never lists the app under Privacy & Security → Accessibility and the user cannot add it manually. That silently kills every `Logue/CrossApp` feature (⌘⌃I inline assistant, global hotkeys, Command Center, text replacement). This shipped in 1.0.0 as issue #22. Guarded by `LogueTests/ReleaseEntitlementsTests.swift` and a CI step.
  - Distribution is Developer ID + notarization via GitHub Releases and Sparkle — not the Mac App Store — so the sandbox is not required. **Hardened Runtime stays ON.**
  - Sparkle needs no XPC services or `SUEnableInstallerLauncherService` when unsandboxed; those exist solely to work around the sandbox.
  - Debug (`Logue.entitlements`) and Release (`Logue.release.entitlements`) still differ: Debug carries the iCloud entitlements, Release does not.
  - Every security exception (`allow-jit`, `disable-library-validation`, etc.) must have a comment explaining why it's needed

### Concurrency and Thread Safety

- **LLMEngine is an actor but Swift actors are reentrant.** Use `inferenceGate` serialization pattern — capture the current gate, create a new task that chains onto it, and assign the new gate synchronously (before any suspension point). Both `complete()` and `completeStream()` participate in the same gate chain. Never assume actor methods run atomically across suspension points.
- **ALL inference MUST route through `complete()` or `completeStream()`.** Never call `session.streamResponse()` or `session.messages` directly from extension methods — this bypasses the `inferenceGate` and causes session races when multiple AI features run concurrently. Extension methods (grammar, clarity, tone, rephrase) should build system/user prompt strings and delegate to `complete()`.
- **Always add `@unchecked Sendable` safety documentation.** Every usage must have a comment explaining what provides thread-safety (lock, dispatch queue, immutability).
- **Always add `nonisolated(unsafe)` documentation.** Explain why the marker is needed and what guarantees safety.
- **Re-check state after async permission checks.** Recording/mic state may change during the `await` — always re-validate with a guard after resuming.
- **Use `RecordingState` enum** (`.idle`, `.starting`, `.recording`, `.stopping`) — never use separate boolean flags for state machines.
- **Use `[weak self]` in all Task closures** except when `self` is a singleton AND the task is trivially short. When in doubt, use `[weak self]`.
- **Use version counters instead of boolean flags** to suppress feedback loops in `onChange` handlers. Booleans reset via `Task { flag = false }` race with rapid state changes; counters don't. Sync `lastSeenVersion = currentVersion` in the handler that **increments** the counter (not in the handler that reads it), so subsequent legitimate changes are not blocked.
- **Check `Task.isCancelled` between expensive resource allocations.** Insert cancellation guards between session creation and prewarm, between model download and activation, etc.

### Error Handling

- **Never use silent `try?` for ANY operation.** This includes file I/O, directory creation, network requests, and data decoding. Use `do/catch` with logging. In static initializers where no Logger instance is available, use `os_log(.error, ...)`. **Exception:** `try? await Task.sleep(for:)` is acceptable — it only throws `CancellationError`, and silencing cancellation is idiomatic in Swift Concurrency.
- **Always use `withRetry()` / `withRetryOptional()`** from `RetryHelper.swift` instead of manual `for attempt in 1...3` loops.
- **Log LLM JSON decode failures** with the error message AND truncated raw response. Silent `try? JSONDecoder()` makes debugging impossible.
- **Add timeout guards to all polling/busy-wait loops.** Use `ContinuousClock.now + .seconds(N)` — never busy-wait indefinitely.
- **Validate array bounds before subscripting** in callbacks and closures where data may have changed since the closure was created. Use `guard index < array.count` before `array[index]`.

### LLM Integration

- **Validate context window before ALL LLM calls.** Truncate input to fit `maxKVSize - outputTokens - promptOverhead`. This applies to: summaries, chat, titles, vocabulary enhancement, fact-check, PII detection, space suggestion, document chat, grammar, clarity, tone, rephrase, `generate()`. The pattern: `let maxChars = ((LLMEngine.mlxParameter.parameters.maxKVSize ?? 16384) - reservedTokens) * 4`. Use `LLMEngine.maxInputChars(reservedTokens:)` or the private `truncatedContext(_:reservedTokens:)` helper in extension files.
- **Always pass explicit `maxTokens`** to `completeStream()` calls — the default (512) is too low for chat responses. Use `maxTokens: 2048` for conversational AI.
- **Rate-limit inference calls.** Use `maxInferenceQueueDepth` to reject calls when the queue is too deep (prevents GPU memory thrashing during bulk operations).
- **Retry with stricter format instructions** when JSON parse fails before falling back to plain-text. Add "IMPORTANT: You MUST output ONLY a valid JSON object" on retry.
- **Check available memory before loading models.** Use `mach_task_basic_info` to verify at least 512MB available — reject with clear error if insufficient.
- **Limit collection sizes in prompts.** Cap space descriptions at 10, content titles at 5, keywords at 5. Large collections exhaust context window.
- **Validate LLM output against source document.** When the LLM returns text that maps back to the document (e.g., vocabulary `original`, suggestion `original`), verify the text actually exists in the document body (case-insensitive) before presenting to the user. Discard hallucinated items that don't match.
- **Use `LLMEngineStatus.shared.isBusy`** to disable AI-triggering UI controls while inference is in progress. This prevents concurrent AI operations that could race on the LLM session. Add `.disabled(LLMEngineStatus.shared.isBusy)` to all buttons that trigger `LLMEngine.complete()` or `completeStream()`.

### Data and Persistence

- **Use `decodeIfPresent` with defaults** for array fields in Codable types (`segments`, `actionItems`, etc.). Never use bare `try container.decode()` for fields that could be missing in older data formats.
- **Encryption migration window is 7 days** (not 30). After that, unencrypted fallback is permanently disabled.
- **Use hash-based change detection** for `didSet` cache invalidation on large arrays — avoid invalidating on every property mutation.

### Code Organization

- **All delay constants go in `AppConstants.Delays`** — never hardcode `Task.sleep(for: .seconds(2))` or `DispatchQueue.main.asyncAfter(deadline: .now() + 0.3)` inline.
- **Large service classes must use extension files.** Pattern: `FooManager.swift` (core) + `FooManager+Feature.swift` (extensions). Each under ~500 lines.
  - `MeetingStore` → 8 extension files (+AI, +Diarization, +Metadata, +Persistence, +Search, +SeedData, +WelcomeMeeting, Protocols)
  - `ModelManager` → +Download, +Discovery, +HuggingFace
- **Extension-visible members:** When splitting a class into extension files, Swift requires `private` members to become `internal` for cross-file access. Mark these with `// Extension-visible: +FileName` comments explaining which extensions need access. Do not call extension-visible members from outside the class and its extensions. Prefer `let` constants and `private(set)` where possible to limit mutation surface.
- **NotificationCenter observers:** Always use block-based API (`addObserver(forName:)`) that returns a token. Store the token and remove in `applicationWillTerminate` or `deinit`. Never use `addObserver(self, selector:)`.
- **Exponential backoff for device retries.** Start at 50ms, double each attempt, cap at 400ms. Never use fixed retry delays.

### SwiftLint Compliance

**Write code that passes SwiftLint without suppressions.** The project enforces strict rules via pre-commit hooks (SwiftFormat + SwiftLint). Code that requires `swiftlint:disable` comments is a smell — fix the underlying issue instead.

**Rules to follow when writing code:**

- **No force unwrapping (`!`)** — use `guard let`, `if let`, or `?? default`. The `force_unwrapping` rule is opt-in and enforced.
- **No force casting (`as!`)** — use `as?` with guard. Exception: CF bridging (AXValue, AXUIElement) where `CFGetTypeID()` verification precedes the cast — Swift has no safe alternative for CF types.
- **Function body length ≤ 60 lines** — break large functions into helpers. If a function genuinely can't be split (complex state machine, UI builder), add `// swiftlint:disable:next function_body_length` with a reason.
- **Cyclomatic complexity ≤ 15** — simplify branching or extract helper methods.
- **File length ≤ 800 lines** — split into extension files. Suppression acceptable only for static data files (seed data, templates).
- **Identifier names: 2-60 chars, no `_` prefix** on non-private properties. Use descriptive names (`downloadAndActivateInternal` not `_downloadAndActivate`).
- **Line length ≤ 150 chars** (warning), ≤ 200 chars (error).

**Acceptable suppressions (with comment explaining why):**

- `force_unwrapping` on compile-time constant `URL(string:)!` and `UUID(uuidString:)!` in seed data / static definitions
- `force_cast` on CF bridging after `CFGetTypeID()` verification (no safe alternative in Swift)
- `file_length` on static data files (seed data, built-in templates) — these are data, not logic
- `function_body_length` on complex view builders or state machines that are cohesive units

### Style

- **`guard let` for runtime URLs** — never force-unwrap URLs constructed from runtime values.
- **Prefer `@Observable` over `ObservableObject`** for new classes. Use `@State` (not `@ObservedObject`) when consuming `@Observable` singletons in views.
- **Prefer `Task.sleep` over `DispatchQueue.main.asyncAfter`** in SwiftUI views and async contexts. GCD is acceptable only in AppKit delegate callbacks (NSTextView, NotificationCenter block handlers) where structured concurrency doesn't apply.
- **Use `DispatchQueue.main.asyncAfter` with `AppConstants.Delays`** — never hardcode `TimeInterval` literals in GCD calls.

## Key Files

| File | Role |
| ---- | ---- |
| `Engine/LLMEngine.swift` | Actor — all LLM inference (serialized via `inferenceGate`) |
| `Engine/LLMEngineStatus.swift` | @MainActor @Observable busy flag for disabling AI controls |
| `Agent/AskRoute.swift` | Which pipeline answers a question — pure, and the same from both surfaces |
| `Agent/AgentRunState.swift` | Live run state scoped to the conversation that started it |
| `Engine/RetryHelper.swift` | `withRetry()` / `withRetryOptional()` — centralized retry |
| `Engine/MeetingPromptBuilder.swift` | All LLM prompt construction + JSON parsing |
| `Engine/LLMClient.swift` | External LLM provider clients (OpenAI/Anthropic-compatible) — optional, user-configured |
| `Services/RecordingSessionManager.swift` | Recording lifecycle (`RecordingState` enum) |
| `Services/RecordingSessionManager+AudioFiles.swift` | Saving a session's audio as the meeting's timeline (splice/compose/move) |
| `Services/RecordingSessionManager+BatchPass.swift` | Choosing the in-memory or on-disk post-recording route |
| `Engine/AudioTimelineMixer.swift` | The session's audio on one timeline, mixed by time rather than arrival |
| `Engine/CaptureSegmentTimeline.swift` | Where each stretch of a source's file belongs on the meeting |
| `Engine/TranscriptReplacement.swift` | How much of the live transcript a batch result may replace |
| `Engine/AudioFileChunkReader.swift` | Reading a recording back in bounded chunks |
| `Engine/DiarizationManager+LongRecording.swift` | Transcribing and diarizing from disk, for recordings memory cannot hold |
| `Services/EncryptionManager.swift` | AES-256-GCM encryption at rest (7-day migration window) |
| `Services/SandboxContainerMigrator.swift` | One-time move of user data out of the pre-1.0.1 sandbox container (runs in `LogueApp.init()`) |
| `Services/DocumentStorage.swift` | Storage mode, switching both ways, the `~/Logue` location (+Rescan: watching and scanning) |
| `Services/MarkdownStorageMigrator.swift` | Every filesystem operation on the folder — export/verify/import/reconcile, folder create/move/retire |
| `Services/MarkdownFolderScan.swift` | One scan pass: folders → spaces, files → documents, → plan. Takes its root as a parameter, so it is testable |
| `Engine/SpaceFolderMap.swift` | Which folder belongs to which space, by identity rather than by name |
| `Engine/ExternalChangePlan.swift` | Pure diffing rules for what a scan means, plus the stale-update guard |
| `Engine/SpaceFolderAdoption.swift` | Pure rules for new, renamed and vanished folders |
| `Engine/MarkdownDocumentFile.swift` | The `.md` file format for a document (frontmatter + body) |
| `Engine/SpaceFile.swift` | `_space.md` — a folder's space identity, and the prose the user may add below it |
| `App/AppConstants.swift` | All constants: `LLMDefaults`, `Audio`, `Diarization`, `Delays` |
| `App/AppVersion.swift` | `CFBundleShortVersionString` parsed so releases can be ordered |
| `Services/WhatsNewCatalog.swift` | What shipped in which release — one block per version |
| `Services/WhatsNewGate.swift` | Whether a launch shows the tour, the release notes, or nothing |

## Releasing

Tagging `vX.Y.Z` runs `.github/workflows/release.yml`, which builds, signs, notarizes,
publishes, and opens a PR updating `appcast.xml`. Two things must be done by hand first,
because nothing can infer them:

- **Move `## [Unreleased]` in `CHANGELOG.md` into `## [X.Y.Z] - <date>`.** The workflow
  extracts that section for both Sparkle's release-notes pane and the GitHub Release body.
  Forgetting falls back to `[Unreleased]`, which ships whatever is sitting there — including
  things not in the tag.
- **Append a matching block to `WhatsNewCatalog.releases`** listing only what this release
  added, illustrated cards first. The catalog is bounded by the running build, so a block for
  a version that has not been tagged stays invisible until it is — write it as the work lands.

`WhatsNewCatalog.tour`, the fresh-install list, is hand-picked and does *not* change every
release. It answers "what is this app for", not "what changed", and a newcomer handed the
upgrade deck gets a dozen cards of features they have no context for yet.

Full runbook, including screenshots and the version stamp: **[docs/WHATS_NEW.md](docs/WHATS_NEW.md)**.
