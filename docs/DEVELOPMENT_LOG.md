# GyozaYap development log

GyozaYap is a native macOS meeting notetaker. It detects calls, transcribes both sides on the Mac, and writes AI notes.

## Releases

| Version | Date | Release |
|---|---|---|
| 1.0 | 2026-09-25 | [v1.0](https://github.com/alfredswift31-botty/GyozaYap/releases/tag/v1.0) |
| 1.0.1 | 2026-09-25 | [v1.0.1](https://github.com/alfredswift31-botty/GyozaYap/releases/tag/v1.0.1) |
| 1.0.2 | 2026-09-29 | [v1.0.2](https://github.com/alfredswift31-botty/GyozaYap/releases/tag/v1.0.2) |

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

## Verified
CI is green:
- 33 unit tests pass, covering the audio timeline, transcription logic, formatting, storage, export and PDF, and the AI prompts.
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
- The 1.0.2 fix, on a real call under macOS 27. Detection itself does work: it found the call, and the panel it then opened is what crashed.
- Capture when a call app switches audio devices mid-call, for example a Bluetooth headset going into call mode.
- Capture through speakers, without headphones.
- Ask on macOS 27.
- Note quality on a real multi-person meeting longer than the 5,000-character single pass, which is where the map-reduce path starts.

## Ideas for next time
- Speaker separation within "Them" (diarization).
- Calendar integration to name meetings automatically.

## Working notes
- Work goes on `develop`; releases come from `main`.
- To release: run Actions › Build › Run workflow on `main` with `release_tag: vX.Y.Z`.
