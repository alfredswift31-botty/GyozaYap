# GyozaYap

Make meeting yapping fun. GyozaYap is a native macOS meeting notetaker. It notices when your call starts, transcribes both you and everyone else **on your Mac**, and turns the yap into a summary, decisions, action items and a searchable transcript. No bot joins your call, and no account or API key is needed.

## Version 1.0

### Record the whole call, not just your side

- **Your voice** comes from the microphone; **everyone else** comes straight from your Mac's audio output through a Core Audio process tap. Because the two are separate streams, every line is labeled **Me** or **Them** without guessing.
- Works with Microsoft Teams, Zoom, Webex, Slack, FaceTime, Discord, and calls in Chrome, Safari, Edge, Arc, Brave or Firefox.
- The call audio needs only the **System Audio Recording** permission, not Screen Recording.
- Works with AirPods and USB headsets. Both sides are stamped against one clock, so the transcript stays in order even after long silences.
- Not wearing headphones? The mic also hears the other side through your speakers. GyozaYap removes those echoed lines when you stop.

### It notices your meetings

When a call app starts using your microphone, a small panel appears in the corner: *"Teams is using your microphone. Record this call?"* One click starts recording. The panel never steals keyboard focus from your call. If you'd rather it just start, turn on **Start recording automatically** in Settings.

### While you talk

- A live transcript that follows the conversation.
- A notes pad for your own notes.
- Marker buttons for the moment something matters: **★ Idea** (⌘1), **✓ Decision** (⌘2), **? Question** (⌘3). The AI treats these as strong hints.
- A menu bar icon so you always know it's recording. ⌘. stops.
- Autosave every 30 seconds, so a crash can't eat your meeting.

### After the call

AI notes are written automatically:

- **TL;DR**
- **Decisions**
- **Action items**, with owners and due dates only when someone actually said them
- **Key points**
- **Open questions**
- **Topics**

Pick a notes style per meeting:

- **Meeting**: decisions and follow-ups.
- **Brainstorm**: every idea and who raised it, the ones picked, and threads left unexplored.
- **Research**: findings with quotes, unanswered questions and contradictions.

**Ask** answers questions about a meeting ("What did Sam promise?") with timestamps. **Search** looks across every meeting's transcript and notes.

### Export

- **Markdown** with YAML front matter, which pastes cleanly into Notion or drops into Obsidian (also *Copy as Markdown*).
- **PDF**, paginated, for sharing.
- **Plain text** transcript.
- **SRT** subtitles.

## The AI: Apple Intelligence, on your Mac

Notes and answers come from **Apple Intelligence's on-device model** (Apple's Foundation Models framework): free, private, offline, with nothing to set up. It needs:

- macOS 26 (Tahoe) or later
- An Apple silicon Mac (M1 or newer)
- Apple Intelligence turned on in System Settings

The on-device model has a small working memory (about 4,000 tokens), so long meetings are read in parts and the part notes are then combined. That's slower, and notes on very long meetings are simpler than a large cloud model would write.

**Optional:** add your own Claude API key in Settings for stronger notes on long meetings. With a key, the transcript text (never audio) is sent to Anthropic. Without a key, nothing leaves your Mac.

## Requirements

| | macOS 15.6 (Sequoia) | macOS 26 (Tahoe) or later |
|---|---|---|
| Recording, both sides | ✓ | ✓ |
| On-device transcription | ✓ Apple's older on-device recognizer (turn on Dictation to download it) | ✓ Apple's new SpeechAnalyzer |
| AI notes and Ask | Only with a Claude key | ✓ Apple Intelligence |

## Install

1. Download `GyozaYap.zip` from the latest [release](https://github.com/alfredswift31-botty/GyozaYap/releases), or from the newest green run of the [Build workflow](https://github.com/alfredswift31-botty/GyozaYap/actions/workflows/build.yml).
2. Unzip it and drag **GyozaYap.app** into Applications.
3. The build is ad-hoc signed, not notarized. The first time, right-click the app and choose **Open**, or allow it under System Settings › Privacy & Security.
4. On your first recording, allow **Microphone**, **Speech Recognition** and **System Audio Recording**.

## Privacy and consent

- Audio is transcribed on your Mac and never saved. Transcripts and notes are stored as JSON in `~/Library/Containers/com.gyoza.GyozaYap/Data/Library/Application Support/GyozaYap/Meetings`.
- Many places require everyone on a call to know or agree before it's recorded. GyozaYap asks "Do the others know?" before each recording, stores the answer with the meeting, and gives you a ready-made notice to paste into the call chat. Being honest with people is on you.

## Good to know

- **Headphones** give the cleanest transcript.
- The call audio tap hears all audio on your Mac (except GyozaYap), so pause music or videos during a call.
- If "Them" stays empty, check System Settings › Privacy & Security › Screen & System Audio Recording.
- On-device speech recognition doesn't cover every language. Pick yours in Settings.

## Building

Open `GyozaYap.xcodeproj` in Xcode 26 and run the **GyozaYap** scheme. Unit tests (Swift Testing) cover formatting, storage, exports, PDF pagination, echo removal, phrase grouping, question retrieval, call-app detection and the AI response parsing. CI builds every push on a macOS 26 runner and also checks the privacy strings, the entitlements, and that FoundationModels is weak-linked so the app still launches on macOS 15.

## Related

[Gyoza Island](https://github.com/alfredswift31-botty/GyozaIsland) is a notch panel for music, files and a mirror. [Gyoza Budget](https://github.com/alfredswift31-botty/GyozaBudget) is a SwiftUI budgeting app for iOS.
