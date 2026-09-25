import SwiftUI

struct RecordingView: View {
    @EnvironmentObject private var recorder: RecordingController

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                liveTranscript
                    .frame(minWidth: 320)
                notesPad
                    .frame(minWidth: 260, idealWidth: 320)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(recorder.phase == .recording ? Color.red : Color.secondary)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(recorder.liveMeeting?.title ?? "Recording")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsedText(at: context.date))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            ForEach(recorder.statusNotes, id: \.self) { note in
                Label(note, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .frame(maxWidth: 260, alignment: .trailing)
            }
            Button(role: .destructive) {
                Task { await recorder.stop() }
            } label: {
                Label(recorder.phase == .stopping ? "Saving…" : "Stop", systemImage: "stop.fill")
            }
            .keyboardShortcut(".", modifiers: .command)
            .controlSize(.large)
            .disabled(recorder.phase != .recording)
        }
        .padding(16)
    }

    private var liveTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    let turns = TranscriptFormatting.mergedTurns(recorder.liveSegments)
                    if turns.isEmpty && recorder.partialText.values.allSatisfy(\.isEmpty) {
                        Text(recorder.phase == .starting
                            ? (recorder.startingStatus ?? "Getting ready…")
                            : "Listening… the transcript appears here as people talk.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
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
                .padding(16)
            }
            .onChange(of: recorder.transcriptRevision) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func line(_ speaker: Speaker, _ time: String, _ text: String, isFinal: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(time)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
            Text(speaker.label)
                .bold()
                .foregroundStyle(speaker == .me ? Color.accentColor : Color.orange)
                .frame(width: 44, alignment: .leading)
            Text(text)
                .foregroundStyle(isFinal ? .primary : .secondary)
                .textSelection(.enabled)
        }
    }

    private var notesPad: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes").font(.headline)
            TextEditor(text: $recorder.liveNotes)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            Text("Mark this moment").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                markerButton(.idea, key: "1")
                markerButton(.decision, key: "2")
                markerButton(.question, key: "3")
            }
            if !recorder.liveMarkers.isEmpty {
                Text(recorder.liveMarkers.map { "\($0.kind.symbol) \(TranscriptFormatting.timestamp($0.time))" }.joined(separator: "   "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
    }

    private func markerButton(_ kind: Bookmark.Kind, key: KeyEquivalent) -> some View {
        Button {
            recorder.addMarker(kind)
        } label: {
            Text("\(kind.symbol) \(kind.title)")
                .frame(maxWidth: .infinity)
        }
        .keyboardShortcut(key, modifiers: .command)
        .help("\(kind.title) (⌘\(String(key.character)))")
        .disabled(recorder.phase != .recording)
    }

    private func elapsedText(at date: Date) -> String {
        guard let start = recorder.recordingStartedAt else { return "0:00" }
        return TranscriptFormatting.timestamp(date.timeIntervalSince(start))
    }
}
