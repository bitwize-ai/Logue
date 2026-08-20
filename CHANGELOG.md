# Changelog

All notable changes to Logue are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **One place to start.** Home and Ask Logue were two screens doing one job; they are now a
  single landing surface — your day, what to pick back up, and a prompt bar that becomes the
  conversation without navigating away.
- **Tasks, and a way to triage them.** Action items Logue finds in a meeting land in a real
  list with due dates, priorities and tags. Typing "Send the deck tomorrow #launch !" files
  itself, and the triage panel turns a meeting's loose ends into things you can work.
- **Recordings that survive the worst.** Unplug a headset mid-call, mute for ten minutes, or
  quit the app outright — the recording keeps its place on the meeting's timeline and the
  transcript is rebuilt when Logue reopens, instead of ending where the trouble started.
- **A Logue extension for Chrome.** Brings Logue's chat and writing tools into any tab,
  answered by the model on this Mac. Install it from the Chrome Web Store; What's New links to
  it, and Help → Get the Chrome Extension keeps the link afterwards.

### Changed

- **Logue now accepts the browser extension's connection by default.** The loopback bridge the
  extension talks to shipped off, which meant the extension did nothing until a switch in
  Settings → Privacy was found — and almost nobody found it. It listens on your Mac's loopback
  address only, so nothing off the machine can reach it, and a notice on Home says plainly that
  it is listening and carries the switch to stop it. Anyone who turned it off deliberately stays
  off; the new default only applies where no choice was recorded.
- **What's New after an update.** Logue now says what a release changed, showing only the
  versions you have not already seen — several at once if you skipped some. Because nothing
  has ever been announced in-app, this first one covers everything shipped so far. A fresh
  install gets a short tour of what Logue does instead, after the setup wizard rather than
  inside it. Both are reachable any time from Help → What's New and from Settings → General.

### Changed

- Update prompts now say what the update contains. Sparkle's release-notes pane had been
  empty since 1.0.0 because the appcast carried no description; it and the GitHub Release
  body are now both generated from this file at tag time.

## [1.0.1] - 2026-08-02

The first release after open-sourcing. Three of the fixes below came from bugs
strangers reported in the two weeks the repository has been public.

### Added

- **Plain markdown storage (opt-in).** Store documents as ordinary `.md` files in `~/Logue`
  instead of encrypted storage, and edit them in any editor, track them in git, or point an
  agent at them. The folder is the storage rather than a copy: edits, new files, renames,
  moves and deletions flow both ways, and folders map to spaces including nested ones.
  Off by default, and Logue explains what encryption you are giving up before turning it on.
  Meetings, transcripts and audio are always encrypted, as is your trash. (#26)
- **Import markdown files and whole vaults into a space.** Right-click a space → Import…
  and choose files or a folder. A vault arrives as a tree, with subfolders becoming
  sub-spaces matched by name so importing twice does not produce `Projects (2)` beside
  `Projects`. Titles resolve frontmatter → `# H1` → filename and are stripped from the body,
  `tags:` and `created:` are honoured, and unrecognised frontmatter keys survive as document
  properties. Hidden entries are skipped, which covers `.obsidian`, `.trash` and `.git`.
  Everything is read on-device; nothing is uploaded. (#35, closes #28 — reported by
  [@tiagodenoronha](https://github.com/tiagodenoronha))
- **Wiki links and backlinks.** `[[Document Name]]` links documents, displays the target's
  real name, is clickable, survives renames, and every document lists what links back to it.
  A completion menu opens on `[[` with a ranked list of documents and meetings. (#25)
- **Document properties and relationships.** Typed fields — text, number, date, select,
  checkbox — and named links between documents, editable in a side panel. Relationship
  fields compute their own inverses, so declaring one side is enough. (#25)
- **Saved views and an inbox.** Save any filter as a sidebar entry, with nested all/any
  filter groups, relative date expressions and regex, and triage unfiled documents with
  keyboard-driven bulk actions. (#25)
- **Links panel and document graph.** A Connect sidebar group showing a document's graph
  neighbourhood, grouped by how each item connects. (#25)
- **Mermaid diagram and LaTeX math blocks** in the editor, durable in markdown through
  ` ```mermaid ` and `$$` fences. (#7)
- **Find and replace (⌘F)**, **move blocks (⌘⇧↑/↓)**, **`==highlight==` (⌘⇧M)**,
  **paste without formatting (⌘⇧V)** and **editor zoom (⌘+ / ⌘- / ⌘0)**. (#7, #39)
- **Quick open (⌘P / ⌘O)** — a flat, title-ranked list filtered on every keystroke,
  separate from the ⌘K command palette. (#39, closes #11)
- **Per-document width, and an app-wide default** for new documents in Settings → General.
  (#7, #39, closes #10)
- **`logue://` deep links** for documents, meetings and spaces, which now navigate rather
  than posting a notification nothing observed. Back history returns you to the document you
  followed a link from. (#7, #25)
- **Sanitized diagnostics on bug reports.** Filesystem paths, account name, URLs and API keys
  are excluded, external providers are reported as a count only, and every value is stripped
  of control characters. (#7)

### Fixed

- **Logue now appears under Privacy & Security → Accessibility.** Release builds shipped with
  the App Sandbox on, and a sandboxed process cannot be an Accessibility API client — no
  entitlement grants it. macOS therefore never listed Logue, and it could not be added by hand.
  This silently disabled every cross-app feature: the ⌘⌃I inline assistant, global hotkeys,
  the Command Center, and text replacement. No release before this one had working cross-app
  features. Logue is distributed Developer ID signed and notarized outside the Mac App Store,
  so the sandbox was never required; Hardened Runtime stays on and every entitlement exception
  remains individually justified. (#23, fixes #22 — reported by
  [@nunoraposo-cloud](https://github.com/nunoraposo-cloud))
- **The app no longer traps when two speakers share a name.** The transcript's speaker colour
  map was keyed by speaker name and built with `Dictionary(uniqueKeysWithValues:)`, which traps
  on a duplicate — so renaming one speaker to match another crashed the app, and kept crashing
  on every attempt to reopen that meeting. Meetings already broken by this open again with no
  migration. Renaming a speaker to a name already in use is now treated as the merge it was
  meant to be: segments are relabelled, speaker segments re-attributed, and the redundant row
  dropped. (#32, fixes #31 — reported by
  [@tiagodenoronha](https://github.com/tiagodenoronha))
- **The Ask Logue island can be put away again.** Its shortcut rebuilt it instead of closing it,
  which stranded the panel on screen with every way out of it dead — often leaving quitting
  Logue as the only escape. Esc and clicking outside were both watched in a way that could not
  see the event while Logue itself was frontmost, so each worked only some of the time. And
  switching apps meant nothing to the island, so the prompt bar sat over every other app until
  Logue was quit or hidden. It now closes on its own shortcut, on Esc and on a click anywhere
  outside it, and gets out of the way when you switch apps — keeping a conversation or an
  unsent prompt rather than discarding it, and coming back to the front on the shortcut that
  summoned it. (#49, fixes #46 — reported by [@keck](https://github.com/keck))
- **Meeting transcripts no longer stop at 30 minutes.** When a recording ended, the transcript
  was replaced by a re-transcription of audio held in memory — and that buffer was capped at
  thirty minutes while the replacement covered the whole session. A ninety-minute meeting lost
  its last hour at the moment recording stopped. The replacement is now bounded to the audio it
  actually heard, and past what memory can hold the recording is read back from its own file and
  processed to the end, so there is no longer a length at which the transcript or the speaker
  labels stop. (#48)
- **Meetings recorded from two sources keep their timing.** Microphone and system audio were
  accumulated in the order they arrived rather than by time, so turning the microphone on during
  an online meeting made every timestamp drift further out as the meeting went on, and halved the
  length that could be processed. (#48)
- **Playback lines up after muting.** A microphone switched on part-way through, or muted and
  resumed, played back early — by more with each toggle. (#48)
- **Speaker detection survives a microphone toggle.** Muting and unmuting during an in-person
  recording used to stop speaker detection silently for the rest of the session. (#48)
- A meeting's saved duration was read from a capture device's clock, which restarts whenever that
  source is toggled, so a long recording with a mid-session mute was stored with the wrong length.
  (#48)
- Lists no longer show an empty state while the library is still loading — launching used to
  flash "No Documents" and greet returning users with the new-user welcome screen.

### Changed

- **Speaker labels are assigned by overlap rather than by midpoint.** Each transcript segment
  used to take its midpoint and find the nearest speaker within 3.5 seconds, which carries no
  information about how much of the segment each speaker actually holds — a brief interjection
  landing mid-sentence captured the whole sentence, and the wide fallback window could label a
  segment with someone who was not speaking during it at all. Attribution is now overlap-duration
  voting, with long segments chunked and each slice voting by duration, near-ties keeping the
  previous speaker instead of flipping, genuinely shared segments split at the boundary, and the
  fallback tightened from 3.5s to 0.5s and used only when nothing overlaps. Raw diarizer output
  is cleaned up first — slivers filtered, same-speaker runs merged, rapid alternations collapsed.
  (#33)
- **Scrolling a document no longer rebuilds every block.** Each block published its frame through
  a SwiftUI preference measured in the scroll coordinate space, so scrolling invalidated the
  editor body, which rebuilt every row, which produced the next layout pass. The scroll fed
  itself, and it did so on small documents as much as large ones. On a 45-block document,
  measured body evaluations went from 48/sec to 0 and row builds from 2,208/sec to 0. (#43)
- The Portuguese locale is now European Portuguese rather than Brazilian Portuguese.
  (#40 — by [@tiagodenoronha](https://github.com/tiagodenoronha))
- The README no longer claims release builds are sandboxed. They are not, and deliberately so:
  a sandboxed process cannot be an Accessibility API client, which disables the inline
  assistant, global hotkeys and Command Center. Hardened Runtime and notarization are on.

## [1.0.0] - 2026-07-22

Initial public open-source release of Logue under the MIT License.

Logue is a native macOS app for AI meeting notes and document editing that runs entirely on
your Mac. Transcription, speaker diarization and LLM inference are all on-device via MLX on
Apple Silicon. There is no account, no telemetry gate and no cloud dependency; the only network
calls are on-device model downloads, Sparkle update checks, and features you explicitly opt into.

### Added

**Meeting intelligence**

- Real-time on-device transcription via Apple's `SpeechTranscriber` (macOS 26+), streaming
  audio directly with no buffering delay.
- Speaker diarization using FluidAudio's streaming Sortformer model, with a batch fallback.
- Simultaneous microphone and system audio capture via ScreenCaptureKit — no meeting bot
  joins the call.
- Smart Minutes: structured summaries with key decisions, themes and follow-ups.
- Smart transcript highlights, with manual bookmarks always preserved.
- Action item extraction — tasks, owners and due dates pulled from the transcript.
- Meeting prep briefings generated from linked documents and prior notes.
- Bidirectional meeting ↔ document links, with back-link chips in the editor.

**AI writing editor**

- Block-based rich text editor built on `NSTextView` with full SwiftUI integration.
- Inline grammar and clarity suggestions with one-tap acceptance.
- Tone analysis and adjustment for selected text.
- Vocabulary enhancement, validated against the actual document so hallucinated edits are
  discarded rather than offered.
- Rewrite and review panels — rephrase a passage, or get structural feedback on the document.
- Fact verification, flagging claims that may need a source.
- Full table creation, editing and context menus.
- Writing goals for word count, reading level and tone.
- Writing modes and a template gallery, with save-as-template for your own formats.

**Ask Logue — agentic AI chat**

- Multi-step agentic reasoning powered by LangGraph-Swift.
- Streaming token-by-token responses.
- Inline Mermaid diagrams and LaTeX math rendered in the chat thread.
- Deep research mode with progress tracking for long-running multi-source tasks.
- Tool execution UI showing what the agent is doing, with approval controls.
- Sources panel listing every document and meeting the agent consulted.
- Persistent, searchable memory across conversations.

**Cross-app features**

- A floating prompt bar (⌘⇧W) over any macOS app.
- An inline assistant (⌘⌃I) that rewrites text in place in any text field.
- A live transcript island at the top of the screen, so a meeting keeps transcribing in view
  while you work elsewhere.
- A menu bar Command Center for starting and stopping recordings from anywhere.

**Native macOS integrations**

- Calendar — read upcoming meetings, and create, update and delete events.
- Reminders — read, add, update and complete reminders.

Both are opt-in through macOS permissions and the data stays on your Mac.

**Search, tasks and automation**

- Unified ⌘K search across documents, meetings and action items.
- Ranked full-text search (SQLite FTS5) across every transcript and document body.
- Action item dashboard with filters (All / Pending / Overdue / Today / This Week /
  Completed), sort, search and a live sidebar overdue badge.
- Scheduled on-device AI tasks — daily digests, automatic summaries and weekly reviews.

**Privacy and distribution**

- AES-256-GCM encryption at rest for meetings, transcripts, audio and documents.
- Optional external AI providers (OpenAI/Anthropic-compatible), with keys stored in the
  macOS Keychain and used only when selected.
- Developer ID signed and notarized, with in-app auto-update over a signed Sparkle feed
  served from GitHub. No backend is involved.

### Known issues

Both were fixed in 1.0.1; they are recorded here because they affect this build.

- **Cross-app features do not work in this release.** It shipped with the App Sandbox enabled,
  which prevents Logue from being an Accessibility API client, so it never appears under
  Privacy & Security → Accessibility. The inline assistant, global hotkeys, Command Center and
  text replacement are all silently disabled as a result. (#22)
- **Meeting transcripts are truncated at 30 minutes.** When recording stops, the live transcript
  is replaced by a re-transcription of an in-memory buffer capped at thirty minutes, so anything
  longer loses everything past that point.

### Requirements

- macOS 26.0 (Tahoe) or later
- Apple Silicon (M1 or newer)

[Unreleased]: https://github.com/bitwize-ai/Logue/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/bitwize-ai/Logue/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/bitwize-ai/Logue/releases/tag/v1.0.0
