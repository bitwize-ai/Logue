# Tasks and AI Triage — Design

**Date:** 2026-08-12
**Status:** proposed
**Related:** `docs/CAPABILITY-ROADMAP.md` (Phase 2 machinery, Phase 4 files-first foundation)

---

## 1. The problem

Logue extracts action items from meetings and then has nowhere to put them.

`ActionItem` exists, but it is:

- **meeting-owned** — it is a field on `MeetingNote`, so it cannot exist without a meeting;
- **unreachable** — there is no UI anywhere in the app that creates one, only the LLM
  summariser writes them;
- **thin** — title, assignee, due date, reminder. No priority, no tags, no repetition;
- **locked in** — it lives inside the always-encrypted meeting store, so it is never a
  file, never editable outside the app, and never visible to anything files-first.

So a user records a meeting, Logue correctly pulls out "Send the revised deck to
Priya by Friday", and that sentence's entire future is a checkbox on a meeting detail
screen. It cannot be re-prioritised, it cannot repeat, it does not appear next to the
work the user gave themselves, and it cannot be edited in the folder the app just
promised them was the source of truth.

The gap is not "Logue needs a to-do list". It is that **the app's best output has no
destination**.

## 2. What we are building

A first-class `TaskItem` that a user owns, stored the same way documents are stored —
plain `.md` with YAML frontmatter when markdown storage is on, encrypted JSON
otherwise — plus:

1. Natural-language capture: `Send the deck tomorrow #launch !`
2. Repetition: completing a repeating task reopens it at the next due date.
3. A Tasks surface in the sidebar, with the filter/sort vocabulary the action-item
   dashboard already established.
4. **Promotion**: a meeting action item becomes a real task, keeping a link back to
   the meeting it was decided in.
5. **Triage**: the on-device model reviews open tasks and proposes changes — wrong
   priority, missing due date, untagged, stale, duplicated — which the user applies
   one at a time. Triage never writes.

## 3. What we are deliberately not building

| Not doing | Why |
| --- | --- |
| A `logue` CLI | Belongs with the MCP server in Phase 6 agent interop, and deserves its own spec. |
| Daily journal / today note | Independent of tasks; own spec. |
| Adopting hand-created task files | A `.md` dropped into `Tasks/` without `_logue_task_id` is left alone and logged. Document adoption took a settle-timer and a stamping pass to get right (`AppConstants.Delays.adoptionSettleSeconds`); tasks can inherit that later. |
| Assignees | `ActionItem.assignee` is meaningful because a meeting has attendees. A personal task list has one person in it. Carried across on promotion into the notes body, not modelled. |
| Reminders / notifications | `ReminderManager` already does this for action items. Wiring tasks in is a follow-up, not part of the model. |

## 4. Model

### 4.1 Why a new entity

Three options were considered.

| Option | Verdict |
| --- | --- |
| Reuse `WritingDocument` with a built-in "Task" type | Rejected. A `WritingDocument` carries body, score, review grade, fact checks, PII findings, vocabulary suggestions, rewrite results and chat messages. That is a very heavy object to represent one sentence, and every task would then appear in document lists, the link graph, and search results as a document. |
| Extend `ActionItem` in place | Rejected. It keeps tasks inside the always-encrypted meeting store — never files, never externally editable — which is the opposite of the direction Phase 4 committed to. |
| **New `TaskItem` + `TaskStore` + `TaskStorage`** | **Chosen.** Small, mirrors the `DocumentStore` / `DocumentStorage` split exactly, and leaves `ActionItem` untouched as the meeting-derived thing it already is. |

### 4.2 Shape

```
TaskItem
  id                UUID
  title             String
  status            .todo | .done
  priority          .low | .medium | .high
  dueDate           Date?          — day precision, start-of-day
  tags              [String]
  spaceID           UUID?
  recurrence        TaskRecurrence?
  createdAt         Date
  updatedAt         Date
  completedCount    Int            — how many times a repeating task has been done
  sourceMeetingID   UUID?          — set on promotion
  notes             String         — markdown body
```

### 4.3 Vocabulary: tags and spaces, not "projects"

The reference implementation groups tasks by a `#project` string. Logue already has
**two** grouping concepts — `Space` and `tags` — and adding a third would mean three
ways to say the same thing.

So `#launch` in quick capture becomes a **tag**, matching how documents already work,
and a task can additionally belong to a **space**. Triage's grouping suggestion
proposes an existing tag rather than inventing a project name.

### 4.4 Priority marker: an intentional deviation

The reference implementation reads a trailing `!` as **low** priority and `!!` as
high. That is a surprising mapping — a person typing `!` almost always means urgent.

Logue reads **any trailing run of `!` as high priority**. Low priority is set from the
UI or by triage, not from text. One marker, one obvious meaning.

## 5. Storage

`TaskStorage` mirrors `DocumentStorage`, and follows the same mode:

| `DocumentStorage.mode` | Tasks live in |
| --- | --- |
| `.encrypted` | `Application Support/Logue/tasks/<uuid>.json`, AES-256-GCM |
| `.markdown` | `~/Logue/Tasks/<slug>-<short-id>.md`, plain |

Tasks follow the document mode rather than having a mode of their own. Two independent
switches would let a user end up with plaintext tasks beside encrypted documents, which
is a privacy posture nobody chose deliberately.

### 5.1 File format

```md
---
_logue_task_id: 3F2A…-…
title: Send the revised deck to Priya
status: todo
priority: high
due: 2026-08-14
tags:
  - launch
recur: 1w
created: 2026-08-12T09:15:00Z
updated: 2026-08-12T09:15:00Z
completed_count: 0
meeting: 91BC…-…
---

Priya wants the pricing slide split in two.
```

Rendering rules are inherited from `MarkdownDocumentFile`: fixed key order, stable
list order, empty values omitted, so the same task always produces identical bytes.
These files may be tracked in git.

Reading is tolerant — an unrecognised key is ignored, a malformed date falls back —
with one strict requirement: **a file without a parseable `_logue_task_id` is not a
task.** Inventing an identifier risks attaching a file to the wrong record.

### 5.2 The folder collision — the one real hazard

`MarkdownFolderScan` walks `~/Logue` and reads every directory as a **space** and
every `.md` as a **document**. Dropping a `Tasks/` folder into it, unchanged, would
produce a phantom "Tasks" space in the sidebar containing one document per task.

The fix follows the invariant the codebase already states — *a folder is found by its
identity, never by recomputing a path from its name*:

- `~/Logue/Tasks/` contains a marker file `_tasks.md` holding `_logue_tasks_folder: <uuid>`,
  exactly as `_space.md` holds `_logue_space_id`.
- `FolderSnapshot` computes which directories carry that marker and excludes them from
  both `documentFiles` and a new `spaceDirectories`.
- Exclusion is by marker **presence**, not by name. Renaming the folder in Finder keeps
  tasks working and keeps them out of the document library. A second marker-bearing
  folder is also excluded — being conservative about what counts as a document is the
  safe direction — and its tasks are read too, deduplicated by identifier with the
  first sorted path winning, and logged. That matches the existing
  `duplicatedDocumentFiles` precedent.

This is the only change to existing scan behaviour, and it is additive: with no
`Tasks/` folder present, every scan behaves exactly as it does today.

## 6. Recurrence

Stored as a unit and a bounded count (`1d`, `2w`, `3m`), never a free string — an
unparseable recurrence would either never reopen the task or reopen it forever. The
interval is clamped to 1…365 on construction.

Completing a repeating task does not create a second task. It rewrites the same one:
`status` stays `todo`, `dueDate` advances from the **old due date** (not from today, so
a weekly task completed three days late stays on its original weekday), and
`completedCount` increments.

## 7. Promotion

`ActionItem` → `TaskItem` is a one-way copy, not a move. The action item stays on the
meeting and stays checkable there; the task is the thing that then has a life.

- `title`, `dueDate`, `isCompleted` carry across.
- `assignee` and `dueDescription`, which have no field on `TaskItem`, are written into
  the task's `notes` body so nothing the model extracted is silently dropped.
- `sourceMeetingID` is set, giving the task a link back via the existing `logue://`
  deep-link scheme.
- Promotion is **idempotent**: re-promoting an action item that already has a task
  updates that task rather than creating a duplicate. Without this, a user pressing
  "Add all to Tasks" twice — which they will — doubles their list.

## 8. Triage

The model reads the open tasks and returns suggestions. It never applies them.

**Kinds:** `priority`, `due`, `tag`, `stale`, `duplicate`.

**The safety gate is the parser, not the prompt.** A suggestion is discarded unless it
survives validation:

- `taskId` resolves to a currently-open task in the batch that was sent;
- `kind` is one of the five;
- the `apply` patch contains exactly one whitelisted field, of the right type
  (`priority` an enum case, `due` a valid `yyyy-MM-dd` that is not in the past,
  `tag` matching the tag charset and length, `status` only ever `done`);
- `duplicate` carries no patch at all — the user decides which of two tasks dies.

An LLM that returns `{"apply": {"title": "…"}}` or a due date in 1970 changes nothing,
because those fields never reach a task.

### 8.1 Prompt construction rules

These are project standards, restated because triage is a new prompt site:

- The task list is serialised as JSON and wrapped in `<tasks>…</tasks>`.
- Titles are sanitised before serialisation — truncated, newlines and NUL stripped.
- Input is truncated to `LLMEngine.maxInputChars(reservedTokens:)`.
- The call routes through `LLMEngine.complete()`, never a session directly.
- Batch capped at 60 open tasks; the count actually sent is reported to the user, so a
  truncated review never reads as a complete one.
- The triage button is disabled while `LLMEngineStatus.shared.isBusy`.

## 9. Success criteria

1. A task created in the app appears as a readable `.md` in `~/Logue/Tasks/`, and a
   task edited in another editor is picked up by the app.
2. No `Tasks/` folder ever appears as a space, and no task file as a document.
3. Turning markdown storage off moves tasks back into encrypted storage without loss;
   turning it on writes every task out first.
4. Completing a weekly task reopens it seven days after its previous due date.
5. Promoting the same action item twice yields one task.
6. A malformed or malicious triage response changes nothing.
