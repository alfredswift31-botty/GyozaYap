import SwiftUI

/// The live recording. One big thing, the elapsed clock, with the meeting's
/// metadata set beside it as label-over-value columns; the transcript runs on
/// the page's left grid, and the notes pad (the screen's one real container)
/// sits in a column on the right.
struct RecordingView: View {
    @EnvironmentObject private var recorder: RecordingController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()
            HStack(alignment: .top, spacing: 0) {
                liveTranscript
                    .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Hairline(axis: .vertical)
                notesPad
                    .frame(minWidth: 240, idealWidth: 300, maxWidth: 300, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.canvas)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .center, spacing: Theme.Space.s) {
                LiveDot(isLive: recorder.phase == .recording)
                Text(phaseLabel)
                    .font(Theme.Typeface.label)
                    .tracking(Theme.Typeface.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(recorder.phase == .recording ? Theme.ink : Theme.inkTertiary)
                Spacer(minLength: Theme.Space.l)
                KeyCap("⌘.")
                Button(role: .destructive) {
                    Task { await recorder.stop() }
                } label: {
                    Label(recorder.phase == .stopping ? "Saving…" : "Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.live)
                .keyboardShortcut(".", modifiers: .command)
                .disabled(recorder.phase != .recording)
            }

            HStack(alignment: .lastTextBaseline, spacing: Theme.Space.xxl) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsedText(at: context.date))
                        .displayStyle()
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityLabel("Elapsed time \(elapsedText(at: context.date))")
                }
                HStack(alignment: .lastTextBaseline, spacing: Theme.Space.xl) {
                    MetaPair(label: "Meeting", value: recorder.liveMeeting?.title ?? "Recording")
                        .layoutPriority(1)
                    if let source = recorder.liveMeeting?.sourceApp {
                        MetaPair(label: "Source", value: source)
                    }
                    if let started = recorder.liveMeeting?.startedAt {
                        MetaPair(label: "Started", value: started.formatted(date: .omitted, time: .shortened))
                    }
                }
            }

            if !recorder.statusNotes.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    ForEach(recorder.statusNotes, id: \.self) { note in
                        Label(note, systemImage: "exclamationmark.triangle")
                            .font(Theme.Typeface.meta)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(2)
                            .frame(maxWidth: Theme.Space.measure, alignment: .leading)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Space.page)
        .padding(.top, Theme.Space.xl)
        .padding(.bottom, Theme.Space.xl)
    }

    private var phaseLabel: String {
        switch recorder.phase {
        case .idle: "Not recording"
        case .starting: "Starting"
        case .recording: "Recording"
        case .stopping: "Saving"
        }
    }

    // MARK: Transcript

    private var liveTranscript: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Transcript")
                .padding(.horizontal, Theme.Space.page)
                .padding(.top, Theme.Space.xl)
                .padding(.bottom, Theme.Space.m)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Space.l) {
                        let turns = TranscriptFormatting.mergedTurns(recorder.liveSegments)
                        if turns.isEmpty && recorder.partialText.values.allSatisfy(\.isEmpty) {
                            waitingLine
                        }
                        ForEach(turns) { turn in
                            line(turn.speaker, TranscriptFormatting.timestamp(turn.start), turn.text, isFinal: true)
                        }
                        ForEach(Speaker.allCases, id: \.self) { speaker in
                            if let partial = recorder.partialText[speaker], !partial.isEmpty {
                                line(speaker, "…", partial, isFinal: false)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, Theme.Space.page)
                    .padding(.top, Theme.Space.xs)
                    .padding(.bottom, Theme.Space.xl)
                }
                .onChange(of: recorder.transcriptRevision) { _, _ in
                    withAnimation(Theme.Motion.quick) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Before the first words: one quiet line. The clock is this screen's big word.
    @ViewBuilder
    private var waitingLine: some View {
        if recorder.phase == .starting {
            HStack(spacing: Theme.Space.s) {
                ProgressView().controlSize(.small)
                Text(recorder.startingStatus ?? "Getting ready…")
            }
            .font(Theme.Typeface.body)
            .foregroundStyle(Theme.inkSecondary)
        } else {
            Text("Listening… the transcript appears here as people talk.")
                .font(Theme.Typeface.body)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private func line(_ speaker: Speaker, _ time: String, _ text: String, isFinal: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(time)
                .font(Theme.Typeface.mono)
                .monospacedDigit()
                .foregroundStyle(Theme.inkTertiary)
                .frame(width: 44, alignment: .leading)
            SpeakerTag(speaker: speaker)
                .frame(width: 40, alignment: .leading)
            Text(text)
                .font(Theme.Typeface.body)
                .lineSpacing(Theme.Typeface.bodyLineSpacing)
                .foregroundStyle(isFinal ? Theme.ink : Theme.inkTertiary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: Theme.Space.measure, alignment: .leading)
        }
    }

    // MARK: Notes pad

    private var notesPad: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionLabel("Notes")
            TextEditor(text: $recorder.liveNotes)
                .font(Theme.Typeface.body)
                .lineSpacing(Theme.Typeface.bodyLineSpacing)
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .padding(Theme.Space.s)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.container))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.container).strokeBorder(Theme.hairline))

            SectionLabel("Mark this moment")
                .padding(.top, Theme.Space.m)
            VStack(spacing: Theme.Space.s) {
                markerButton(.idea, key: "1")
                markerButton(.decision, key: "2")
                markerButton(.question, key: "3")
            }
            if !recorder.liveMarkers.isEmpty {
                placedMarkers
                    .padding(.top, Theme.Space.xs)
            }
        }
        .padding(Theme.Space.xl)
    }

    private func markerButton(_ kind: Bookmark.Kind, key: KeyEquivalent) -> some View {
        Button {
            recorder.addMarker(kind)
        } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: kind.systemImage)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 16)
                Text(kind.title)
                Spacer(minLength: Theme.Space.s)
                KeyCap("⌘\(String(key.character))")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.quiet)
        .keyboardShortcut(key, modifiers: .command)
        .help("\(kind.title) (⌘\(String(key.character)))")
        .accessibilityLabel(kind.title)
        .disabled(recorder.phase != .recording)
    }

    /// The markers placed so far: symbol and time in mono, wrapping.
    private var placedMarkers: some View {
        let markers = recorder.liveMarkers.reduce(Text(verbatim: "")) { text, marker in
            Text("\(text)\(Image(systemName: marker.kind.systemImage)) \(TranscriptFormatting.timestamp(marker.time))    ")
        }
        return markers
            .font(Theme.Typeface.mono)
            .monospacedDigit()
            .foregroundStyle(Theme.inkTertiary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(recorder.liveMarkers
                .map { "\($0.kind.title) at \(TranscriptFormatting.timestamp($0.time))" }
                .joined(separator: ", "))
    }

    private func elapsedText(at date: Date) -> String {
        guard let start = recorder.recordingStartedAt else { return "0:00" }
        return TranscriptFormatting.timestamp(date.timeIntervalSince(start))
    }
}
