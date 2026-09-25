import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MeetingDetailView: View {
    let meetingID: Meeting.ID
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var notesService: NotesService

    @State private var tab: Tab = .notes
    @State private var errorMessage: String?
    @State private var question = ""
    @State private var answer: String?
    @State private var isAsking = false
    @State private var transcriptFilter = ""

    nonisolated enum Tab: String, CaseIterable, Identifiable {
        case notes = "Notes"
        case transcript = "Transcript"
        case ask = "Ask"
        var id: String { rawValue }
    }

    var body: some View {
        if let meeting = store.meeting(id: meetingID) {
            VStack(alignment: .leading, spacing: 0) {
                header(meeting)
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

                Divider()

                switch tab {
                case .notes: notesTab(meeting)
                case .transcript: transcriptTab(meeting)
                case .ask: askTab(meeting)
                }
            }
            .toolbar { toolbar(meeting) }
            .alert("Something went wrong", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        } else {
            ContentUnavailableView("Meeting not found", systemImage: "questionmark.folder")
        }
    }

    // MARK: Header

    private func header(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Title", text: binding(meeting, \.title))
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
            HStack(spacing: 12) {
                Label(meeting.startedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                Label(TranscriptFormatting.timestamp(meeting.duration), systemImage: "clock")
                if let app = meeting.sourceApp {
                    Label(app, systemImage: "video")
                }
                Picker("Mode", selection: binding(meeting, \.mode)) {
                    ForEach(NotesMode.allCases) { Text($0.title).tag($0) }
                }
                .fixedSize()
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    // MARK: Notes

    private func notesTab(_ meeting: Meeting) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if notesService.isWorking(on: meeting.id) {
                    ProgressView(notesService.progressText(for: meeting.id))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let notes = meeting.notes {
                    generatedNotes(notes, meeting: meeting)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No AI notes yet").font(.headline)
                        Text(notesService.readinessMessage ?? "Generate a summary, decisions and action items from the transcript.")
                            .foregroundStyle(.secondary)
                        Button("Generate notes") { generate(meeting) }
                            .disabled(meeting.segments.isEmpty)
                    }
                }

                if !meeting.bookmarks.isEmpty {
                    section("Marked moments") {
                        ForEach(meeting.bookmarks.sorted(by: { $0.time < $1.time })) { marker in
                            HStack(alignment: .firstTextBaseline) {
                                Text(marker.kind.symbol).bold()
                                Text(TranscriptFormatting.timestamp(marker.time)).monospacedDigit().foregroundStyle(.secondary)
                                Text(marker.note.isEmpty ? marker.kind.title : marker.note)
                            }
                        }
                    }
                }

                section("My notes") {
                    TextEditor(text: binding(meeting, \.userNotes))
                        .font(.body)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    private func generatedNotes(_ notes: MeetingNotes, meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            section("TL;DR") { Text(notes.tldr) }
            bulletSection("Decisions", notes.decisions)
            if !notes.actionItems.isEmpty {
                section("Action items") {
                    ForEach(notes.actionItems) { item in
                        Toggle(isOn: actionItemDone(meeting, item.id)) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                if let owner = item.owner {
                                    Text("\(owner):").bold()
                                }
                                Text(item.task)
                                if let due = item.due {
                                    Text("· due \(due)").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            bulletSection(MeetingExport.keyPointsTitle(meeting.mode), notes.keyPoints)
            bulletSection("Open questions", notes.openQuestions)
            if !notes.topics.isEmpty {
                section("Topics") {
                    ForEach(notes.topics) { topic in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(topic.title).font(.headline)
                            Text(topic.summary).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("Notes by \(notes.generatedBy) · \(notes.generatedAt.formatted(date: .abbreviated, time: .shortened)). AI can be wrong; check against the transcript.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func bulletSection(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            section(title) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(item)
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.semibold))
            content()
        }
    }

    // MARK: Transcript

    private func transcriptTab(_ meeting: Meeting) -> some View {
        let turns = TranscriptFormatting.mergedTurns(meeting.segments)
        let filter = transcriptFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = filter.isEmpty ? turns : turns.filter { $0.text.localizedCaseInsensitiveContains(filter) }

        return VStack(spacing: 0) {
            TextField("Find in transcript", text: $transcriptFilter)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            if turns.isEmpty {
                ContentUnavailableView("No transcript", systemImage: "waveform", description: Text("Nothing was transcribed in this recording."))
            } else if visible.isEmpty {
                ContentUnavailableView.search(text: filter)
            } else {
                List(visible) { turn in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(TranscriptFormatting.timestamp(turn.start))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                        Text(turn.speaker.label)
                            .bold()
                            .foregroundStyle(turn.speaker == .me ? Color.accentColor : Color.orange)
                            .frame(width: 44, alignment: .leading)
                        Text(turn.text)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: Ask

    private func askTab(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask anything about this meeting, like “What did we decide about pricing?” or “What did Sam promise?”")
                .foregroundStyle(.secondary)
            HStack {
                TextField("Your question", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { ask(meeting) }
                Button("Ask") { ask(meeting) }
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || isAsking || meeting.segments.isEmpty)
            }
            if isAsking {
                ProgressView()
            }
            if let answer {
                ScrollView {
                    Text(answer)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer()
        }
        .padding(20)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func toolbar(_ meeting: Meeting) -> some ToolbarContent {
        ToolbarItemGroup {
            Button {
                generate(meeting)
            } label: {
                Label(meeting.notes == nil ? "Generate notes" : "Regenerate notes", systemImage: "sparkles")
            }
            .disabled(meeting.segments.isEmpty || notesService.isWorking(on: meeting.id))
            .help(meeting.notes == nil ? "Generate notes" : "Regenerate notes")

            Menu {
                Button("Copy as Markdown") { copyMarkdown(meeting) }
                Divider()
                ForEach(ExportFormat.allCases) { format in
                    Button("Export \(format.title)…") { export(meeting, as: format) }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export or copy")
        }
    }

    // MARK: Actions

    private func binding<Value>(_ meeting: Meeting, _ keyPath: WritableKeyPath<Meeting, Value>) -> Binding<Value> {
        Binding(
            get: { store.meeting(id: meeting.id)?[keyPath: keyPath] ?? meeting[keyPath: keyPath] },
            set: { newValue in
                guard var current = store.meeting(id: meeting.id) else { return }
                current[keyPath: keyPath] = newValue
                store.save(current)
            }
        )
    }

    private func actionItemDone(_ meeting: Meeting, _ itemID: ActionItem.ID) -> Binding<Bool> {
        Binding(
            get: { store.meeting(id: meeting.id)?.notes?.actionItems.first { $0.id == itemID }?.isDone ?? false },
            set: { done in
                guard var current = store.meeting(id: meeting.id),
                      let index = current.notes?.actionItems.firstIndex(where: { $0.id == itemID }) else { return }
                current.notes?.actionItems[index].isDone = done
                store.save(current)
            }
        )
    }

    private func generate(_ meeting: Meeting) {
        Task {
            do {
                let notes = try await notesService.generateNotes(for: meeting)
                guard var current = store.meeting(id: meeting.id) else { return }
                current.notes = notes
                store.save(current)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func ask(_ meeting: Meeting) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAsking else { return }
        isAsking = true
        answer = nil
        Task {
            defer { isAsking = false }
            do {
                answer = try await notesService.answer(trimmed, about: meeting)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func copyMarkdown(_ meeting: Meeting) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(MeetingExport.markdown(meeting), forType: .string)
    }

    private func export(_ meeting: Meeting, as format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = MeetingExport.fileName(for: meeting, format: format)
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .data]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let data: Data
        switch format {
        case .markdown: data = Data(MeetingExport.markdown(meeting).utf8)
        case .text: data = Data(MeetingExport.plainText(meeting).utf8)
        case .subtitles: data = Data(MeetingExport.subtitles(meeting).utf8)
        case .pdf: data = PDFExport.pdfData(for: meeting)
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = "Couldn't save the file: \(error.localizedDescription)"
        }
    }
}
