# GyozaYap development log

GyozaYap is a native macOS meeting notetaker. It detects calls, transcribes both sides on the Mac, and writes AI notes.

## Releases

| Version | Date | Release |
|---|---|---|
| 1.0 | 2026-09-25 | [v1.0](https://github.com/alfredswift31-botty/GyozaYap/releases/tag/v1.0) |
| 1.0.1 | 2026-09-25 | [v1.0.1](https://github.com/alfredswift31-botty/GyozaYap/releases/tag/v1.0.1) |
| 1.0.2 | 2026-09-29 | [v1.0.2](https://github.com/alfredswift31-botty/GyozaYap/releases/tag/v1.0.2) |
| 1.1 | 2026-09-30 | [v1.1](https://github.com/alfredswift31-botty/GyozaYap/releases/tag/v1.1) |
| 1.1.1 | 2026-10-01 | [v1.1.1](https://github.com/alfredswift31-botty/GyozaYap/releases/tag/v1.1.1) |

## The brief
The goal was a Notion-AI-meeting-notes-style app, but better. It should:
- notice when a meeting starts;
- record and transcribe the whole team call;
- summarise it and pull out topics and important points;
- export to PDF, TXT or MD.

The user asked whether AI was needed, then whether Apple Intelligence could be the in-house AI. Yes: it's the default engine.

## Key decisions
- **Two separate streams, so no speaker guessing.** Your voice comes from the microphone and everyone else from a Core Audio process tap. Every line is labelled Me or Them.
- **Tap-only aggregate device.** An aggregate that included the output device put a headset mic's streams before the tap, which left "Them" silent on headsets. That's fixed (commit 0ce10f4), with per-cycle buffer checks and a watchdog that rebuilds a broken aggregate.
- **One clock.** `AudioTimeline` stamps both sources against a shared clock, so long silences don't compress the timeline.
- **On-device transcription:**
  - macOS 26: `SpeechAnalyzer` / `SpeechTranscriber`.
  - macOS 15: `SFSpeechRecognizer`.
- **AI:**
  - Apple Intelligence through FoundationModels is the default. It's free, private and offline. Long meetings use map-reduce to fit the 4096-token context.
  - FoundationModels is weak-linked so the app still launches on macOS 15. CI checks this.
  - Claude is optional, with the key kept in the Keychain.
- **Consent:** the detection panel asks before recording (auto-start is an option) and never steals focus from the call.

## What 1.0 includes
- Call detection:
  - Teams, Zoom, Webex, Slack, FaceTime and Discord;
  - calls in Chrome, Safari, Edge, Arc, Brave or Firefox.
- While recording:
  - a live transcript, a notes pad, and ★ Idea / ✓ Decision / ? Question markers (⌘1–3);
  - a menu bar recording indicator;
  - autosave every 30 s.
- AI notes: TL;DR, decisions, action items (owners and dates only when someone said them), key points, open questions and topics.
  - Styles: Meeting, Brainstorm and Research.
  - **Ask** answers questions with timestamps, and **Search** covers all meetings.
- Export: Markdown with YAML front matter (also copy as Markdown), paginated PDF, plain text and SRT.

## Fixes during the build
- Timeline compression during silence, fixed by `AudioTimeline`.
- Full-file writes on every keystroke, replaced by a 400 ms debounced save that also flushes on quit; deleting a meeting cancels its pending writes.
- Stereo capture that kept only the left channel, fixed with `converter.downmix = true`.
- Silent failures from the floating panel now show a message toast.
- Compiler warnings: a raw-pointer warning, fixed with a `BitwiseCopyable` constraint, and NSLock use in an async context.
- Releases were titled "Gyoza Island", and the README wrongly claimed Return works in the panel. Both corrected.

## 1.0.1
- Adds the user's app icon. The artwork's rounded square was cut out, placed on Apple's macOS icon grid, and exported at every size.
- CI now fails if the icon isn't compiled into the app.

## 1.0.2: crash when a call is detected (macOS 27)
The user's first real team call crashed the app several times. The crash report showed an abort in `-[NSWindow _postWindowNeedsUpdateConstraints]`, about 3 s after launch. The detector checks for calls every 3 s, so the app crashed as soon as it opened the "Record this call?" corner panel.

- **Cause:** the panel let SwiftUI size its window (`NSHostingController` with `sizingOptions = .preferredContentSize`, in a titled panel with full-size content). Each frame change moved the title bar's safe area, which asked for new constraints, which moved the frame again. On macOS 27 this never settled, so AppKit threw.
- **First attempt:** only turning off `sizingOptions` wasn't enough. A new test showed the hosting view, as the window's content view, still grew the panel by the title bar's height: 370 pt became 402 pt on macOS 26.
- **Fix:** the SwiftUI view is measured once, then placed inside a plain container view and follows it by autoresizing. Only `FloatingPanel` sets the panel's frame. Commits 753df89 and 8a25d17.
- **Tests:** `FloatingPanelTests` checks the panel keeps its measured size through layout passes. CI runs macOS 26, which can't reproduce the macOS 27 loop, so the proof is a real call on the user's Mac.
- **CI:** a failing test now prints its failure text, taken from the result bundle. xcodebuild's log only names the test.
- **Workaround for 1.0.1:** turn off call detection and start recordings from the main window. That path never opens the corner panel.
- **Not the cause:** the user suspected the call app was blocking recording. The report rules this out: the crash is entirely in window layout, the abort was called by GyozaYap itself, and no other process touched it.

## 1.1: redesign (30 Sep 2026)
The user asked for a modern minimalist redesign: the old UI was "flat and boring". They asked to use the taste-skill (github.com/Leonxlnx/taste-skill), and gave a Swiss poster as a reference: black ground, a huge lowercase word, small bold uppercase labels in columns, a strict left grid, no accent colour. 1.0.2 was already the crash fix, so the redesign ships as 1.1.

- **Design system:** `GyozaYap/Design/Theme.swift`.
  - Tokens: monochrome colours plus one red, `live`, used only while recording and on Stop/Delete. San Francisco and SF Mono sizes; spacing; radius 5 on controls and 8 on containers; motion.
  - Components: `MetaPair`, `SectionLabel`, `Hairline`, `SpeakerTag`, `KeyCap`, `LiveDot`, `EmptyState`, and the button styles `.primary`, `.quiet` and `.live`.
- **Brief:** `docs/DESIGN.md` is the contract for the agents: principles, copy, states and guardrails.
- **Adapting the taste-skill:** it's written for websites, so its principles were adapted for a native Mac app. No custom fonts or web imagery, and `NavigationSplitView`, toolbar, menus and shortcuts all stay.
- **Three agents in parallel,** each on its own branch and owning its own files:
  - `redesign/library`: sidebar, empty and no-selection states, menu bar.
  - `redesign/meeting`: meeting detail.
  - `redesign/capture`: recording, start sheet, toasts, Settings.
  - They merged without conflicts.
- **Behaviour changes, deliberately small:**
  - The recording screen's `HSplitView` became a fixed notes column, 260–320 pt. The split view made the page wider than the detail pane, which clipped Stop.
  - Copy changes on the start sheet: "Record this call?", "Copy chat notice".
  - A done action item is struck through.
  - Settings "Recording" is split into Recording and General.
- **`EmptyState` has a minimum width.** The library agent found that a narrow measuring pass made the wrapping message ask for more height than the window had. `NavigationSplitView` then laid its content out off screen.

### Snapshot pipeline (for reviewing design from CI)
`UISnapshotTests` renders every screen in light and dark (01–08, plus 20 sidebar and 21 no-selection). CI prints them into the log as base64 JPEGs, and `scripts/decode-snapshots.py <log> <dir>` decodes them. Getting it right took four fixes:
1. `cacheDisplay` draws only AppKit, so SwiftUI text and shapes were blank. The snapshots now render the layer tree with `layer.render(in:)` at 2x.
2. Parametrised cases ran in parallel and spun the run loop into each other's windows. Fixed with `@Suite(.serialized)`.
3. The rendered layers have no window background, so dark text landed on transparent pixels that turned white as JPEG. The window background is now painted first, for the right appearance.
4. After a display pass AppKit marks the host layer geometry-flipped, and `render(in:)` ignores that on the root layer. The context is now flipped when the layer says so. (Ordering the window in wasn't the cause.)

Two known limitations:
- The macOS 26 glass sidebar renders as a blank panel. `20-sidebar` renders the list on its own instead.
- CI uses legacy, always-visible scrollbars, so scroll views are about 16 pt narrower there than on a trackpad Mac.

## 1.1.1: invisible text cursor in dark mode (1 Oct 2026)
The user reported that the sidebar search field had no blinking cursor. Everything else in 1.1 looked good on their Mac (macOS 27, dark mode), including the glass sidebar next to the flat canvas.

- **Cause:** macOS draws the insertion point in the app's accent colour. 1.1 set the dark accent to graphite #585857. Sampled from the user's screenshot, the search field is #545151, a contrast of 1.1:1. Every text field was affected; the search field was simply the worst.
- **Fix:** the dark accent is now #AAAAAE, 3.4:1 on the search field. A selected sidebar row is filled with the accent, so its text now uses `Theme.inkInverse` rather than the system's light hierarchical styles.
- **Tests:** `AccentColorTests` check the accent's contrast as the cursor (on the search field and on `Theme.surface`) and as a selection fill (under `inkInverse`), in both appearances. The test was pushed first and failed on 1.1 (run 36791552411: 1.10, 2.44 and 2.65); it passes with the fix (run 36791576120).
- **Verified by the user** after installing 1.1.1: the cursor now shows in the search field.
- **Unverified:** whether the checkbox's white tick reads well on the lighter dark accent (action items), and the selected sidebar row's dark text on the lighter fill.

## Verified
CI is green (1.1.1):
- The unit tests pass, including the snapshot renders (every screen, light and dark) and the accent-contrast checks. Before 1.1 there were 33, covering the audio timeline, transcription logic, formatting, storage, export and PDF, and the AI prompts.
- The Release build passes.
- The built app is checked for its privacy strings, entitlements, the weak link to FoundationModels, the icon, and the minimum macOS version.

### On a real Mac (28 Sep 2026, macOS 27, headphones, GyozaYap 1.0.1)
The user did a 1.5-minute solo test: they started a recording by hand, played a podcast on the Mac and talked over it.
- The mic was transcribed as **Me** and the Mac's audio as **Them**, and the two sides interleaved correctly by time. This confirms the tap-only system-audio capture works with headphones.
- Apple Intelligence wrote the notes on the device (the notes footer says so). Those notes had quality problems:
  - Both action items were made up. Nobody gave a task. The model still made "Me" the owner and gave the meeting date as the due date, even though the prompt says never to invent either.
  - One "open question" had been answered in the transcript: who pre-ordered.
- A first attempt played the podcast from a phone. That audio isn't Mac system audio, so there was no "Them", which is expected. Worth a line in the README.

## Not verified
- The 1.1 redesign on a real Mac: the user checked the library screen and the search cursor (1.1.1). Still unchecked: the meeting, recording and start-panel screens with real data, the checkbox tick and selected-row text on the lighter dark accent, the menu bar menu's sections (it's a real NSMenu, so no snapshot shows it), and the text tab row with Full Keyboard Access and VoiceOver.
- The 1.0.2 fix, on a real call under macOS 27. Detection itself does work: it found the call, and the panel it then opened is what crashed.
- Capture when a call app switches audio devices mid-call, for example a Bluetooth headset going into call mode.
- Capture through speakers, without headphones.
- Ask on macOS 27.
- Note quality on a real multi-person meeting longer than the 5,000-character single pass, which is where the map-reduce path starts.

## Next steps (agreed, not started)
1. **Waiting on the user:** a real call on macOS 27 with 1.1.1 (it carries the 1.0.2 fix), to confirm the crash fix. The quickest check is to join a call first, then open GyozaYap: the corner panel should appear and stay open.
2. **Stop made-up action items:** have Apple Intelligence quote the transcript words behind each action item. Then drop any item whose quote isn't in the transcript, and blank any due date that isn't in the quote. This is a hard check rather than another prompt instruction. Test it against the 28 Sep transcript, where both action items were invented.
3. **Better search for Ask on long meetings:** past about 6,000 characters (8–10 minutes), Ask only gives the model the lines that share exact words with the question. A synonym ("processor" vs "chip") finds nothing. A broad question ("what was decided overall?") falls back to roughly the first 8 minutes. Options are to search the notes as well as the transcript, or to match synonyms and word stems.
4. **Show whether the call audio is arriving:** a level meter or indicator for the "Them" side, plus an early warning when it only gets digital silence. Today a missing permission and a real bug look the same.
5. **Show live status in Settings:** whether Apple Intelligence is ready on this Mac right now, not just the fixed list of requirements.

### Testing Apple Intelligence (plan given to the user, 28 Sep)
Write down the right answers before recording, so the notes are scored against them instead of just read.
- **Three recordings:**
  - Planted items: a task with an owner and a date, a task with no date, a decision, and an unanswered question.
  - A 15–20 minute recording, long enough to use the part-by-part path.
  - A podcast only, where there should be no action items at all.
- **Scoring:** mark each planted item found, missed or invented. Invented is the worst outcome.
- **Ask:** check a specific detail, a trap question with no answer in the transcript, a false premise, a synonym on the long recording, and a broad question.
- **Offline:** generate notes again with Wi-Fi off, to prove it runs on the Mac.
- **Privacy:** results come back as notes plus the answer key. Transcripts of work meetings shouldn't be pasted into a cloud session unredacted.

6. **Redesign follow-ups:**
   - Inline errors for Ask and notes generation, in `inkSecondary` next to the thing that failed. Today they still use the "Something went wrong" alert, which the 1.1 guardrails kept as is.
   - Consider restoring a draggable divider on the recording screen. 1.1 fixed the notes column at 260–320 pt, because the old split view was wider than the detail pane and clipped Stop.
   - Optional: move `GutterRow` and `measure()` out of MeetingDetailView into Theme, if other screens use the timestamp-column grid.

## Ideas for next time
- Speaker separation within "Them" (diarization).
- Calendar integration to name meetings automatically.

## Working notes
- Work goes on `develop`; releases come from `main`.
- Design changes follow `docs/DESIGN.md`, using the tokens and components in `GyozaYap/Design/Theme.swift`. To review one:
  1. Push, and CI renders every screen in `UISnapshotTests`.
  2. Fetch the build job's log.
  3. Run `python3 scripts/decode-snapshots.py <log> .snapshots/<name>` and look at the JPEGs. `.snapshots/` is gitignored.
- To release: run Actions › Build › Run workflow on `main` with `release_tag: vX.Y.Z`.
