# GyozaYap design (1.1)

**Design read:** a full redesign of a native macOS meeting-notes tool for professionals, in a Swiss / International Typographic language. It uses native SwiftUI, San Francisco and SF Mono, monochrome tokens and one semantic colour.

**Dials** (from taste-skill): variance 5, motion 3, density 4.

**Reference:** a Swiss-style poster.
- Near-black ground and off-white type.
- One grotesque typeface doing everything through size and weight.
- A huge lowercase word with tight tracking.
- Small bold uppercase labels over plain text, set in columns like data.
- A strict left-aligned grid and a lot of empty space.
- No decoration and no accent colour.

The tokens and components live in `GyozaYap/Design/Theme.swift`. **Use them. Don't write raw colours, font sizes or radii in a view.**

## Principles
1. **Type is the design.** Hierarchy comes from size, weight and tracking, not from boxes, fills or colour. One family: San Francisco (`.system`), with SF Mono for timestamps and durations. No custom fonts.
2. **Monochrome.** `Theme.canvas`, `ink`, `inkSecondary`, `inkTertiary`, `hairline`, `wash`, `surface`. The only colour is `Theme.live` (red). It is reserved for "recording is live" and for destructive actions. Speakers, tags and states are told apart by weight and position, never by colour.
3. **Hairlines, not cards.** Separate with `Hairline()`, `SectionLabel` or space. A container exists only when it really is one: a text field, or the notes pad during recording. No shadows, no gradients, no glass.
4. **Left-aligned grid.** Pages have a 40 pt margin (`Theme.Space.page`). Running text keeps a readable measure of about 640 pt. Nothing is centred except inside a control.
5. **Labels over values.** Metadata is set as `MetaPair` columns (DATE / DURATION / SOURCE / NOTES), like the poster's top row. Section headers are `SectionLabel`: small bold uppercase with a hairline running right.
6. **One big word per screen, at most.** `EmptyState` and the recording clock use `displayStyle()`: large, lowercase, tight tracking. Everything else is quiet.
7. **Native where it matters.** Keep `NavigationSplitView`, the toolbar, menus, keyboard shortcuts, `Form` behaviour in Settings, VoiceOver labels and the macOS window chrome. Keep the app a Mac app; don't imitate a website.
8. **Both appearances.** Every screen must work in light and dark mode. The tokens handle this; never hard-code one appearance.

## Shape and motion
- **Radius:** 5 pt on controls and 8 pt on containers (`Theme.Radius`), nothing else. No pills or capsules.
- **Buttons:**
  - `.buttonStyle(.primary)`: ink fill. At most one per screen, for the main action.
  - `.buttonStyle(.live)`: red. For Stop recording and Delete.
  - `.buttonStyle(.quiet)`: a hairline outline, for everything else.
  - Plain text buttons are fine in toolbars and menus.
- **Motion:** `Theme.Motion.quick` (0.18 s) for state changes, and a 0.98 scale on press, which the button styles already do. `LiveDot` breathes while recording. No other ambient animation. Respect Reduce Motion.

## Copy
- Sentence case everywhere except labels, which `labelStyle()` uppercases.
- Plain and specific. No "Oops", no exclamation marks, no "Elevate/Seamless/Unleash".
- **Empty-state words are lowercase and concrete:** "no meetings", "listening", "nothing yet". The line under them says what to do.
- No emoji. Bookmarks use SF Symbols (`Bookmark.Kind.systemImage`), not the ★ ✓ ? glyphs; those stay in the model for exports.

## Icons
SF Symbols only, at the default weight, and only where they add meaning, such as toolbar actions and bookmark kinds. Don't put an icon in front of every metadata value; the label already says what it is.

## States
Every screen needs designed empty, loading and error states:
- **Loading:** a single line of text with a small `ProgressView().controlSize(.small)`, not a large spinner.
- **Error:** inline, near the thing that failed, in `inkSecondary`, with `live` only for real failures.

## Guardrails (do not break)
- **No behaviour changes.** Bindings, actions, keyboard shortcuts, accessibility labels, the recorder and notes logic stay as they are. This is a visual redesign.
- **`FloatingPanel` measures its content once** (the macOS 27 crash fix in 1.0.2). The toasts and the start sheet shown in it must keep a fixed width and must not change height after they appear.
- No new dependencies. Swift 5 mode, default MainActor isolation.
- Keep the snapshot entry points: `RootView(initialSelection:)`, `MeetingDetailView(meetingID:initialTab:)` and `RecordingController.showPreviewRecording`.
