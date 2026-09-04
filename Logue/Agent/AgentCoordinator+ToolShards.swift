import Foundation

/// The tool registry's contents, split out of `AgentCoordinator`.
///
/// These are the lists themselves — one function per family — and they are static because
/// none of them read the coordinator's state. Moving them here is what keeps the class body
/// inside the 450-line cap; nothing about the registry changed with the move.
///
/// `buildToolRegistry`, which decides what survives the user's filters, stays with the state
/// it consults.
///
/// Extension-visible: these were `private static` in the core file and had to widen to
/// `static` to be composed by `allKnownTools()` from there. Nothing outside `AgentCoordinator`
/// and its extensions should call them — the registry is the answer, not its ingredients.
extension AgentCoordinator {
    //
    // The full registry is composed from these helpers in `buildToolRegistry`.
    // Splitting keeps each function under SwiftLint's body-length cap and
    // gives a single place to look up which tools exist in each category.

    static func readOnlyTools() -> [any AgentTool] {
        [
            ListMeetingsTool(),
            SearchMeetingsTool(),
            SemanticSearchMeetingsTool(),
            GetMeetingDetailsTool(),
            GetTranscriptTool(),
            GetActionItemsTool(),
            GetDailyDigestTool(),
            ListDocumentsTool(),
            SearchDocumentsTool(),
            SemanticSearchDocumentsTool(),
            GetDocumentTool(),
            GetUpcomingEventsTool(),
        ]
    }

    static func writeTools() -> [any AgentTool] {
        [
            CreateDocumentTool(),
            UpdateDocumentTool(),
            DeleteDocumentTool(),
            MoveDocumentTool(),
            AddDocumentTagTool(),
            CreateSpaceTool(),
            RenameSpaceTool(),
            DeleteSpaceTool(),
            CreateCalendarEventTool(),
            UpdateCalendarEventTool(),
            DeleteCalendarEventTool(),
            ListTemplatesTool(),
            CreateDocumentFromTemplateTool(),
            ExportDocumentPDFTool(),
        ]
    }

    static func aiContentTools() -> [any AgentTool] {
        [
            SummarizeDocumentTool(),
            RephraseTextTool(),
            GrammarCheckTool(),
            ClarityCheckTool(),
            ToneDetectTool(),
            FactCheckDocumentTool(),
            DetectPIITool(),
            RenderDiagramTool(),
            GenerateSlideDeckTool(),
        ]
    }

    static func appleNativeTools() -> [any AgentTool] {
        [
            DraftEmailTool(),
            FetchContactsTool(),
            GetRemindersTool(),
            AddReminderTool(),
            UpdateReminderTool(),
            DeleteReminderTool(),
            GetLocationTool(),
        ]
    }

    static func computeAndDialogTools() -> [any AgentTool] {
        [
            RunJavaScriptTool(),
            GetConfirmationTool(),
            GetTextInputTool(),
            GetUserSelectionTool(),
        ]
    }

    /// Phase G: external filesystem access. Sandbox-safe via
    /// `FileAccessGate` — first call to a new folder prompts the user
    /// via `NSOpenPanel` for an explicit grant.
    static func fileSystemTools() -> [any AgentTool] {
        [
            ListDirectoryTool(),
            ReadFileAtPathTool(),
            WriteTextToFileTool(),
            DeleteFileAtPathTool(),
        ]
    }

    /// Per-tool disable set. Persisted by `AISettingsTab` as a comma-separated
    /// list of tool names. The registry rebuilds on every send (via the
    /// observer in `AISettingsTab`), so toggling is effectively immediate.
    static func disabledToolNames() -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.disabledAgentTools) ?? ""
        return Set(raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }
}
