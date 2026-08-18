# Library Panels — Design

**Date:** 2026-08-13
**Status:** approved
**Related:** `docs/specs/2026-08-12-tasks-and-triage.md`, `docs/specs/2026-08-12-action-item-inbox-plan.md`

---

## 1. The problem

The left sidebar carries ten destinations, two of which do not earn a permanent row.

**Action Items** is a triage queue. Once it is empty — which is now its intended resting
state — a top-level row pointing at nothing is pure weight. It is also conceptually a lens
*on meetings* rather than a sibling of them.

**Templates** is something you reach for when starting a document, perhaps weekly. It sits
between "All Documents" and "Trash" as though it were a place you live.

Both belong *inside* the library surface they describe: action items are what meetings
produced; templates are what documents start from.

## 2. What we are building

Action Items and Templates leave the left sidebar and become on-demand right panels of
**All Meetings** and **All Documents** respectively, opened from a button in each surface's
header.

This is not a new pattern for the app. The meeting workspace already has a tabbed right
sidebar (`MeetingTool` + `IconToolbarView` + `UnifiedSidebarView`) with per-tool icons,
groups and widths — one of whose tools is already Action Items, scoped to one meeting. This
applies the same machinery one level up, at the library surfaces, where the scope is all
meetings.

After the change the left sidebar reads: Home · Ask Logue · Pinned · Recent · **Library**
(All Documents · All Meetings · Tasks) · Spaces · Trash · Settings.

**Tasks stays top-level.** It is the surface a user lives in and the destination triage
feeds; it is not a lens on something else.

## 3. What we are deliberately not building

| Not doing | Why |
| --- | --- |
| Panels on space surfaces | `DocumentListContentView` / `MeetingListContentView` are shared with spaces. The panels are wrapped at the routing site so the space path is untouched. A per-space action item lens is a separate idea. |
| Multi-tool panels | One tool each today. The enums exist so a second tool costs nothing later, but inventing tools to fill a tab bar would be building for an imagined future. |
| Removing the meeting workspace's own Action Items tool | That one is scoped to a single meeting and remains correct. The new one is the global inbox. |
| Deep links to the panels | `DeepLink` covers document / meeting / space only. Nothing links to these surfaces today. |

## 4. Design

### 4.1 The host wrapper

A generic `LibrarySurfaceView<Tool, Content, Panel>` composes:

- the existing content view, unchanged;
- a `UnifiedSidebarView` on the trailing edge, collapsed by default;
- a toolbar button that toggles it, carrying an optional count badge.

Reusing `UnifiedSidebarView` rather than hand-rolling a third panel buys drag-to-resize,
remembered widths and collapse behaviour that already work everywhere else.

### 4.2 Tools

```
MeetingsLibraryTool  — case actionItems   (icon "checklist",  width 340)
DocumentsLibraryTool — case templates     (icon "doc.on.doc", width 320)
```

Both conform to the existing `ToolbarTool`.

### 4.3 Badge support

`ToolbarTool` gains an optional `badgeCount` supplied by the host, so the Action Items icon
can carry the inbox number. This is where the "seven waiting to triage" signal lives once
the sidebar row is gone — the one thing the move would otherwise cost.

The count is the Inbox chip's count, through `ActionItemInbox.matches(_:mode:.inbox:)`, so
the badge and the panel cannot disagree.

### 4.4 Action Items panel

Always global: every undecided item across every live meeting, never scoped by what is
selected in the list behind it. Selecting a meeting in All Meetings navigates away to that
meeting, so there is no selection for the panel to follow.

Inside the panel:

- the Inbox / Dismissed / All chips, unchanged;
- a **meeting picker** narrowing to one meeting's items;
- search;
- the existing `ActionItemInboxRow`, which was already built for a narrow column.

Triage behaviour — promote, dismiss, restore, add-all — is unchanged. `ActionItemDashboardView`
becomes the panel's content; the full-screen surface goes away with the sidebar row.

### 4.5 Templates panel

The grid does not survive a 320pt column — `TemplateGalleryView` uses adaptive 200–280pt
columns over 55 templates, which collapses to a single column. So the panel is a purpose-built
compact list: small icon, name, category, with a category filter and search.

Clicking a row opens the existing `TemplatePreviewView` sheet, so create / edit / delete keep
working with no new surface.

A **Browse all** button at the foot of the panel opens `TemplateGalleryView` as a sheet. The
grid remains the better way to shop for a template; this keeps it reachable — and keeps 655
lines of working code — without a sidebar row.

### 4.6 Not stranding anyone

- **Persisted selection migrates.** `"actionItems"` resolves to All Meetings, `"templates"`
  to All Documents, each with its panel opened. Without this, anyone whose app last sat on
  either surface would launch into nothing.
- **⌘K keeps both entries**, now navigating to the host surface and opening the panel. With
  the visible rows gone, the palette is the discovery path, so removing the entries would
  make the features genuinely hard to find.
- The command palette's action-item *search results* are untouched; they resolve to meetings.

## 5. Testing

The honest testable core is the pure logic:

- legacy selection strings migrate to the right host surface;
- the panel's filter composes correctly across inbox mode × meeting filter × search;
- the badge count equals the panel's Inbox count for the same data.

Panel layout and resize behaviour are exercised by `UnifiedSidebarView` already and are not
re-tested here.

## 6. Consequences

- The left sidebar loses two rows; the inbox signal moves one level in, visible only once
  you are on All Meetings.
- The full-screen action item dashboard stops existing as a destination.
- Templates browsing is a list by default, with the grid one click away.
