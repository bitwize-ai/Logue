<a href="https://bitwize.ai/logue">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/header-banner-dark.png">
    <img alt="Logue, by Bitwize.ai" width="100%" src="docs/images/header-banner.png">
  </picture>
</a>

<p align="center">
  <b>Privacy-first AI meeting notes & writing assistant for macOS.</b><br/>
  On-device transcription, Smart Minutes, agentic chat and 60+ writing modes — all powered by Apple Silicon. Nothing leaves your Mac.
</p>

<p align="center">
  <a href="https://trendshift.io/repositories/90137" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/90137/daily?language=Swift" alt="bitwize-ai/Logue | Trendshift" width="250" height="55"/></a>
  <br/>
  <sub>First reached July 28, 2026</sub>
</p>

<p align="center">
  <a aria-label="License: MIT" href="https://github.com/bitwize-ai/Logue/blob/main/LICENSE" target="_blank">
    <img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-4630EB.svg?style=flat-square&labelColor=000000" />
  </a>
  <a aria-label="macOS version" href="https://www.apple.com/macos/" target="_blank">
    <img alt="Requires macOS 26+" src="https://img.shields.io/badge/macOS-26%2B%20Tahoe-000000?style=flat-square&labelColor=000000&color=4630EB&logo=apple&logoColor=white" />
  </a>
  <a aria-label="On-Device AI" href="https://bitwize.ai" target="_blank">
    <img alt="On-Device AI" src="https://img.shields.io/badge/AI-On--Device%20Only-33CC12?style=flat-square&labelColor=000000&logo=apple&logoColor=white" />
  </a>
  <a aria-label="Contact Bitwize" href="mailto:support@bitwize.ai" target="_blank">
    <img alt="Contact Bitwize" src="https://img.shields.io/badge/Contact-support%40bitwize.ai-4630EB?style=flat-square&labelColor=000000&logoColor=white" />
  </a>
</p>

<p align="center">
  <a aria-label="Download Logue" href="https://github.com/bitwize-ai/Logue/releases/latest"><b>Download for macOS</b></a>
&ensp;•&ensp;
  <a aria-label="Build from Source" href="#-build-from-source">Build from Source</a>
&ensp;•&ensp;
  <a aria-label="Contributing" href="CONTRIBUTING.md">Contributing</a>
&ensp;•&ensp;
  <a aria-label="Request a feature" href="https://github.com/bitwize-ai/Logue/issues">Request a feature</a>
</p>

<p align="center">
  <img alt="The Logue home surface on macOS — the prompt bar, what needs attention, and what to pick back up" src="docs/images/home-dashboard.png" width="900">
</p>

## Introduction

Logue is a privacy-first AI meeting-notes and writing assistant for macOS. It combines
real-time audio transcription, speaker diarization, and intelligent document editing —
all powered entirely **on-device via MLX on Apple Silicon**. By default your meetings,
notes, and conversations stay on your Mac — the only network calls are on-device model
downloads, update checks, and the opt-in features you explicitly enable (web search and
external AI providers).

This repository contains the full Logue app source: the LLM engine, recording pipeline,
agentic AI chat, writing editor, and test suites. [Bitwize](https://bitwize.ai) builds
Logue for professionals and students who want the full power of AI without sacrificing
privacy.

New here? Read [CONTRIBUTING.md](CONTRIBUTING.md) to get set up and learn the standards
every pull request follows.

## Table of contents

- [✨ Features](#-features)
- [🖼 Screenshots](#-screenshots)
- [📥 Install (users)](#-install-users)
- [🚀 Build from Source](#-build-from-source)
- [⚙️ Configuration](#-configuration)
- [📚 Documentation](#-documentation)
- [🗺 Project Layout](#-project-layout)
- [👏 Contributing](#-contributing)
- [❓ FAQ](#-faq)
- [📄 License](#-license)

## ✨ Features

### 🏠 One Place to Start

- **Home is the assistant** — Home and Ask Logue used to be two screens doing one job; they are now a single landing surface. Your day, what needs attention, what to pick back up, and a prompt bar that becomes the conversation without navigating away
- **Needs Attention** — overdue tasks and loose ends from recent meetings, surfaced before you go looking for them
- **Continue where you left off** — recent documents and meetings as cards, each able to hand its own question straight to the prompt bar
- **Suggestion chips drawn from your workspace** — the starter questions are built from what is actually in your library, not a canned list

### 🎙 Meeting Intelligence

- **Real-time transcription** — powered by Apple's `SpeechTranscriber` (macOS 26+), streaming audio directly with no buffering delays
- **Speaker diarization** — identifies and labels individual speakers using FluidAudio's Sortformer model, with a batch fallback for accuracy
- **System audio capture** — records mic and system audio simultaneously via ScreenCaptureKit; no meeting bot joins your call
- **Recordings that survive the worst** — unplug a headset mid-call, mute for ten minutes, or quit the app outright: the recording keeps its place on the meeting's timeline and the transcript is rebuilt when Logue reopens, instead of ending where the trouble started
- **Smart Minutes** — generates structured summaries with key decisions, themes, and follow-ups
- **Smart transcript highlights** — AI automatically extracts the most important moments; manual bookmarks are always preserved
- **Action item extraction** — pulls tasks, owners, and due dates from the transcript automatically
- **Meeting prep briefing** — AI-generated context brief before a meeting starts, based on linked documents and prior notes
- **Meeting ↔ Document links** — bidirectional links between meetings and related documents with back-link chips in the editor

### 🤖 Ask Logue — Agentic AI Chat

- **The same assistant in every window** — the Command Center island you summon over whatever app you are in runs the same agent as the main window: the same tools, the same memory, the same attachments, web search and Deep Research. Which window you asked from no longer decides what Logue can do, and **Open in Logue** hands the thread to the main window whenever you want the room to think in
- **Multi-step agentic reasoning** — powered by LangGraph-Swift; plans, reasons, and executes multi-step workflows
- **A real toolbox** — documents and spaces, meetings, semantic search, Calendar, Reminders, Contacts, files, email, web search, diagrams, slides and exports, with an approval gate in front of anything destructive
- **Streaming responses** — live token-by-token output with animated indicators
- **Inline diagrams & LaTeX** — renders Mermaid diagrams and math expressions directly in the chat thread
- **Deep research mode** — progress tracking for long-running multi-source research tasks, on either surface
- **Tool execution UI** — shows exactly what actions the agent took, paired with the results that answered them
- **Sources panel** — lists every document and meeting the agent consulted
- **Persistent memory & history** — the agent remembers context across conversations, all searchable

### 🌐 Logue in Your Browser

- **A Logue extension for Chrome** — the same chat and writing tools, in any tab. Ask about the page you are on and it is answered by the model running on this Mac. Install it from the [Chrome Web Store](https://chromewebstore.google.com/detail/logue/gaegipceeccdchdffamdphfiegfeenhc)
- **The page never leaves your machine** — the extension talks to Logue over a bridge bound to your Mac's loopback address only, so nothing off the machine can reach it. There is no account and no server in the loop
- **Visible and revocable** — Home says plainly when the bridge is listening and carries the switch to stop it; the same switch lives in Settings → Privacy

### ⌨️ Beyond the App Window

- **Inline assistant (⌘⌃I)** — rewrite, fix or continue text in whatever app you are typing in, via the Accessibility API
- **Command Center island** — a global hotkey summons the assistant as a floating pill over any app; drop files onto it, and it stays in front while it holds a conversation
- **Menu bar companion** — start an online or in-person meeting, or open Ask Logue, without switching to the app

### ✅ Tasks & Action Items

- **A real task list** — action items Logue finds in a meeting land in Tasks with due dates, priorities and tags, alongside anything you add yourself
- **Natural-language entry** — typing `Send the deck tomorrow #launch !` files itself: due date, tag and priority parsed out of the sentence
- **Triage, not a second list** — a meeting's extracted action items are triaged into tasks you can actually work, and the meeting shows which of its items became one
- **Filters, search and an overdue badge** — All / Pending / Overdue / Today / This Week / Completed, searchable by title, tag and notes, with a live overdue count in the sidebar

### ✍️ AI Writing Editor

- **Block-based rich text editor** — built on `NSTextView` with full SwiftUI integration
- **Grammar & clarity suggestions** — inline AI-powered suggestions with one-tap acceptance
- **Tone analysis** — detects and adjusts the tone of selected text
- **Vocabulary enhancement** — suggests richer alternatives, validated against the actual document content
- **Rewrite & review panels** — rewrite selected passages or get structural feedback on the whole document
- **Fact verification** — flags claims that may need a source
- **Table support** — full table creation, editing, and context menus inside the editor
- **Writing goals** — set and track word count, reading level, and tone targets
- **Wiki links & backlinks** — type `[[Document Name]]` to link documents; links show the target's real name, are clickable, survive renames, and every document lists what links back to it
- **Properties & relationships** — give documents typed fields (text, number, date, select, checkbox) and named links to other documents, all editable in a side panel
- **Saved views & inbox** — save any filter as a sidebar entry, and triage unfiled documents from an inbox with keyboard-driven bulk actions
- **Import markdown files and whole vaults** — right-click a space → Import…; a vault arrives as a tree, with subfolders becoming sub-spaces and frontmatter surviving as document properties
- **Plain markdown storage (opt-in)** — store documents as ordinary `.md` files in `~/Logue` instead of encrypted storage, and edit them in any editor, track them in git, or point an agent at them. The folder is the storage, not a copy: edits, new files, renames, moves and deletions flow both ways, and folders map to spaces including nested ones. Off by default, and Logue explains the encryption you give up before turning it on

### 🔍 Search & Discovery

- **Unified ⌘K search** — searches across documents, meetings, and action items in one keystroke, with keyword-centered snippets
- **Quick open (⌘P / ⌘O)** — a flat, title-ranked list filtered on every keystroke, separate from the ⌘K command palette
- **Full-text search (FTS5)** — fast, ranked full-text search across all meeting transcripts and document bodies

### 🔒 Privacy & Security

- **On-device AI by default** — inference, transcription, and diarization run locally via MLX on Apple Silicon; no content is sent to any cloud service unless you opt into web search or an external AI provider
- **AES-256-GCM encryption at rest** — meetings, transcripts, audio and documents are encrypted on disk. Documents are the one thing you can opt out of, by turning on plain markdown storage; meeting data is always encrypted
- **The Privacy tab lists what leaves this Mac, route by route** — including the routes you cannot turn off, rather than describing encryption and stopping there
- **No account required** — download and start working; there's no sign-up, no telemetry gate, no cloud dependency
- **Hardened Runtime, notarized, not sandboxed** — Logue ships Developer ID signed and notarized with the Hardened Runtime on. It is deliberately **not** sandboxed: a sandboxed process cannot be an Accessibility API client, so macOS never lists it under Privacy & Security → Accessibility, which silently disables the inline assistant, global hotkeys and Command Center. Every entitlement exception is documented in the entitlements files

## 🖼 Screenshots

| Ask Logue — the agent, its tools and its sources | Tasks, triaged out of a meeting |
| :---: | :---: |
| ![Ask Logue answering with tool calls and a sources panel](docs/images/ask-logue.png) | ![Action items from a meeting triaged into the task list](docs/images/tasks.png) |

| Meeting transcription + Ask Logue | Smart Minutes |
| :---: | :---: |
| ![Meeting transcription with speaker labels and AI chat](docs/images/meeting-transcription.png) | ![Smart Minutes with key decisions and action items](docs/images/smart-minutes.png) |

| AI writing editor with fact-checking | On-device PII detection |
| :---: | :---: |
| ![Writing a legal document with claims flagged for a source](docs/images/writing-editor.png) | ![PII detection flagging patient identifiers in a document](docs/images/pii-detection.png) |

| The Chrome extension — the same assistant, answered by the model on this Mac |
| :---: |
| ![The Logue Chrome extension answering a question about the open tab](docs/images/chrome-extension.png) |

## 📥 Install (users)

**Requirements:** macOS 26.0 (Tahoe) or later on Apple Silicon (M1 or newer).

1. Download the latest `Logue-<version>.dmg` from the [**Releases**](https://github.com/bitwize-ai/Logue/releases/latest) page.
2. Open the DMG and drag **Logue** into your **Applications** folder.
3. Launch it. On first run, macOS Gatekeeper may prompt — right-click the app → **Open**.

**Browser extension (optional).** Install [Logue for Chrome](https://chromewebstore.google.com/detail/logue/gaegipceeccdchdffamdphfiegfeenhc)
to ask about the page you are on. It talks to the Logue app over your Mac's loopback
address — the page never leaves your machine, and there is no account or server involved.

**Updates** are delivered in-app via Sparkle: Logue checks the GitHub-hosted feed on
launch and prompts you to install new versions. Updating only replaces the app —
your meetings, documents, and downloaded models are stored separately and are never
touched. To update manually, download the newest DMG and drag it over the old app.

## 🚀 Build from Source

**Prerequisites:** macOS 26.0+ (Tahoe) on Apple Silicon, Xcode 26+ (it ships the macOS 26 SDK required by `SpeechTranscriber`), and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

**1. Clone with submodules** (vendored dependencies live under `Vendor/`):

```bash
git clone --recurse-submodules https://github.com/bitwize-ai/Logue.git
cd Logue
```

**2. Download the Metal toolchain** (one-time; required by MLX):

```bash
xcodebuild -downloadComponent MetalToolchain
```

**3. Install tooling and generate the Xcode project:**

```bash
brew install xcodegen swiftformat swiftlint
xcodegen generate
```

**4. Build and run** — open in Xcode and hit **Run**, or from the CLI:

```bash
# The signing flags let you build without an Apple Developer account.
xcodebuild build -project Logue.xcodeproj -scheme Logue -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
open Logue.xcodeproj
```

> Already cloned without submodules? Run `git submodule update --init --recursive`.
> Re-run `xcodegen generate` whenever you add/remove `.swift` files or edit `project.yml`.

Dev builds use ad-hoc signing with the sandbox off — no Apple Developer account
needed just to build and run. (In Xcode, if the build stops at signing, either
pick your team under **Signing & Capabilities** or use the CLI flags above.) Full linting and git-hook setup are in
[`docs/dev-setup.md`](docs/dev-setup.md).

## ⚙️ Configuration

Logue runs fully on-device out of the box — **no keys or accounts are required** to
build, run, or use it. Everything below is optional and only relevant if you fork
the project or cut your own signed releases. Nothing is hardcoded to secrets: all
credentials are read from your own environment / GitHub Actions secrets.

**Optional external AI providers.** Alongside the on-device MLX models, you can add
OpenAI-/Anthropic-compatible or OpenRouter/Ollama/LM Studio endpoints under
**Settings → Models**. Keys are entered in-app and stored in your macOS Keychain —
never in the repo.

**Running your own signed builds / releases.** To ship notarized builds under your
own identity, set these as **GitHub Actions repository secrets** (the release
workflow reads them — none are committed):

| Secret | Purpose |
| --- | --- |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_CERTIFICATE_BASE64` / `APPLE_CERTIFICATE_PASSWORD` | "Developer ID Application" cert (base64 `.p12` + password) |
| `APPLE_ID` / `APPLE_APP_PASSWORD` | Apple ID + app-specific password for notarization |
| `SPARKLE_PRIVATE_KEY` | EdDSA key that signs auto-update ZIPs |

For a signed fork you'll also want to change, in [`project.yml`](project.yml):

- the **bundle identifier** (`PRODUCT_BUNDLE_IDENTIFIER`, default `com.bitwize.logue`);
- the **iCloud container identifiers** (`iCloud.com.bitwize.logue`) in
  [`Logue.entitlements`](Logue/Resources/Logue.entitlements) — these are tied to your Apple
  Developer account, so point them at a container you own if you want iCloud sync (or remove
  them). The shipped **release** entitlements don't include iCloud, so signed release builds
  aren't affected;
- to run your own update channel, `SUFeedURL` + `SUPublicEDKey`.

Building and running unsigned dev builds needs none of the above. See
[`docs/dev-setup.md`](docs/dev-setup.md) and
[`docs/SPARKLE_UPDATE_FLOW.md`](docs/SPARKLE_UPDATE_FLOW.md).

## 📚 Documentation

- [Developer Setup](docs/dev-setup.md)
- [Contributing Guide](CONTRIBUTING.md)
- [Sparkle Update Flow](docs/SPARKLE_UPDATE_FLOW.md)
- [Scripts Reference](scripts/README.md)
- [Security Policy](SECURITY.md)

## 🗺 Project Layout

- [`Logue/`](/Logue) — Main Swift source; SwiftUI + AppKit application target.
- [`Logue/Engine/`](/Logue/Engine) — LLM inference actor, prompt builders, and retry helpers. All AI logic lives here.
- [`Logue/Agent/`](/Logue/Agent) — Ask Logue: the agent graph, run state, routing, Deep Research, and the tools the agent can call.
- [`Logue/CrossApp/`](/Logue/CrossApp) — Everything outside the app window: the Command Center island, inline assistant, global shortcuts, and menu bar companion.
- [`Logue/Services/`](/Logue/Services) — Recording pipeline, transcription, speaker diarization, encryption, document storage, the browser bridge, and scheduling services.
- [`Logue/Views/`](/Logue/Views) — All SwiftUI views: Meeting workspace, Writing editor, Ask Logue chat, Action items, Settings, and more.
- [`LogueTests/`](/LogueTests) — Swift Testing suites (`@Suite`, `@Test`), including real-inference LLM integration tests.
- [`Vendor/`](/Vendor) — Vendored git submodule dependencies — no remote access required at build time.
- [`docs/`](/docs) — Developer setup and release documentation.
- [`scripts/`](/scripts) — Release build script, Sparkle appcast updater, and export options plist.

## 👏 Contributing

Contributions are welcome! Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup and the
security, concurrency, and SwiftLint standards enforced on every pull request. The full,
always-current ruleset the project builds against lives in [CLAUDE.md](CLAUDE.md).

Found a bug or have an idea? [Open an issue](https://github.com/bitwize-ai/Logue/issues).

## ❓ FAQ

Have questions about using Logue? Check the [FAQ on our site](https://bitwize.ai/#faq),
or email us at [support@bitwize.ai](mailto:support@bitwize.ai).

## 📄 License

Logue is open source under the [MIT License](LICENSE) — © 2026 [Bitwize](https://bitwize.ai).

Some vendored dependencies under [`Vendor/`](/Vendor) are licensed separately (MIT, BSD,
Apache-2.0); see each package for details.
