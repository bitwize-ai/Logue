# Automatic capture and recording resilience

**Date:** 2026-08-12
**Status:** Approved, not yet implemented

## Why

Three things are wrong with recording today, and one thing is missing.

**The user is asked questions the machine can answer.** Starting a recording means picking a
recording mode (`.inPerson` / `.onlineMeeting` / `.voiceNote`), and then, during the meeting,
managing two independent toggles for the microphone and system audio. The app already knows this
is confusing: `MeetingWorkspaceView` shows a coach-mark when a recording is running with system
audio off, on the assumption the user meant to turn it on and could not find the control. The
information needed to make these decisions is available from Core Audio without asking.

**Everything the microphone hears reaches the transcriber.** There is no gate between the capture
tap and `SpeechTranscriber`, so silence, keyboard noise and room tone are all transcribed, and the
microphone re-hears remote participants coming out of the laptop speakers — so the same sentence
is transcribed twice, once from the system tap and once from the mic, and the diarizer sees one
person's voice arriving on two channels.

**A crash loses the meeting.** Transcript segments are appended with `persistImmediately: false`,
and the metadata that says where each stretch of captured audio belongs on the meeting's timeline
is only resolved when recording stops. The audio files are written continuously, but to
`FileManager.default.temporaryDirectory` with a delete-on-reboot resource value, so after an
unexpected quit there is no transcript and no reliable audio.

**A device that disappears is not handled.** `AVAudioEngineConfigurationChange` is observed, but
there is no notion of a device being briefly gone versus gone for good, and no fallback.

## What this is not

This work was prompted by a comparison against [meetily](https://github.com/Zackriya-Solutions/meetily),
which was read in full before this was written. It is worth recording what was deliberately *not*
adopted, so the question is not reopened later.

Meetily is a Rust/Tauri application. Its recording core is roughly 15k lines built on cpal,
whisper-rs, silero-rs and an ffmpeg sidecar. Adopting its architecture wholesale would mean
rewriting a working subsystem in a different shape, and would cost us three things we have and it
does not:

- **Timeline-correct mixing.** `AudioTimelineMixer` gives each source its own cursor, so samples
  land where they were heard. Meetily accumulates into an arrival-order ring buffer and drops
  samples on overflow — its own log line reads `SYSTEM AUDIO BUFFER OVERFLOW ... THIS CAUSES
  DISTORTION`. Over an hour that drifts.
- **Direct system audio capture.** We use ScreenCaptureKit. Meetily's macOS documentation requires
  the user to install BlackHole.
- **Speaker diarization.** Meetily has none — there is not one occurrence of "diariz" in its
  source. We have FluidAudio Sortformer, streaming with a batch fallback.

What meetily does have, and we do not, is the four capabilities below. They are worth taking, but
as additions to our pipeline rather than a replacement of it. Two of its implementation choices
are also deliberately declined:

- **Its polling device monitor.** It polls the device list on a timer because that is portable
  across three platforms. On macOS, Core Audio property listeners tell us the same thing without
  the latency or the wakeups.
- **Its Bluetooth-to-built-in microphone override.** Meetily silently records from the built-in
  microphone whenever a Bluetooth device is the default, because Bluetooth's variable sample rate
  desynchronises its ring buffer. Our per-source cursors do not have that failure mode, and
  recording from the laptop when the user has deliberately put on a headset is worse audio, not
  better. We take its `InputDeviceKind` detection, but spend it on buffer sizing and reconnection
  grace periods instead.

## Design

### 1. Capture becomes automatic

`RecordingMode` stops deciding what is captured and becomes a description of what happened.

The microphone runs for the whole session. A mute control remains, but it mutes — it is not a mode,
and it does not change what the session is.

System audio arms itself. A new `SystemAudioArmingMonitor` installs Core Audio property listeners
on `kAudioHardwarePropertyDefaultOutputDevice` (so it follows the user changing outputs) and on
`kAudioDevicePropertyDeviceIsRunningSomewhere` for whichever device that currently is. When any
application starts playing audio, the monitor reports it; a debounce of one second keeps a system
alert sound from arming a meeting.

On the first such report in a session, the ScreenCaptureKit tap starts and **stays running for the
rest of the session**. It is not torn down when playback pauses. A meeting has quiet stretches, and
stopping and restarting the tap across them would open a new `CaptureSegmentTimeline` entry each
time for no benefit. Arming late is already a case the timeline handles: the tap declares itself
with `beginSource(.system, atSessionTime: sessionElapsed)`, which is the same path a mid-meeting
system-audio toggle takes today.

`RecordingMode` is then derived. A session in which system audio armed is an `.onlineMeeting`;
otherwise it is `.inPerson`. `RecordingSessionManager` already does exactly this at line 608 — the
change is to make it the only way the value is set, and to delete the places the user is asked. The
mode continues to drive icons, sidebar filtering and card presentation, which is all the other
twenty files that read it use it for.

`.voiceNote` is the exception and stays explicit. It is not a capture configuration but a statement
of intent about what is being made, chosen at creation from a distinct entry point, and it is what
suppresses diarization for a single-speaker recording.

**Permission.** Screen-recording permission is currently requested when the user presses the system
audio toggle. With no toggle it must be requested when the tap first arms. Arming preflights with
`CGPreflightScreenCaptureAccess()`; if access has not been granted, the request is made once and
the outcome remembered, so a user who has declined is not asked again every meeting. A session
whose system audio never armed for want of permission records microphone audio and says so quietly
in the recording bar, rather than failing.

### 2. Conditioning and gating on the microphone branch

**Voice processing is enabled** on the input node via `setVoiceProcessingEnabled(true)`. This is
what replaces meetily's high-pass filter, RNNoise suppressor and −23 LUFS normaliser: one native
call that provides acoustic echo cancellation, noise suppression and automatic gain control, with
no C dependency to vendor.

Echo cancellation is the reason to do it. Without it the microphone picks up remote participants
coming out of the speakers, and that audio is transcribed a second time and presented to the
diarizer as a second channel carrying a voice it has already clustered elsewhere.

This transforms the input node itself, so the microphone audio that is saved for playback is
processed too. That is accepted deliberately: a recording without echo is the one worth keeping.

**A VAD gate sits in front of the transcriber, and only in front of the transcriber.**
`VadManager.processStreamingChunk` — already shipped by FluidAudio in `VadManager+Streaming.swift`,
and the same model already prewarmed for the post-recording pass — runs over the microphone
buffers. A 300 ms pre-roll ring is held so that the beginning of a word is not lost; on
`.speechStart` the ring and everything after it is released into
`SpeechTranscriberEngine.streamAudio`, and it keeps flowing until `.speechEnd` plus a 400 ms tail.

The gate must never be able to remove audio from anything but the transcriber. The file on disk and
`AudioTimelineMixer` receive every buffer, always. The saved recording is the meeting's timeline
and the diarizer needs the silence to place what follows it; a voice-activity model that is wrong
about one word should cost a wrong word, not a hole in the meeting.

Live timestamps derive from `sessionStartDate`, not from streamed frame counts
(`useAudioDrivenTiming` is false in the live path), so withholding buffers cannot skew them.

**Verified.** `SpeechAnalyzer` was measured against discontinuous input before this was settled:
two synthesised utterances separated by eight seconds of silence, transcribed once with the silence
streamed and once with it withheld. Both utterances survived being withheld, and the gated run was
the *more* accurate of the two — the continuous run rendered "The quarterly numbers came in higher"
as "that ours came in higher", where the gated run got it right. Silence is not context the model
needs; it is material it can misread.

The probe also established a second thing worth writing down: the analyzer returns nothing at all
when a session is fed faster than real time. Anything that replays captured audio through it has to
pace itself.

### 3. Device loss

A new `CaptureDeviceMonitor` observes `kAudioHardwarePropertyDevices` and
`kAudioHardwarePropertyDefaultInputDevice`. Property listeners, not a polling loop.

When the microphone in use disappears, a grace period starts, sized by `InputDeviceKind`: about
three seconds for Bluetooth, two for wired. Bluetooth devices drop briefly and constantly, and
switching away from a headset that is about to come back is worse than a two-second gap.

If the device returns within the grace period, capture resumes on it. If it does not, capture moves
to the new system default, declares itself with `beginSource` at the current `sessionElapsed`, and
opens a new `CaptureSegmentTimeline` entry — so the dead stretch stays a gap on the timeline
instead of shifting everything after it earlier. A non-blocking banner in `MeetingRecordingBar`
says which device is now live. Recording does not stop and the user is not asked anything.

`AudioRecorder.handleConfigChange()` is the seam this attaches to.

### 4. Checkpointing and silent recovery

**In-progress audio moves somewhere durable first.** Today it is written to
`FileManager.default.temporaryDirectory` with `URLFileProtection.complete`, which is set precisely
so a crashed session's audio does not linger. Recovery needs the opposite, so in-progress files
move to `Application Support/Logue/InProgress/<meetingID>/` and are moved to their final home when
the recording stops normally.

**A checkpoint is written every 30 seconds**, atomically, encrypted through `EncryptionManager` in
keeping with the rest of the data layer. `RecordingCheckpoint` is a `Codable` value carrying the
transcript segments so far, the `CaptureSegmentTimeline` for each source, `sessionStartDate`,
`timeOffset`, the meeting identifier and the in-progress file URLs — everything needed to describe
where the captured audio belongs, which is the part that is otherwise only computed at stop.

**Recovery is silent.** At launch `RecordingRecoveryService` looks for a checkpoint. Finding one, it
restores the meeting and its transcript, composes the audio from the checkpointed segment timeline,
and runs the normal post-recording pass over it. The meeting carries a note that it was recovered
and may be missing its final seconds. No dialog, no decision asked of the user.

`TranscriptReplacement` already governs the dangerous part. A recovered audio file may be shorter
than the meeting it belongs to, and the existing rule — that a pass may only replace the stretch of
transcript it can be shown to cover — is what stops a truncated recovery from deleting correct
transcript.

## Testing

The decision logic goes in pure types, tested with Swift Testing in the shape `CaptureSegmentTimeline`
and `TranscriptReplacement` already establish, so that almost none of it requires a live device:

- **Arming.** Debounce behaviour, arming once and staying armed, following an output device change,
  and the permission-refused path.
- **Gating.** The gate state machine as a pure function of VAD events: pre-roll release, tail, and
  the invariant that the file and mixer branches receive every buffer regardless of gate state.
- **Device loss.** That a loss shorter than the grace period produces no timeline entry, and one
  longer produces a gap at the right offset with subsequent audio still correctly placed.
- **Checkpointing.** Round-trip of `RecordingCheckpoint`, and that recovering from a checkpoint
  covering part of a session produces a transcript bounded by `TranscriptReplacement` rather than
  one that overwrites the whole meeting.

Integration coverage: a session that arms system audio mid-way lands the system audio at the right
offset; a recovered session's composed audio aligns with its transcript.

## Out of scope

- **Importing external audio.** Meetily can import and transcribe an existing file. Useful, not a
  pain today, and independent of everything above.
- **Replacing `SpeechTranscriber` with whisper.cpp.** Would buy model choice, wider language support
  and remove the macOS 26 floor. A separate decision with its own trade-offs.

## Files

New: `Engine/SystemAudioArmingMonitor.swift`, `Engine/CaptureDeviceMonitor.swift`,
`Engine/InputDeviceKind.swift`, `Engine/TranscriptionGate.swift`,
`Engine/RecordingCheckpoint.swift`, `Services/RecordingRecoveryService.swift`.

Changed: `Services/RecordingSessionManager.swift` (+ extensions), `Engine/AudioRecorder.swift`,
`Engine/SystemAudioCapture.swift`, `Views/Meeting/MeetingWorkspaceView.swift`,
`Views/CrossApp/CommandCenterNewMeetingView.swift`, `Views/Meeting/MeetingRecordingBar.swift`,
`App/AppConstants.swift`.

New files require `xcodegen generate`.
