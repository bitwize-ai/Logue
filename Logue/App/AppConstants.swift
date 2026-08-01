import Foundation

enum AppConstants {
    static let bundleID = "com.bitwize.logue"
    static let appName = "Logue"

    enum UserDefaultsKeys {
        static let activeModelID = "activeModelID"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"

        /// Set once `SandboxContainerMigrator` has moved data out of the legacy
        /// (pre-1.0.1, sandboxed) container. See that type for why the sandbox went away.
        static let sandboxContainerMigrationCompleted = "sandboxContainerMigrationCompleted"

        static let writingGoalMode = "writingGoalMode"
        static let actionModelMap = "ActionModelMap"
        static let documentViewMode = "documentViewMode"
        static let meetingViewMode = "meetingViewMode"
        static let trashViewMode = "trashViewMode"

        static let shortcutCommandCenterKeyCode = "shortcutCommandCenterKeyCode"
        static let shortcutCommandCenterModifiers = "shortcutCommandCenterModifiers"

        static let hasClearedSeedData = "hasClearedSeedData"

        static let documentSortOrder = "documentSortOrder"
        static let meetingSortOrder = "meetingSortOrder"
        static let actionItemSortOrder = "actionItemSortOrder"
        static let autoSortCheckedItems = "autoSortCheckedItems"
        /// Editor zoom multiplier applied on top of the base editor font size.
        static let editorZoomScale = "editorZoomScale"
        /// Width mode newly created documents start at. Per-document values still win.
        static let defaultDocumentWidthMode = "defaultDocumentWidthMode"
        /// Which panes the main window shows — see `EditorLayoutMode`.
        static let editorLayoutMode = "editorLayoutMode"
        /// Language last chosen in a code block, used as the default for the next one.
        static let lastCodeBlockLanguage = "lastCodeBlockLanguage"
        /// How documents are stored: `encrypted` (default) or `markdown`.
        static let documentStorageMode = "documentStorageMode"
        static let unwritableDocuments = "unwritableDocuments"
        static let groupByDate = "groupByDate"
        static let customAPIModels = "CustomAPIModels"
        static let autoSaveSummaryToDocument = "autoSaveSummaryToDocument"
        static let sidebarSpaceSortOrder = "sidebarSpaceSortOrder"
        /// Master toggle for the agent's web-search tools. Default OFF for privacy.
        static let webSearchEnabled = "agent.webSearchEnabled"
        /// Per-send "Search this turn" override toggled from the input bar's
        /// `+` menu. Mirrors the in-memory `oneShotIncludeWebTools` state, but
        /// gives the AgentCoordinator a SwiftUI-binding-independent way to
        /// observe the user's intent (the Menu close pipeline on macOS can
        /// race with `@Binding` updates). Reset to `false` after every send.
        static let oneShotWebSearch = "agent.oneShotWebSearch"
        /// Same idea for the per-send Deep Research toggle.
        static let oneShotDeepResearch = "agent.oneShotDeepResearch"
        /// Optional override for the agent system prompt. Empty string = use the
        /// built-in default in `PromptRegistry.Agent`.
        static let agentSystemPromptOverride = "agent.systemPromptOverride"
        /// Comma-separated list of tool names the user has disabled in Settings.
        /// The registry strips these on every rebuild.
        static let disabledAgentTools = "agent.disabledTools"
        /// Whether the agent's `<thinking>` reasoning blocks are shown in the
        /// rendered response. Default OFF — most users don't want them.
        static let showReasoningBlocks = "agent.showReasoningBlocks"
        /// Tavily API key (stored via Keychain, but we mirror "is set" here so
        /// Settings can show the input as filled without re-fetching the secret).
        static let tavilyKeyPresent = "agent.tavilyKeyPresent"
        /// User-overridden inference params. -1 = use model defaults.
        static let inferenceTemperature = "agent.inferenceTemperature"
        static let inferenceTopP = "agent.inferenceTopP"
        static let inferenceMaxTokens = "agent.inferenceMaxTokens"
        /// Memory recall thresholds.
        static let memoryRecallThreshold = "agent.memoryRecallThreshold"
        static let memoryTopK = "agent.memoryTopK"
        /// Preferred TTS voice identifier (`AVSpeechSynthesisVoice.identifier`).
        static let ttsVoiceIdentifier = "agent.ttsVoiceIdentifier"
    }

    enum ModelStorage {
        /// Root directory where downloaded MLX models are stored.
        /// Matches LocalLLMClient's FileDownloader.defaultRootDestination.
        static var rootDirectory: URL {
            URL.applicationSupportDirectory
                .appending(path: "LocalLLM", directoryHint: .isDirectory)
        }
    }

    // A9/A10/A-N10/A-N11: Centralized LLM defaults
    enum LLMDefaults {
        static let maxRetryAttempts = 3
        static let retryDelay: Duration = .seconds(1)
        static let contextWindowSize = 800
        static let titlePromptContextSize = 800
        static let summaryFallbackContextSize = 2000
        static let spaceSuggestionContextSize = 600
        static let maxTitleLength = 100
        // A-N10: Minimum content thresholds
        static let minCharsForAI = 20
        static let minDocCharsForAutoTitle = 50
        // A-N11: Additional context window sizes
        static let piiContextSize = 6000
        static let piiLLMContextSize = 3000
        static let spaceContextSize = 4000
        static let digestSummaryContextSize = 300

        /// Reserved tokens for context window calculations (~4 chars/token heuristic).
        /// summaryReservedTokens: 2048 output + 1500 system prompt/speaker context = 3548
        static let summaryReservedTokens = 3548
        /// chatReservedTokens: 1024 output + 500 system prompt = 1524
        static let chatReservedTokens = 1524
    }

    enum Audio {
        /// Buffer size for AVAudioEngine input tap
        static let tapBufferSize: UInt32 = 4096
        /// Interval in nanoseconds for polling aggregate device readiness
        static let devicePollIntervalNanos: UInt64 = 100_000_000 // 100ms
        /// Retry delay in nanoseconds for AudioDeviceStart
        static let deviceStartRetryDelayNanos: UInt64 = 200_000_000 // 200ms
        /// Maximum attempts to poll aggregate device readiness
        static let maxDevicePollAttempts = 20
        /// Maximum attempts to start audio device
        static let maxDeviceStartRetries = 5
        /// Diarization model initialization timeout in seconds (long to allow first-time HuggingFace download)
        static let diarizationInitTimeoutSeconds: TimeInterval = 600
    }

    enum Diarization {
        /// Minimum samples between Sortformer process() calls (at 16kHz)
        static let processIntervalSamples = 32000 // 2.0s
        /// Speaker label matching tolerance in seconds
        static let speakerLabelTolerance: Double = 3.5
        /// Clustering threshold for batch diarizer
        static let clusteringThreshold: Float = 0.65
        /// Sortformer onset threshold (lower catches quieter speakers)
        static let onsetThreshold: Float = 0.4
        /// Sortformer offset threshold
        static let offsetThreshold: Float = 0.4
        /// Post-recording pipeline timeout in seconds
        static let postRecordingTimeoutSeconds: TimeInterval = 180
        /// How much of a recording the post-recording batch pass (Parakeet ASR + Sortformer) can be
        /// handed in one go, expressed as memory rather than as minutes: the session's audio is held
        /// as 16 kHz mono Float32 (~230 MB per hour) and given to the models whole, so what bounds
        /// it is what the machine can hold. A fixed number of minutes would be wasteful on a large
        /// Mac and reckless on a small one. `AudioTimelineMixer.capacity(forPhysicalMemory:)` reads
        /// these; audio past the limit is dropped and that stretch keeps its live transcript rather
        /// than losing it — see `TranscriptReplacement`.
        static let audioBufferMemoryDivisor: UInt64 = 16 // a sixteenth of physical memory
        static let audioBufferMinBytes: UInt64 = 256 * 1024 * 1024 // ~1.2 hours
        static let audioBufferMaxBytes: UInt64 = 1024 * 1024 * 1024 // ~4.6 hours
        /// Chunk size for the long-recording pass, which streams the persisted file past the
        /// in-memory limit instead of stopping there. Big enough that per-chunk overhead is
        /// irrelevant, small enough that a chunk is a few megabytes.
        static let longRecordingChunkSeconds: Double = 30
        /// Dedup tolerance for overlapping speaker segments in seconds
        static let segmentDedupTolerance: Double = 0.15
        /// Silero VAD model probability threshold — lowered from default 0.85 to catch quiet/distant speakers
        static let vadThreshold: Float = 0.5
        /// VAD: minimum speech duration kept (filters keyboard/breath noise)
        static let vadMinSpeechDuration: TimeInterval = 0.25
        /// VAD: silence needed to close a speech segment (prevents mid-sentence cuts on thinking pauses)
        static let vadMinSilenceDuration: TimeInterval = 1.5
        /// VAD: padding added before/after each speech region (covers cut-off word starts/ends)
        static let vadSpeechPadding: TimeInterval = 0.25
        /// VAD: hysteresis offset — once speech starts, stays triggered until prob drops this far below threshold
        static let vadNegativeThresholdOffset: Float = 0.25

        // MARK: Timeline normalization

        /// Sortformer segments shorter than this are treated as fragments and discarded
        static let minSpeakerSegmentDuration: TimeInterval = 0.7
        /// Consecutive segments from the same speaker within this gap are merged into one
        static let sameSpeakerMergeGap: TimeInterval = 0.25
        /// An A-B-A speaker alternation completing within this window is collapsed to the dominant speaker
        static let alternationWindowSeconds: TimeInterval = 0.8
        /// Largest silence left between normalized speaker segments before it is closed up
        static let timelineMaxGap: TimeInterval = 0.5
        /// Widest silence worth closing at all. Beyond this the pause is real conversation rhythm,
        /// not model jitter, and pulling the next speaker back over it would hand them time they
        /// were audibly not speaking for — which alignment would then read as confident overlap for
        /// anything transcribed in that window. Long silences are left as silence.
        static let maxClosableGap: TimeInterval = 2.0

        // MARK: Transcript alignment

        /// Transcript segments longer than this are chunked for weighted majority voting
        static let chunkThresholdSeconds: TimeInterval = 2.0
        /// Width of each voting chunk when a long transcript segment is subdivided
        static let chunkDurationSeconds: TimeInterval = 1.5
        /// A runner-up speaker holding at least this fraction of the winner's overlap makes the
        /// segment too close to call, so the previous segment's speaker is preferred instead
        static let ambiguityOverlapRatio: Double = 0.70
        /// Nearest-speaker fallback window used only when nothing overlaps the segment at all.
        /// Deliberately far tighter than `speakerLabelTolerance`, which governs text gathering.
        static let labelFallbackTolerance: TimeInterval = 0.5
        /// Minimum overlap that makes a second speaker worth splitting a transcript segment for
        static let minSplitOverlap: TimeInterval = 0.15
        /// Split parts shorter than this are not worth creating
        static let minSplitPartDuration: TimeInterval = 0.4
        /// Upper bound on the parts a single transcript segment may be split into
        static let maxSplitParts = 5
        /// A single-segment speaker island longer than this is a real turn, not flapping,
        /// so smoothing leaves it alone
        static let maxSmoothedIslandDuration: TimeInterval = 0.8
    }

    // A-N13: Default title strings
    static let defaultDocumentTitle = "Untitled Document"
    static let defaultMeetingTitle = "Untitled Meeting"

    // MARK: - Centralized Delays

    enum Delays {
        /// Coalesces a burst of filesystem events from another editor saving, so one
        /// external save triggers one folder scan rather than several.
        ///
        /// A `TimeInterval` rather than a `Duration` because its only caller is
        /// `DispatchQueue.asyncAfter`, sitting between two C APIs — `FSEventStream` and GCD —
        /// and neither speaks `Duration`.
        static let folderScanDebounceSeconds: TimeInterval = 0.4

        /// How long a file must have been untouched before it is adopted as a new document.
        ///
        /// A file mid-write looks exactly like a file with no identifier, and adopting one wrote our
        /// frontmatter over content the user was still saving. Comfortably longer than the scan
        /// debounce, because the point is to outlast a writer that is not atomic.
        static let adoptionSettleSeconds: TimeInterval = 2.0

        /// How long a pane waits before admitting it is still loading.
        ///
        /// Long enough that a fast load looks instant rather than showing a spinner that
        /// flashes, short enough that a slow one does not look broken.
        static let loadingIndicatorAppearance: Duration = .milliseconds(250)

        /// How long the rescan button keeps spinning at minimum.
        ///
        /// A scan of a normal folder finishes in milliseconds — faster than the eye, so
        /// without a floor the press would look like it did nothing at all.
        static let rescanMinimumVisible: Duration = .milliseconds(700)

        /// -- UI Debounce --
        /// Search field input debounce (document list, meeting list, overview, sidebar)
        static let searchDebounce: Duration = .milliseconds(300)
        /// Markdown sync debounce in block editor
        static let markdownSyncDebounce: Duration = .milliseconds(300)
        /// Metadata save debounce for non-critical meeting changes (favorite, archive, rename)
        static let metadataSaveDebounce: Duration = .milliseconds(300)

        /// -- Persistence Debounce --
        /// Debounced disk save interval during live recording
        static let liveRecordingSaveDebounce: Duration = .seconds(3)
        /// Debounce before generating auto-title for meetings
        static let meetingAutoTitleDebounce: Duration = .seconds(2)
        /// Debounce before generating auto-title for documents
        static let documentAutoTitleDebounce: Duration = .seconds(3)
        /// Debounce before running spell check after cursor movement
        static let spellCheckDebounce: Duration = .seconds(1)

        /// -- UI Focus --
        /// Brief yield to let UI update before setting focus on a text field
        static let focusActivation: Duration = .milliseconds(100)

        /// -- UI Feedback --
        /// Duration to show transient "Copied" / "Inserted" / clipboard feedback
        static let clipboardFeedback: Duration = .milliseconds(1500)
        /// Duration to show transient toast or status messages (e.g. export, save, command center)
        static let toastDismiss: Duration = .seconds(2)
        /// Duration to show bookmark confirmation feedback
        static let bookmarkConfirm: Duration = .seconds(1)
        /// Duration to show bookmark confirm during recording (slightly longer)
        static let bookmarkConfirmLong: Duration = .seconds(1.5)
        /// Duration to show "copied to clipboard" in Polish engine
        static let copiedToClipboardDismiss: Duration = .seconds(1.5)
        /// Duration to show block highlight after programmatic focus
        static let blockHighlight: Duration = .seconds(1.5)
        /// Cleanup delay for temporary suggestion highlight injected by scrollToBlockContaining
        static let suggestionHighlightCleanup: Duration = .milliseconds(500)
        /// Brief pause before auto-advancing onboarding page after model ready
        static let onboardingAutoAdvance: Duration = .milliseconds(800)

        /// -- Navigation --
        /// Brief yield to let sidebar expand before selecting a space
        static let sidebarNavigationYield: Duration = .milliseconds(150)

        /// -- Engine / System --
        /// Yield to allow Metal resource deallocation when switching LLM models
        static let metalDeallocationYield: Duration = .milliseconds(200)
        /// Timeout for LLM session prewarm
        static let llmPrewarmTimeout: Duration = .seconds(60)
        /// Timeout for waiting on previous post-recording task before new session
        static let postRecordingWaitTimeout: Duration = .seconds(5)
        /// Timeout for SpeechTranscriberEngine recognizer finalization
        static let recognizerFinalizationTimeout: Duration = .seconds(10)

        /// -- Accessibility / Cross-App --
        /// Brief yield before posting synthetic keyboard events (Cmd+V paste)
        static let accessibilityKeyEventYield: Duration = .milliseconds(100)
        /// Delay before restoring original clipboard contents after paste
        static let clipboardRestoreDelay: Duration = .milliseconds(500)
        /// Brief yield before activating app (dock icon + frontmost)
        static let appActivationYield: Duration = .milliseconds(100)
        /// Speech synthesis polling interval to detect end of speaking
        static let speechSynthesisPolling: Duration = .milliseconds(500)
        /// Delay before re-focusing input field after sending chat message
        static let chatInputRefocusInterval: TimeInterval = 0.1

        /// -- Voice --
        /// Brief pause to let voice recognition finalize before reading transcript
        static let voiceRecognitionFinalize: Duration = .milliseconds(400)

        /// -- Diarization --
        /// Polling interval while waiting for Sortformer processing lock to release
        static let sortformerPollInterval: Duration = .milliseconds(10)
        /// How long stop-recording waits for diarization models to finish initializing before
        /// giving up and letting post-recording AI proceed without Sortformer
        static let diarizationInitStopWait: Duration = .seconds(10)

        /// -- Audio Device Retry (exponential backoff) --
        /// Initial retry delay for AudioDeviceStart (doubles each attempt)
        static let audioDeviceStartInitialDelayNanos: UInt64 = 50_000_000 // 50ms
        /// Maximum retry delay cap for AudioDeviceStart
        static let audioDeviceStartMaxDelayNanos: UInt64 = 400_000_000 // 400ms

        // -- DispatchQueue / GCD Delays (TimeInterval) --
        // These use `TimeInterval` (seconds as Double) for GCD compatibility:
        // `DispatchQueue.main.asyncAfter(deadline: .now() + delay)`.
        // All `Duration` constants above are for `Task.sleep(for:)` in async contexts.

        /// Delay for dock visibility update after window close
        static let dockVisibilityUpdateInterval: TimeInterval = 0.3
        /// Delay before terminating app after relaunch to let new instance start
        static let relaunchTerminationInterval: TimeInterval = 0.5
        /// Brief delay before hiding selection toolbar (checks if selection cleared)
        static let selectionToolbarHideInterval: TimeInterval = 0.08
    }

    enum Support {
        static let email = "support@bitwize.ai"
    }

    // MARK: - Editor

    enum Editor {
        /// Comfortable measure for prose — roughly 75 characters at the default size.
        static let normalContentWidth: CGFloat = 720
        /// Wide measure for tables, diagrams, and generated documents.
        static let wideContentWidth: CGFloat = 1100

        /// Editor text-zoom bounds. 1.0 is the document's natural size.
        static let minZoom: CGFloat = 0.5
        static let maxZoom: CGFloat = 3.0
        static let zoomStep: CGFloat = 0.1
        static let defaultZoom: CGFloat = 1.0
    }

    // MARK: - Agent Defaults

    // MARK: - Web Search

    enum WebSearch {
        /// User-Agent sent to DuckDuckGo's HTML endpoint. Matches a common Mac
        /// browser shape; some endpoints reject unknown clients.
        static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        /// Hard ceiling on results returned per query (keeps tool output tight).
        static let maxResults = 10
        /// Maximum query length before truncation. Long queries are usually noise.
        static let maxQueryChars = 200
        /// Maximum characters returned by `fetch_web_page`. Caps tool output well
        /// below the agent result truncation threshold.
        static let maxFetchChars = 16000
    }

    enum AgentDefaults {
        /// Maximum tool-call rounds before the agent loop terminates with a fallback response.
        static let maxToolRounds = 5
        /// Maximum retries per individual tool before skipping it.
        static let maxToolRetries = 3
        /// Maximum characters for a single tool result before truncation.
        static let toolResultMaxChars = 4000
        /// Reserved tokens for agent system prompt + output overhead.
        static let reservedTokens = 1524
        /// Max output tokens for agent responses (higher than default 512 for detailed answers).
        static let maxResponseTokens = 2048
        /// Per-tool execution timeout in seconds. Prevents indefinite hangs from stuck tools.
        static let toolTimeoutSeconds: UInt64 = 30
        /// How long the approval gate waits for user input before auto-rejecting (in seconds).
        static let approvalTimeoutSeconds: Int = 300
    }
}
