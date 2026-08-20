# Action Item Inbox + Tasks Visual Parity — Implementation Plan

> **For implementers:** steps use checkbox (`- [ ]`) syntax for tracking. Work them in
> order; each task ends with an independently testable deliverable and a commit.

**Goal:** Turn Action Items from a second to-do list into a triage inbox that empties, and
bring the Tasks surface up to the app's established visual language.

**Architecture:** `ActionItem` gains a persistent `isDismissed` flag so an extracted item can
be rejected without lying about completion. A new pure `ActionItemInbox` type owns the
"what's still undecided" predicate and the chip counts, so the rule is testable without
SwiftUI — the same split `TaskFilter` already uses. The dashboard's due-date filter
vocabulary moves out (that slicing is the Tasks surface's job now) and is replaced by
Inbox / Dismissed / All. Nothing about promotion semantics changes: it stays a copy that
reuses the action item's UUID.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Testing (`@Suite` / `@Test` / `#expect`), XcodeGen.

**Spec:** `docs/specs/2026-08-12-tasks-and-triage.md` (sections 1–4 establish why `TaskItem`
and `ActionItem` are separate entities; this plan builds the surface split that follows from
it).

## Global Constraints

- Swift Testing only — `@Suite`, `@Test`, `#expect`. Never XCTest.
- `decodeIfPresent` with a default for every field that could be missing in older data.
  Bare `try container.decode()` on a new field breaks meetings written by earlier builds.
- No force unwrapping (`!`) or force casting (`as!`). SwiftLint `force_unwrapping` is on.
- Function bodies ≤ 60 lines, files ≤ 800 lines, lines ≤ 150 chars.
- Colors come from `AppThemeConstants` — never a raw `Color.red` in new view code.
- `xcodegen generate` after adding any new `.swift` file, or it is silently absent.
- Pure logic takes `now: Date` and `calendar: Calendar` as parameters, never `.now` /
  `.current` internally — the existing `TaskFilter` and `TaskRecurrence` rule.
- Build: `xcodebuild build -project Logue.xcodeproj -scheme Logue -destination 'platform=macOS'
  -derivedDataPath /tmp/logue-dd-tasks-and-triage
  -clonedSourcePackagesDirPath ~/Library/Developer/Xcode/DerivedData/Logue-SPM
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`

---

### Task 1: `ActionItem.isDismissed`

**Files:**
- Modify: `Logue/Models/ActionItem.swift`
- Test: `LogueTests/ActionItemInboxTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `ActionItem.isDismissed: Bool` (default `false`), settable via the memberwise
  init's new `isDismissed:` parameter placed after `isCompleted:`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
@testable import Logue
import Testing

@Suite("ActionItemInbox")
struct ActionItemInboxTests {
    /// An action item written before the dismissed flag existed must still decode.
    @Test("Action items from older builds decode with isDismissed false")
    func decodesLegacyActionItemWithoutDismissedKey() throws {
        let json = """
        {
          "id": "8B1F2C9E-4A6D-4E1B-9C3A-2F5D7E8A1B4C",
          "title": "Send the revised deck",
          "isCompleted": false,
          "createdAt": 776000000
        }
        """
        let data = try #require(json.data(using: .utf8))
        let item = try JSONDecoder().decode(ActionItem.self, from: data)
        #expect(item.isDismissed == false)
        #expect(item.title == "Send the revised deck")
    }

    @Test("A dismissed action item round-trips through Codable")
    func dismissedFlagRoundTrips() throws {
        let item = ActionItem(title: "Not a task", isDismissed: true)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ActionItem.self, from: data)
        #expect(decoded.isDismissed)
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run:
```bash
xcodebuild test -project Logue.xcodeproj -scheme Logue -destination 'platform=macOS' \
  -derivedDataPath /tmp/logue-dd-tasks-and-triage \
  -clonedSourcePackagesDirPath ~/Library/Developer/Xcode/DerivedData/Logue-SPM \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  -only-testing:LogueTests/ActionItemInboxTests 2>&1 | grep -E "^✘|Test run with|error:"
```
Expected: compile failure — `extra argument 'isDismissed' in call`. That is the failure;
the flag does not exist yet.

- [ ] **Step 3: Add the property**

In `Logue/Models/ActionItem.swift`, add the stored property after `isCompleted`:

```swift
    var isCompleted: Bool
    /// The user saw this and decided it is not something to act on.
    ///
    /// Separate from `isCompleted` because "I did it" and "this was never a task" are
    /// different claims, and recording the second as the first makes the meeting record lie.
    var isDismissed: Bool
```

Add the init parameter after `isCompleted`:

```swift
        isCompleted: Bool = false,
        isDismissed: Bool = false,
```

and the assignment `self.isDismissed = isDismissed` after `self.isCompleted = isCompleted`.

Add `isDismissed` to `CodingKeys`:

```swift
        case id, title, assignee, dueDescription, isCompleted, isDismissed, createdAt
```

and decode it with a default, next to the other optional-tolerant reads:

```swift
        isDismissed = try container.decodeIfPresent(Bool.self, forKey: .isDismissed) ?? false
```

- [ ] **Step 4: Run the test and confirm it passes**

Same command as Step 2. Expected: `Test run with 2 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add Logue/Models/ActionItem.swift LogueTests/ActionItemInboxTests.swift
git commit -m "feat: let an action item be dismissed without being marked done"
```

---

### Task 2: `ActionItemInbox` — the pure triage rule

**Files:**
- Create: `Logue/Models/ActionItemInbox.swift`
- Test: `LogueTests/ActionItemInboxTests.swift` (extend)

**Interfaces:**
- Consumes: `ActionItem.isDismissed` from Task 1.
- Produces:
  - `enum ActionItemInboxMode: String, CaseIterable { case inbox, dismissed, all }`
    with `displayName: String` and `symbolName: String`.
  - `enum ActionItemInbox` with
    `static func matches(_ item: ActionItem, mode: ActionItemInboxMode, isPromoted: Bool) -> Bool`
    and
    `static func counts(_ items: [ActionItem], isPromoted: (ActionItem) -> Bool) -> [ActionItemInboxMode: Int]`.

- [ ] **Step 1: Write the failing tests**

Append to `LogueTests/ActionItemInboxTests.swift`, inside the existing suite:

```swift
    // MARK: - Inbox rule

    private var pending: ActionItem { ActionItem(title: "Pending") }
    private var done: ActionItem { ActionItem(title: "Done", isCompleted: true) }
    private var rejected: ActionItem { ActionItem(title: "Rejected", isDismissed: true) }

    @Test("An undecided item is in the inbox")
    func undecidedItemIsInInbox() {
        #expect(ActionItemInbox.matches(pending, mode: .inbox, isPromoted: false))
    }

    @Test("A promoted item leaves the inbox")
    func promotedItemLeavesInbox() {
        #expect(!ActionItemInbox.matches(pending, mode: .inbox, isPromoted: true))
    }

    @Test("A dismissed item leaves the inbox and lands under Dismissed")
    func dismissedItemMovesToDismissed() {
        #expect(!ActionItemInbox.matches(rejected, mode: .inbox, isPromoted: false))
        #expect(ActionItemInbox.matches(rejected, mode: .dismissed, isPromoted: false))
    }

    @Test("A completed item is not awaiting a decision")
    func completedItemLeavesInbox() {
        #expect(!ActionItemInbox.matches(done, mode: .inbox, isPromoted: false))
    }

    @Test("All shows everything regardless of state")
    func allShowsEverything() {
        for item in [pending, done, rejected] {
            #expect(ActionItemInbox.matches(item, mode: .all, isPromoted: false))
        }
        #expect(ActionItemInbox.matches(pending, mode: .all, isPromoted: true))
    }

    @Test("Counts report each chip independently")
    func countsPerMode() {
        let items = [pending, done, rejected]
        let counts = ActionItemInbox.counts(items) { $0.title == "Done" }
        #expect(counts[.inbox] == 1)
        #expect(counts[.dismissed] == 1)
        #expect(counts[.all] == 3)
    }
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run the Step 2 command from Task 1. Expected: `cannot find 'ActionItemInbox' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Logue/Models/ActionItemInbox.swift`:

```swift
import Foundation

// MARK: - ActionItemInboxMode

/// Which slice of the extracted action items is shown.
///
/// Deliberately not the due-date vocabulary `TaskFilter` uses. An inbox is a queue you
/// empty, and slicing a queue by due date is the job of the list you empty it into.
enum ActionItemInboxMode: String, CaseIterable, Sendable {
    /// Extracted, and the user has not yet decided what it is.
    case inbox
    /// Explicitly rejected. Kept visible so a wrong call is recoverable.
    case dismissed
    case all

    var displayName: String {
        switch self {
        case .inbox: "Inbox"
        case .dismissed: "Dismissed"
        case .all: "All"
        }
    }

    var symbolName: String {
        switch self {
        case .inbox: "tray"
        case .dismissed: "xmark.circle"
        case .all: "tray.full"
        }
    }
}

// MARK: - ActionItemInbox

/// Whether an extracted action item is still awaiting a decision.
///
/// Pure and view-free for the same reason `TaskFilter` is: "still undecided" is the whole
/// behaviour of this screen, and a rule that can only be exercised by clicking is a rule
/// that silently rots.
enum ActionItemInbox {
    /// `isPromoted` is passed in rather than looked up, so this stays free of `TaskStore`
    /// and the rule can be tested without a store.
    static func matches(
        _ item: ActionItem, mode: ActionItemInboxMode, isPromoted: Bool
    ) -> Bool {
        switch mode {
        case .all:
            true
        case .dismissed:
            item.isDismissed
        case .inbox:
            !item.isDismissed && !item.isCompleted && !isPromoted
        }
    }

    static func counts(
        _ items: [ActionItem], isPromoted: (ActionItem) -> Bool
    ) -> [ActionItemInboxMode: Int] {
        var result: [ActionItemInboxMode: Int] = [:]
        for mode in ActionItemInboxMode.allCases {
            result[mode] = items.filter { matches($0, mode: mode, isPromoted: isPromoted($0)) }.count
        }
        return result
    }
}
```

- [ ] **Step 4: Regenerate the project, then run the tests**

```bash
xcodegen generate
```
Then the Step 2 command. Expected: `Test run with 8 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add Logue/Models/ActionItemInbox.swift LogueTests/ActionItemInboxTests.swift Logue.xcodeproj
git commit -m "feat: decide what counts as an undecided action item"
```

---

### Task 3: Dismissing an action item

**Files:**
- Modify: `Logue/Services/MeetingStore.swift` (next to `toggleActionItemCompleted`, ~line 506)

**Interfaces:**
- Consumes: `ActionItem.isDismissed` from Task 1.
- Produces: `MeetingStore.setActionItemDismissed(_ dismissed: Bool, itemID: UUID, in meetingID: UUID)`.

- [ ] **Step 1: Write the implementation**

`MeetingStore` mutations are `@MainActor` and persist through `saveMeeting`; there is no
existing unit-test harness for them, so this task follows the file's established pattern
rather than adding one. Insert directly after `toggleActionItemCompleted`:

```swift
    /// Marks an extracted action item as something the user chose not to act on.
    ///
    /// A dismissal cancels any reminder — leaving a notification armed for an item the user
    /// just rejected is the one way this can nag them about a decision they already made.
    func setActionItemDismissed(_ dismissed: Bool, itemID: UUID, in meetingID: UUID) {
        guard let mIdx = meetingIndex(for: meetingID),
              let itemIndex = meetings[mIdx].actionItems.firstIndex(where: { $0.id == itemID })
        else { return }
        meetings[mIdx].actionItems[itemIndex].isDismissed = dismissed
        meetings[mIdx].modifiedAt = Date()

        if dismissed, let notifID = meetings[mIdx].actionItems[itemIndex].notificationID {
            ReminderManager.shared.cancelReminder(notificationID: notifID)
            meetings[mIdx].actionItems[itemIndex].reminderDate = nil
            meetings[mIdx].actionItems[itemIndex].notificationID = nil
        }

        saveMeeting(id: meetingID)
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run the Global Constraints build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Logue/Services/MeetingStore.swift
git commit -m "feat: let a meeting's action item be dismissed"
```

---

### Task 4: The dashboard becomes an inbox

**Files:**
- Modify: `Logue/Views/ActionItems/ActionItemDashboardView.swift` (588 lines — the row moves out)
- Create: `Logue/Views/ActionItems/ActionItemInboxRow.swift`

**Interfaces:**
- Consumes: `ActionItemInbox`, `ActionItemInboxMode` (Task 2),
  `MeetingStore.setActionItemDismissed` (Task 3), the existing
  `TaskStore.promotedTask(for:)` and `TaskStore.promote(_:from:)`.
- Produces: `ActionItemInboxRow` — `init(item: DashboardActionItem)`, reading
  `MeetingStore` and `TaskStore` from the environment as the current private row does.

- [ ] **Step 1: Move the row into its own file**

Cut the `private struct ActionItemDashboardRow` (and the small helpers it owns —
`completionButton`, `meetingLink`, `dueBadge`) out of `ActionItemDashboardView.swift` into
the new `ActionItemInboxRow.swift`, renaming the type to `ActionItemInboxRow` and dropping
`private` so it is visible across the two files. Keep every existing modifier: the hover
background (`AppThemeConstants.surfaceBackground` in a
`RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)`), `.padding(.horizontal, 8)`,
`.padding(.vertical, 10)`, the tap-to-open-meeting gesture and the context menu.

- [ ] **Step 2: Replace the row's leading control and trailing actions**

The completion checkbox comes off the row — the two decisions an inbox offers are "this is
work" and "this is not". Delete `completionButton` and its use in the `HStack` entirely, so
the row leads with the title, and replace the old `promoteControl` with the pair below:

```swift
    /// Promote and dismiss, revealed on hover.
    ///
    /// Both are shown only on hover for the same reason the promote button already was: one
    /// permanently-visible control per row competes with the due badge for the eye.
    @ViewBuilder
    private var decisionControls: some View {
        if taskStore.promotedTask(for: item.actionItem.id) != nil {
            Label("In Tasks", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .help("Already on your task list")
                .accessibilityLabel("Already in Tasks")
        } else if item.actionItem.isDismissed {
            Button {
                meetingStore.setActionItemDismissed(false, itemID: item.actionItem.id, in: item.meetingID)
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Put this back in the inbox")
            .accessibilityLabel("Restore to inbox")
            .opacity(isHovered ? 1 : 0)
        } else {
            HStack(spacing: 6) {
                Button {
                    taskStore.promote(item.actionItem, from: item.meetingID)
                } label: {
                    Image(systemName: "arrow.right.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Add this to your tasks")
                .accessibilityLabel("Add to Tasks")

                Button {
                    meetingStore.setActionItemDismissed(true, itemID: item.actionItem.id, in: item.meetingID)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Not something to act on")
                .accessibilityLabel("Dismiss")
            }
            .opacity(isHovered ? 1 : 0)
        }
    }
```

Keep the existing "Mark complete" entry in the row's context menu, so completing an action
item in place is still possible — it just stops being the row's headline gesture.

- [ ] **Step 3: Swap the filter vocabulary in the dashboard**

In `ActionItemDashboardView`, delete `ActionItemFilterMode` and every switch over it
(`matchesFilter`, `counts`, `tintColor(for:)`, `emptyTitle`, `emptyIcon`,
`emptyDescription`), and replace the state with the inbox mode:

```swift
    @AppStorage(AppConstants.UserDefaultsKeys.actionItemInboxMode)
    private var inboxModeRaw = ActionItemInboxMode.inbox.rawValue

    private var inboxMode: ActionItemInboxMode {
        ActionItemInboxMode(rawValue: inboxModeRaw) ?? .inbox
    }
```

Add `actionItemInboxMode` to `AppConstants.UserDefaultsKeys` beside the existing
`actionItemSortOrder`. Rewrite the filter and counts against the new rule:

```swift
    private func matchesFilter(_ item: DashboardActionItem) -> Bool {
        ActionItemInbox.matches(
            item.actionItem,
            mode: inboxMode,
            isPromoted: taskStore.promotedTask(for: item.actionItem.id) != nil
        )
    }

    private var counts: [ActionItemInboxMode: Int] {
        ActionItemInbox.counts(allItems.map(\.actionItem)) { item in
            taskStore.promotedTask(for: item.id) != nil
        }
    }
```

and the chip bar against `ActionItemInboxMode.allCases`, keeping the existing
`FilterChip(label:isSelected:tintColor:)` construction, the horizontal `ScrollView`, and
`.padding(.horizontal, 24)` / `.padding(.vertical, 8)`. Tint: `.dismissed` gets
`AppThemeConstants.warning`, the others `nil`.

- [ ] **Step 4: Update the empty states to inbox language**

```swift
    private var emptyTitle: String {
        if !searchText.isEmpty { return "No Matching Items" }
        switch inboxMode {
        case .inbox: return "Inbox Zero"
        case .dismissed: return "Nothing Dismissed"
        case .all: return "No Action Items Yet"
        }
    }

    private var emptyIcon: String {
        if !searchText.isEmpty { return "magnifyingglass" }
        return inboxMode == .inbox ? "tray" : "checklist"
    }

    private var emptyDescription: String {
        if !searchText.isEmpty { return "No action items match \"\(searchText)\"" }
        switch inboxMode {
        case .inbox:
            return "Every action item Logue found has been added to your tasks or dismissed."
        case .dismissed:
            return "Items you decide aren't worth acting on will appear here."
        case .all:
            return "Action items extracted from meetings will appear here."
        }
    }
```

Update `.navigationSubtitle` copy to read `"N in inbox"` when `inboxMode == .inbox`, and
`"N items"` otherwise. Leave the sort menu, `.searchable`, and the "Add all to Tasks"
toolbar button untouched — the last one now clears the inbox in one press, which is exactly
what it should do.

- [ ] **Step 5: Regenerate, build, and look at it**

```bash
xcodegen generate
```
Then the Global Constraints build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Logue/Views/ActionItems Logue/App/AppConstants.swift Logue.xcodeproj
git commit -m "feat: triage extracted action items instead of listing them twice"
```

---

### Task 5: The sidebar badge counts the inbox

**Files:**
- Modify: `Logue/Views/Sidebar/CategorySidebarView.swift` (`pendingActionItemCount`,
  `hasOverdueItems`, `actionItemsAccessibilityLabel` — around lines 107–125 and 327–336)

**Interfaces:**
- Consumes: `ActionItemInbox.matches` (Task 2), `TaskStore.promotedTask(for:)`.
- Produces: nothing new.

- [ ] **Step 1: Point the count at the inbox rule**

A badge that disagrees with the screen it opens is worse than no badge. Rewrite
`pendingActionItemCount` so it counts exactly what the Inbox chip shows:

```swift
    /// What the Action Items screen will show under its default chip.
    ///
    /// Counted through the same rule the screen uses rather than re-derived here — a badge
    /// that disagrees with the list it opens teaches the user to ignore it.
    private var pendingActionItemCount: Int {
        meetingStore.activeMeetings
            .filter { !$0.isArchived }
            .flatMap(\.actionItems)
            .filter {
                ActionItemInbox.matches(
                    $0, mode: .inbox, isPromoted: taskStore.promotedTask(for: $0.id) != nil
                )
            }
            .count
    }
```

Add `@State private var taskStore = TaskStore.shared` to the view if it is not already
present (the Tasks row already reads `taskStore.openTasks`, so it is).

- [ ] **Step 2: Restrict the overdue tint to inbox items**

`hasOverdueItems` drives the badge's red tint, so it must be scoped the same way — an
overdue item already promoted is Tasks' problem to colour. Apply the identical
`ActionItemInbox.matches(..., mode: .inbox, ...)` guard before the due-date check inside
that computed property.

- [ ] **Step 3: Build**

Run the Global Constraints build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Logue/Views/Sidebar/CategorySidebarView.swift
git commit -m "fix: make the action item badge agree with the screen it opens"
```

---

### Task 6: Insights stop counting dismissed items

**Files:**
- Modify: `Logue/Services/InsightsStatsProvider.swift` (`actionItemStats`, ~line 120)

**Interfaces:**
- Consumes: `ActionItem.isDismissed` (Task 1).
- Produces: nothing new — `ActionItemStats` keeps its shape.

**Note on scope:** the design said this card should exclude promoted items too. That is
wrong on reflection and is deliberately not done: the ring reports *completion rate across
extracted action items*, and a promoted item is still one of those — its completion simply
lives in Tasks. Only dismissed items are excluded, because a rejected item was never work
and counting it permanently depresses the rate.

- [ ] **Step 1: Filter dismissed items out of the denominator**

```swift
    var actionItemStats: ActionItemStats {
        // Dismissed items are excluded: they were never work, and leaving them in the
        // denominator makes the completion rate fall every time the user triages honestly.
        let allItems = activeMeetings.flatMap(\.actionItems).filter { !$0.isDismissed }
```

Leave the rest of the computation unchanged.

- [ ] **Step 2: Build**

Run the Global Constraints build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Logue/Services/InsightsStatsProvider.swift
git commit -m "fix: don't let dismissed action items depress the completion rate"
```

---

### Task 7: The meeting panel shows what became a task

**Files:**
- Modify: `Logue/Views/Meeting/MeetingActionItemsPanelView.swift` (467 lines)

**Interfaces:**
- Consumes: `TaskStore.promotedTask(for:)`.
- Produces: nothing new.

- [ ] **Step 1: Add a read-only task marker to each row**

This is the divergence fix. The meeting keeps its own checkbox and nothing is written back
to it; the row simply *reads* the promoted task's status so the user can see the two are
related. Add to the panel's row view:

```swift
    /// The task this action item was promoted into, if any.
    ///
    /// Read-only on purpose. Writing the task's status back into the meeting would edit a
    /// record of what was said because the user later changed their mind about the work.
    private var promotedTask: TaskItem? {
        taskStore.promotedTask(for: item.id)
    }

    @ViewBuilder
    private var taskMarker: some View {
        if let promotedTask {
            Label(
                promotedTask.status == .done ? "Done in Tasks" : "In Tasks",
                systemImage: promotedTask.status == .done ? "checkmark.circle.fill" : "arrow.right.circle"
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
            .help("This action item was added to your tasks")
        }
    }
```

Add `@State private var taskStore = TaskStore.shared` to that row view and place
`taskMarker` in the row's trailing `HStack`, before any due-date badge.

- [ ] **Step 2: Build**

Run the Global Constraints build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Logue/Views/Meeting/MeetingActionItemsPanelView.swift
git commit -m "feat: show on the meeting which action items became tasks"
```

---

### Task 8: Tasks gains search

**Files:**
- Modify: `Logue/Models/TaskFilter.swift`
- Test: `LogueTests/TaskFilterTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `TaskFilter.apply(_:mode:tag:searchText:now:calendar:)` — a new `searchText:
  String = ""` parameter placed after `tag:`, so every existing call site keeps compiling.

- [ ] **Step 1: Write the failing tests**

Append to the existing `TaskFilterTests` suite:

```swift
    // MARK: - Search

    private func searched(_ text: String) -> [String] {
        TaskFilter.apply(sample, mode: .all, tag: nil, searchText: text, now: now, calendar: calendar)
            .map(\.title)
    }

    @Test("Empty search leaves the list alone")
    func emptySearchIsNoOp() {
        #expect(searched("") == titles(.all))
    }

    @Test("Search matches the title case-insensitively")
    func searchMatchesTitle() {
        #expect(searched("upcom") == ["Upcoming"])
        #expect(searched("UPCOM") == ["Upcoming"])
    }

    @Test("Search matches a tag")
    func searchMatchesTag() {
        #expect(searched("work").sorted() == ["Overdue", "Upcoming"])
    }

    @Test("Search matches the notes body")
    func searchMatchesNotes() {
        let tasks = [TaskItem(title: "Opaque", notes: "Assigned to: Priya")]
        let found = TaskFilter.apply(
            tasks, mode: .all, tag: nil, searchText: "priya", now: now, calendar: calendar
        )
        #expect(found.map(\.title) == ["Opaque"])
    }

    @Test("A search that matches nothing returns nothing")
    func searchWithNoMatches() {
        #expect(searched("zzzz").isEmpty)
    }
```

- [ ] **Step 2: Run the tests and confirm they fail**

```bash
xcodebuild test -project Logue.xcodeproj -scheme Logue -destination 'platform=macOS' \
  -derivedDataPath /tmp/logue-dd-tasks-and-triage \
  -clonedSourcePackagesDirPath ~/Library/Developer/Xcode/DerivedData/Logue-SPM \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  -only-testing:LogueTests/TaskFilterTests 2>&1 | grep -E "^✘|Test run with|error:"
```
Expected: compile failure — `extra argument 'searchText' in call`.

- [ ] **Step 3: Add the parameter**

In `TaskFilter.apply`, add `searchText: String = ""` after `tag: String?`, and apply it
after the tag filter:

```swift
        guard let tag, !tag.isEmpty else { return applySearch(matched, searchText) }
        let tagged = matched.filter { task in
            task.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }
        return applySearch(tagged, searchText)
    }

    /// Title, tags and notes — the three places a task's words live.
    private static func applySearch(_ tasks: [TaskItem], _ searchText: String) -> [TaskItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tasks }
        return tasks.filter { task in
            task.title.localizedCaseInsensitiveContains(query)
                || task.notes.localizedCaseInsensitiveContains(query)
                || task.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
```

- [ ] **Step 4: Run the tests and confirm they pass**

Same command as Step 2. Expected: all `TaskFilter` tests pass, including the pre-existing ones.

- [ ] **Step 5: Commit**

```bash
git add Logue/Models/TaskFilter.swift LogueTests/TaskFilterTests.swift
git commit -m "feat: search tasks by title, tag and notes"
```

---

### Task 9: Tasks adopts the app's list chrome

**Files:**
- Modify: `Logue/Views/Tasks/TaskListView.swift`

**Interfaces:**
- Consumes: `TaskFilter.apply(_:mode:tag:searchText:now:calendar:)` (Task 8), the existing
  `FilterChip`, `AppThemeConstants`.
- Produces: nothing new.

- [ ] **Step 1: Move filter, search and sort into the app's vocabulary**

Replace the segmented `Picker` and the inline button row with the chip bar and a toolbar,
mirroring `ActionItemDashboardView` element for element:

```swift
    @State private var searchText = ""

    private var visibleTasks: [TaskItem] {
        TaskFilter.sort(
            TaskFilter.apply(store.tasks, mode: filterMode, tag: selectedTag, searchText: searchText),
            by: sortOrder
        )
    }

    private var counts: [TaskFilterMode: Int] {
        var result: [TaskFilterMode: Int] = [:]
        for mode in TaskFilterMode.allCases {
            result[mode] = TaskFilter.apply(store.tasks, mode: mode, tag: selectedTag).count
        }
        return result
    }

    private var filterChipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TaskFilterMode.allCases, id: \.rawValue) { mode in
                    let count = counts[mode] ?? 0
                    FilterChip(
                        label: "\(mode.displayName) \(count)",
                        isSelected: filterMode == mode,
                        tintColor: tintColor(for: mode)
                    ) {
                        filterModeRaw = mode.rawValue
                    }
                    .accessibilityLabel("\(mode.displayName), \(count) tasks")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }

    /// The same mapping the action item chips use, so a red chip means the same thing on
    /// both screens.
    private func tintColor(for mode: TaskFilterMode) -> Color? {
        switch mode {
        case .overdue: AppThemeConstants.error
        case .today, .upcoming: AppThemeConstants.warning
        case .completed: AppThemeConstants.success
        default: nil
        }
    }
```

- [ ] **Step 2: Rebuild the body around the shared chrome**

```swift
    var body: some View {
        VStack(spacing: 0) {
            TaskQuickAddField { text in
                store.capture(text)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            filterChipBar
            Divider()

            if visibleTasks.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .background(AppThemeConstants.contentBackground)
        .navigationTitle("Tasks")
        .navigationSubtitle(subtitle)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search tasks")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showTriage) { triageSheet }
    }

    private var subtitle: String {
        let total = visibleTasks.count
        return "\(total) task\(total == 1 ? "" : "s")"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showTriage = true
                Task {
                    await triageService.run(tasks: store.tasks, knownTags: store.allTags)
                }
            } label: {
                Image(systemName: "sparkles")
            }
            // Concurrent inference races on the shared session; this is the project-wide
            // guard for any control that reaches the engine.
            .disabled(engineStatus.isBusy || store.openTasks.isEmpty)
            .help("Ask Logue to review your open tasks")
            .accessibilityLabel("Triage tasks")

            sortMenu
        }
    }
```

Change `sortMenu`'s label to `Image(systemName: "arrow.up.arrow.down.circle")` and drop
`.menuStyle(.borderlessButton)` / `.fixedSize()` so it sits in the toolbar like the
dashboard's. Keep the tag section inside that menu.

- [ ] **Step 3: Replace the list and the empty state**

```swift
    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(visibleTasks) { task in
                    TaskRowView(
                        task: task,
                        meetingTitle: meetingTitle(for: task),
                        onToggle: { store.toggleCompletion(id: task.id) },
                        onOpenSource: { openSource(for: task) }
                    )
                    .contextMenu {
                        priorityMenu(for: task)
                        Divider()
                        Button("Delete", role: .destructive) { store.delete(id: task.id) }
                    }
                    if task.id != visibleTasks.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: emptyIcon)
        } description: {
            Text(emptyDescription)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if !searchText.isEmpty { return "No Matching Tasks" }
        switch filterMode {
        case .all: return "Nothing Here"
        case .today: return "Nothing Due Today"
        case .overdue: return "Nothing Overdue"
        case .upcoming: return "Nothing Upcoming"
        case .noDueDate: return "Every Task Has a Date"
        case .completed: return "No Completed Tasks"
        }
    }

    private var emptyIcon: String {
        if !searchText.isEmpty { return "magnifyingglass" }
        switch filterMode {
        case .overdue, .today, .upcoming: return "checkmark.circle"
        case .completed: return "circle"
        default: return "checklist"
        }
    }

    private var emptyDescription: String {
        if !searchText.isEmpty { return "No tasks match \"\(searchText)\"" }
        switch filterMode {
        case .all: return "Type above to add a task. Try \"Send the deck tomorrow #launch !\"."
        case .today: return "Nothing is due today."
        case .overdue: return "No task is past its due date."
        case .upcoming: return "Nothing is scheduled ahead."
        case .noDueDate: return "Every open task has a due date."
        case .completed: return "Completed tasks will appear here."
        }
    }
```

Watch the 60-line function limit — `body` and each computed property above are well under
it, but do not merge them.

- [ ] **Step 4: Build**

Run the Global Constraints build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Logue/Views/Tasks/TaskListView.swift
git commit -m "feat: give Tasks the same chrome as the rest of the app"
```

---

### Task 10: Task rows match dashboard rows

**Files:**
- Modify: `Logue/Views/Tasks/TaskRowView.swift`

**Interfaces:**
- Consumes: `AppThemeConstants`.
- Produces: nothing new — the initializer is unchanged.

- [ ] **Step 1: Add the hover treatment and theme colours**

```swift
    @State private var isHovered = false
```

Replace `.padding(.vertical, 4)` with the dashboard row's geometry and hover fill:

```swift
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            isHovered ? AppThemeConstants.surfaceBackground : Color.clear,
            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
```

Change the `HStack` alignment from `.firstTextBaseline` to `.center` to match, and swap the
two raw colours in `badges` for theme constants — `tint: task.isOverdue ?
AppThemeConstants.error : .secondary` and `tint: task.priority == .high ?
AppThemeConstants.warning : .secondary`. Raw `.red` / `.orange` do not adapt with the rest
of the palette.

- [ ] **Step 2: Build**

Run the Global Constraints build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Logue/Views/Tasks/TaskRowView.swift
git commit -m "feat: match task rows to the app's row styling"
```

---

### Task 11: Verify the whole change

**Files:** none modified unless a check fails.

- [ ] **Step 1: Run the fast test suites**

LLM integration suites run real inference and are unrelated to this change, so skip them by
type name:

```bash
ARGS=(); for s in ClarityAnalysisLLMTests DailyDigestLLMTests DocumentChatLLMTests \
  DocumentTitleLLMTests FactCheckLLMTests GrammarAnalysisLLMTests MeetingChatLLMTests \
  MeetingTitleLLMTests PIIScanLLMTests RephraseLLMTests ReviewReactionsLLMTests \
  ReviewScoreLLMTests RewriteStyleLLMTests SmartMinutesLLMTests ToneDetectionLLMTests \
  VocabularyEnhancementLLMTests; do ARGS+=("-skip-testing:LogueTests/$s"); done
xcodebuild test -project Logue.xcodeproj -scheme Logue -destination 'platform=macOS' \
  -derivedDataPath /tmp/logue-dd-tasks-and-triage \
  -clonedSourcePackagesDirPath ~/Library/Developer/Xcode/DerivedData/Logue-SPM \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  -only-testing:LogueTests "${ARGS[@]}" 2>&1 | grep -E "^✘|Test run with|\*\* TEST"
```

Expected: every suite passes, including the untouched `TaskPromotionTests` — promotion
semantics did not change in this plan, so a failure there means something regressed.

- [ ] **Step 2: Lint exactly as CI does**

```bash
make lint
```

Expected: no output from either tool. Run `make format` to auto-fix SwiftFormat complaints.

- [ ] **Step 3: Launch and look at both screens**

Build signed, then open and screenshot. **Launching starts recording the microphone and
system audio and writes a meeting** — quit as soon as you are done, and tell the user a
meeting was created.

```bash
xcodebuild build -project Logue.xcodeproj -scheme Logue -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/logue-dd-tasks-and-triage \
  -clonedSourcePackagesDirPath ~/Library/Developer/Xcode/DerivedData/Logue-SPM \
  DEVELOPMENT_TEAM=HC5R66SXM5 CODE_SIGN_STYLE=Automatic 2>&1 | grep -E "error:|BUILD"
open /tmp/logue-dd-tasks-and-triage/Build/Products/Debug/Logue.app
```

Confirm by eye: the Action Items chips read Inbox / Dismissed / All; promoting a row makes
it leave the Inbox; the Tasks screen has a search field in the toolbar, counted chips, and
rows that highlight on hover. Quit with `osascript -e 'quit app "Logue"'`.

- [ ] **Step 4: Check nothing leaked into the repo**

```bash
git log origin/main..HEAD | grep -iE 'superpower|skill|plugin|claude|🤖' || echo clean
```

Expected: `clean`.
