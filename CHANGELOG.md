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

- The Ask Logue island can be put away again. Its shortcut rebuilt it instead of closing it,
  which stranded the panel on screen with every way out of it dead — often leaving quitting
  Logue as the only escape. Esc and clicking outside were both watched in a way that could not
  see the event while Logue itself was frontmost, so each worked only some of the time. And
  switching apps meant nothing to the island, so the prompt bar sat over every other app until
  Logue was quit or hidden. It now closes on its own shortcut, on Esc and on a click anywhere
  outside it, and gets out of the way when you switch apps — keeping a conversation or an
  unsent prompt rather than discarding it.
- Lists no longer show an empty state while the library is still loading — launching used to
  flash "No Documents" and greet returning users with the new-user welcome screen.

### Changed

- The README no longer claims release builds are sandboxed. They are not, and deliberately so:
  a sandboxed process cannot be an Accessibility API client, which disables the inline
  assistant, global hotkeys and Command Center. Hardened Runtime and notarization are on.

[Unreleased]: https://github.com/bitwize-ai/Logue/commits/main
