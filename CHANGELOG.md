# Changelog

All notable changes to Logue are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Plain markdown storage (opt-in).** Store documents as ordinary `.md` files in `~/Logue`
  instead of encrypted storage, and edit them in any editor, track them in git, or point an
  agent at them. The folder is the storage rather than a copy: edits, new files, renames,
  moves and deletions flow both ways, and folders map to spaces including nested ones.
  Off by default, and Logue explains what encryption you are giving up before turning it on.
  Meetings, transcripts and audio are always encrypted, as is your trash.
- **Wiki links and backlinks.** `[[Document Name]]` links documents, displays the target's
  real name, is clickable, survives renames, and every document lists what links back to it.
- **Document properties and relationships.** Typed fields — text, number, date, select,
  checkbox — and named links between documents, editable in a side panel.
- **Saved views and an inbox.** Save any filter as a sidebar entry, and triage unfiled
  documents with keyboard-driven bulk actions.
- Initial public open-source release of Logue under the MIT License.

### Fixed

- **Meeting transcripts no longer stop at 30 minutes.** When a recording ended, the transcript
  was replaced by a re-transcription of audio held in memory — and that buffer was capped at
  thirty minutes while the replacement covered the whole session. A ninety-minute meeting lost
  its last hour at the moment recording stopped. The replacement is now bounded to the audio it
  actually heard, and past what memory can hold the recording is read back from its own file and
  processed to the end, so there is no longer a length at which the transcript or the speaker
  labels stop.
- **Meetings recorded from two sources keep their timing.** Microphone and system audio were
  accumulated in the order they arrived rather than by time, so turning the microphone on during
  an online meeting made every timestamp drift further out as the meeting went on, and halved the
  length that could be processed.
- **Playback lines up after muting.** A microphone switched on part-way through, or muted and
  resumed, played back early — by more with each toggle.
- **Speaker detection survives a microphone toggle.** Muting and unmuting during an in-person
  recording used to stop speaker detection silently for the rest of the session.
- A meeting's saved duration was read from a capture device's clock, which restarts whenever that
  source is toggled, so a long recording with a mid-session mute was stored with the wrong length.
- Lists no longer show an empty state while the library is still loading — launching used to
  flash "No Documents" and greet returning users with the new-user welcome screen.

### Changed

- The README no longer claims release builds are sandboxed. They are not, and deliberately so:
  a sandboxed process cannot be an Accessibility API client, which disables the inline
  assistant, global hotkeys and Command Center. Hardened Runtime and notarization are on.

[Unreleased]: https://github.com/bitwize-ai/Logue/commits/main
