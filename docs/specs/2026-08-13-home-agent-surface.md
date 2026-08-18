# Home as an agent surface

**Status:** design approved, not yet implemented
**Date:** 2026-08-13

## Summary

Logue has two landing surfaces that compete for the same job. `Home` (`SidebarItem.overview`)
is a scrolling dashboard of time-sensitive cards. `Ask Logue` (`SidebarItem.agentChat`) is a
ChatGPT-shaped agent with a full tool layer. They sit next to each other in the sidebar, and
the app already skips the first one — `MainWindowView` defaults new installs to `.agentChat`.

This design merges them into one surface. The prompt box is the primary action; the dashboard
cards sit beneath it and teach the prompt what to say. Sending a message takes the surface over
in place.

## Who this is for

Logue has no sync, no sharing, and no team surface anywhere in the codebase. Everything is
encrypted on one Mac. The user is a single professional or student who both *meets* and
*writes*, and who chose Logue specifically because their recordings cannot go to a vendor's
cloud. By the time they reach Home they have already downloaded a multi-GB local model and
granted Screen Recording and Accessibility — a high-intent install.

Two consequences shape every decision below:

- **There is no activity feed**, because nobody else acts in this workspace. The only forces
  that can organise a personal home are the clock (what is next, what is overdue) and the
  user's own trail (what they left open). The existing `HomeAttentionCard` and
  `HomeContinueSection` are already exactly these two axes.
- **The cold start is the weak moment.** A surface that personalises has nothing to
  personalise on day one, which is precisely when the user is most sceptical.

## Why the cards stay

The prompt box alone is a known failure mode, not minimalism. Nielsen Norman Group calls the
underlying problem the *articulation barrier*: before a user can type anything they must know
what the system can do, decide what they want, and then phrase it. Three walls before any
value. The cards are the signifiers that knock those walls down — and unlike generated prose,
they cost no inference and cannot be wrong.

The same research says suggestions are ignored when generic and used when specific. So every
suggestion on this surface is derived from the user's real data: their meeting titles, their
overdue items. Never "Try asking about your meetings."

Microsoft's May 2026 Copilot redesign converged on the same shape — an expandable prompt
surface with, in their words, tools and controls surfaced *below it* to assist with the task at
hand.

## Section 1 — Information architecture

One sidebar item. `.overview` is deleted, `.agentChat` is renamed `.home`, and
`CategorySidebarView` keeps a single `Label("Home", systemImage: "house")` where the two rows
used to be.

The change is contained: 12 `.overview` references and 11 `.agentChat` references, all but two
inside `MainWindowView.swift`.

| Site | Change |
| --- | --- |
| `MainWindowView.swift:356-359` | `case .home, nil:` renders `AgentChatView()`; the `OverviewView` case is removed |
| `MainWindowView.swift:484-485` | Both titles collapse to `"Home"` |
| `MainWindowView.swift:514` | Command-palette "Home" entry targets `.home` |
| `MainWindowView.swift:189-190` | Analytics tab names `"overview"` and `"agent_chat"` collapse to `"home"` |
| `MainWindowView.swift:596-597` | Decoder maps `"overview"`, `"agentChat"` and `"home"` all to `.home` |
| `MainWindowView.swift:615-616` | Encoder writes `"home"` |
| `MainWindowView+Navigation.swift:97` | `case nil: .home` |
| `SpaceTreeRow.swift:239` | `selection = .home` |

The decoder migration is not optional. An existing user whose last surface was Home has
`"overview"` written to disk; an unmapped string would silently land them somewhere else on
first launch after upgrade.

**Deliberate side effect.** ⌘L (`MainWindowView.swift:134-139`) creates a new conversation and
selects the surface. After the merge a new conversation *is* the landing state, so ⌘L becomes
"go Home". That is the right meaning for it. ⌘⇧L continues to focus the input without clearing
the thread.

`OverviewView.swift` is deleted. Its three non-card responsibilities relocate:

- `timeOfDay` → the landing greeting
- `startQuickRecording` / `stopQuickRecording` / `HomeRecordingBanner` → `HomeLandingView`
- `welcomeState` → the cold-start branch (Section 4)

## Section 2 — The landing layout

`AgentChatView.body` already branches on `hasMessages`. That branch is untouched; only the
empty side is rebuilt.

```
VStack(spacing: 0) {
    HomeLandingHeader()        // greeting, context pills, suggestion chips
    inputBar                   // .matchedGeometryEffect — unchanged
    ScrollView { HomeLandingCards(onAsk:) }
}
```

**The prompt bar is pinned; only the cards scroll.** Anchoring the input inside the scroll view
would make its frame move as the user scrolls, and `matchedGeometryEffect` would tear during
the slide-to-bottom animation on first send. Pinning it also matches the Copilot shape.

Card order is time first, trail second:

1. `HomeRecordingBanner` — only while quick-recording, as a `safeAreaInset`, as today
2. `SeedDataBannerView`
3. **Needs Attention** — upcoming calendar events and overdue action items
4. **Continue Where You Left Off**
5. **Quick Actions** — Voice Note / New Meeting / New Document
6. **Daily Digest**

All four existing sections read their own `@Environment` stores and already self-hide when
empty, so they re-host into the new parent with no data-layer changes.

`HomeContextBar` does not survive as its own row. It is a one-line pill summary ("2 meetings
today · 3 overdue") that reads as a subtitle, so it moves into the header directly beneath the
greeting. Same information, one less section, and it stops competing with Needs Attention,
which says the same thing louder.

**New files**, which keep `AgentChatView.swift` (447 lines today) under the project's
extension-file guidance:

- `Logue/Views/Home/HomeLandingView.swift` — header and card stack; owns quick-recording state
- `Logue/Views/Home/HomeAskAffordance.swift` — the sparkle button and its hover/focus treatment
- `Logue/Engine/HomeAskPrompts.swift` — pure prompt composition (Section 3)

`AgentChatView` gains a single method, `prefill(_ text: String)`, which sets `inputText` and
focuses the field. That is the entire bridge between the two halves.

**Window title.** The landing state shows `"Home"`; the greeting lives in the content hero, not
the titlebar. Once a thread starts the title becomes the conversation title, exactly as today.

## Section 3 — The ask affordance

Every card row that represents a concrete object — a meeting, a document, an action item, a
calendar event — gains an optional `onAsk: (() -> Void)?`. When non-nil a sparkle button
renders: revealed on hover, but always present for keyboard focus and VoiceOver, never
hover-only.

Clicking it composes a prompt and calls `prefill(_:)`. **It does not send.** The user sees a
concrete, editable sentence appear in the input box. The card teaches the prompt; the user
stays in control of it. Primary click on the card body still does the literal thing — open the
meeting, open the document, join and record — so no existing navigation path is lost.

Composition lives in `HomeAskPrompts.swift` as pure functions with no view or store
dependency, which is what makes them testable:

| Object | Prompt |
| --- | --- |
| Meeting, unsummarized | `Summarize the meeting "<title>" and pull out the action items.` |
| Meeting, already summarized | `What were the decisions in "<title>"?` |
| Document | `Help me continue writing "<title>".` |
| Action item | `What do I need to do for "<title>", and what is the context from the meeting it came from?` |
| Calendar event | `Prepare me for "<title>" — what happened last time and what is still outstanding?` |

**Sanitization.** Titles are user content, so they are truncated to 120 characters and stripped
of newlines and control characters using the project's standard pattern:
`String($0.prefix(120)).filter { !$0.isNewline && $0.asciiValue != 0 }`. Empty or
whitespace-only titles fall back to "Untitled meeting" / "Untitled document".

Titles are **not** wrapped in XML delimiters here, and that is a deliberate departure worth
flagging to a reviewer. The XML rule exists for injecting content *blocks* into prompts —
transcripts, document bodies, PII category lists — where the boundary between instruction and
content must be unambiguous. What this produces is an ordinary user message containing a quoted
title, byte-identical to something the user could have typed by hand, and delimiters would be
visible in the input box. Sanitization is what actually matters here: it stops a document
titled with embedded newlines from restructuring the message.

No inference is triggered by the sparkle, so it is **not** gated on
`LLMEngineStatus.shared.isBusy`. Filling a text field during inference is harmless; the send
button is already disabled by the existing input-bar handling.

## Section 4 — Cold start and degraded states

The landing must answer four states.

**1. Stores still loading.** `ContentLoadingView()`, and the `isLoaded` guard from
`OverviewView` is preserved verbatim. The comment already in that file states the invariant:
a returning user must never be greeted as a new one because their library was still being read.
That is the loudest possible wrong answer this surface can give.

**2. Empty workspace (first run).** Every card self-hides, which would collapse the landing to
a bare prompt box — exactly the failure this design set out to avoid. So the empty case is
explicit rather than emergent: the hero centres vertically, and the card area is replaced by a
starter card carrying the three actions from the old `welcomeState` (Record a Meeting, Write a
Document, Create a Space) alongside capability-teaching suggestion chips.

**3. No model installed, or still downloading.** The agent cannot answer, so the landing must
not promise it. A compact inline notice sits above the input — "Set up a model to ask Logue",
opening Settings → Models. Cards stay fully functional: navigation never depends on the model.

**4. Warm workspace.** The layout described in Section 2.

**Suggestion chips** are derived from real data with no inference, capped at three, in a fixed
order so they do not flicker between renders:

1. If an unsummarized meeting exists → `Summarize "<most recent unsummarized meeting>"`
2. If overdue action items exist → `What's overdue?`
3. If meetings happened today → `What did I miss today?`
4. Fallback, always available → `What can you do?`

## Section 5 — Testing and verification

Swift Testing (`@Suite` / `@Test` / `#expect`). This work is pure logic plus views, so it needs
no LLM integration coverage.

`LogueTests/HomeAskPromptsTests.swift`

- newlines and control characters are stripped from titles
- titles truncate at 120 characters
- empty and whitespace-only titles produce the fallback label
- each prompt variant contains the sanitized title and its expected verb
- an unsummarized meeting and a summarized meeting produce different prompts

`LogueTests/SidebarItemPersistenceTests.swift`

- `"overview"`, `"agentChat"` and `"home"` all decode to `.home`
- an unrecognised string decodes to `nil`
- `.home` round-trips through encode → decode

**Manual verification**, following the launch rules in `CLAUDE.md` (resolve
`BUILT_PRODUCTS_DIR`, `pkill -x Logue`, exec the binary directly, confirm by process):

- the landing renders with cards and a pinned prompt bar
- the sparkle fills the input without sending, and the text is editable
- the first send animates the input bar to the bottom without tearing
- ⌘L returns to the landing state; ⌘⇧L focuses the input without clearing the thread
- with `"overview"` written to the stored-selection key, a relaunch lands on Home

`xcodegen generate` is required — three files are added.

## Risks

- **The `matchedGeometryEffect` transition** is the one real visual risk. The source frame moves
  from "pinned below a header" to "pinned above the bottom edge", a larger distance than today's
  centred-to-bottom animation. Verify in the running app, not only in a mockup.
- **`HomeLandingView.body` must stay within the 60-line function-body limit**, so it composes
  from small subviews rather than growing one builder.
- **Deleting `OverviewView` removes the only caller of some `Views/Home` components.** Anything
  the landing does not re-host is dead code and should be deleted in the same change, not left
  orphaned.
