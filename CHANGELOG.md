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
- **What's New after an update.** Logue now says what a release changed, showing only the
  versions you have not already seen — several at once if you skipped some. A first install
  gets a short tour of what Logue does instead, after the setup wizard rather than inside it.
  Both are reachable any time from Help → What's New and from Settings → General.
- Initial public open-source release of Logue under the MIT License.

### Fixed

- Lists no longer show an empty state while the library is still loading — launching used to
  flash "No Documents" and greet returning users with the new-user welcome screen.

### Changed

- Update prompts now say what the update contains. Sparkle's release-notes pane had been
  empty since 1.0.0 because the appcast carried no description; it and the GitHub Release
  body are now both generated from this file at tag time.
- The README no longer claims release builds are sandboxed. They are not, and deliberately so:
  a sandboxed process cannot be an Accessibility API client, which disables the inline
  assistant, global hotkeys and Command Center. Hardened Runtime and notarization are on.

[Unreleased]: https://github.com/bitwize-ai/Logue/commits/main
