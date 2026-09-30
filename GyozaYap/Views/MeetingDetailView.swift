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

    init(meetingID: Meeting.ID, initialTab: Tab = .notes) {
        self.meetingID = meetingID
        _tab = State(initialValue: initialTab)
    }

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
                DetailTabBar(selection: $tab)
                    .padding(.horizontal, Theme.Space.page)

                switch tab {
                case .notes: notesTab(meeting)
                case .transcript: transcriptTab(meeting)
                case .ask: askTab(meeting)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.canvas)
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
            EmptyState(word: "not found", message: "This meeting is no longer in your library.")
                .background(Theme.canvas)
        }
    }

    // MARK: Header

    /// The poster's top: the title, then a row of label-over-value columns.
    private func header(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            TextField("Title", text: binding(meeting, \.title))
                .textFieldStyle(.plain)
                .titleStyle()
            HStack(alignment: .top, spacing: Theme.Space.xxxl) {
                MetaPair(label: "Date", value: meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
                MetaPair(label: "Duration", value: TranscriptFormatting.timestamp(meeting.duration), monospaced: true)
                if let app = meeting.sourceApp {
                    MetaPair(label: "Source", value: app)
                }
                modeColumn(meeting)
            }
        }
        .padding(.horizontal, Theme.Space.page)
        .padding(.top, Theme.Space.page)
        .padding(.bottom, Theme.Space.xxl)
    }

    /// MODE over a quiet pull-down: the same choices and binding as a plain picker.
    private func modeColumn(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Mode").labelStyle()
            Menu {
                Picker("Mode", selection: binding(meeting, \.mode)) {
                    ForEach(NotesMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: Theme.Space.xs) {
                    Text(meeting.mode.title)
                        .font(Theme.Typeface.meta)
                        .foregroundStyle(Theme.ink)
                    Image(systemName: "chevron.down")
                        .font(Theme.Typeface.label)
                        .imageScale(.small)
                        .foregroundStyle(Theme.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Mode")
            .accessibilityValue(meeting.mode.title)
        }
    }

    // MARK: Notes

    private func notesTab(_ meeting: Meeting) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                if notesService.isWorking(on: meeting.id) {
                    HStack(spacing: Theme.Space.s) {
                        ProgressView().controlSize(.small)
                        let progress = notesService.progressText(for: meeting.id)
                        Text(progress.isEmpty ? "Writing notes…" : progress)
                            .font(Theme.Typeface.body)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                } else if let notes = meeting.notes {
                    generatedNotes(notes, meeting: meeting)
                } else {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        Text("no notes yet").displayStyle()
                        Text(notesService.readinessMessage ?? "Generate a summary, decisions and action items from the transcript.")
                            .font(Theme.Typeface.body)
                            .lineSpacing(Theme.Typeface.bodyLineSpacing)
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(maxWidth: 360, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Generate notes") { generate(meeting) }
                            .buttonStyle(.primary)
                            .disabled(meeting.segments.isEmpty)
                            .padding(.top, Theme.Space.s)
                    }
                    .padding(.vertical, Theme.Space.s)
                }

                if !meeting.bookmarks.isEmpty {
                    section("Marked moments") {
                        ForEach(meeting.bookmarks.sorted(by: { $0.time < $1.time })) { marker in
                            GutterRow(gutter: TranscriptFormatting.timestamp(marker.time)) {
                                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                                    Image(systemName: marker.kind.systemImage)
                                        .font(Theme.Typeface.meta)
                                        .foregroundStyle(Theme.inkSecondary)
                                        .frame(width: Theme.Space.l, alignment: .leading)
                                        .accessibilityLabel(marker.kind.title)
                                    Text(marker.note.isEmpty ? marker.kind.title : marker.note)
                                        .bodyStyle()
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                section("My notes") {
                    TextEditor(text: binding(meeting, \.userNotes))
                        .font(Theme.Typeface.body)
                        .foregroundStyle(Theme.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .fieldSurface()
                }
            }
            .frame(maxWidth: Theme.Space.measure, alignment: .leading)
            .padding(.horizontal, Theme.Space.page)
            .padding(.top, Theme.Space.xxl)
            .padding(.bottom, Theme.Space.page)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    private func generatedNotes(_ notes: MeetingNotes, meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            section("TL;DR") {
                Text(notes.tldr)
                    .font(Theme.Typeface.lead)
                    .tracking(Theme.Typeface.leadTracking)
                    .lineSpacing(Theme.Typeface.bodyLineSpacing)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            bulletSection("Decisions", notes.decisions)
            if !notes.actionItems.isEmpty {
                section("Action items") {
                    ForEach(notes.actionItems) { item in
                        actionItemRow(item, meeting: meeting)
                    }
                }
            }
            bulletSection(MeetingExport.keyPointsTitle(meeting.mode), notes.keyPoints)
            bulletSection("Open questions", notes.openQuestions)
            if !notes.topics.isEmpty {
                section("Topics") {
                    ForEach(Array(notes.topics.enumerated()), id: \.element.id) { index, topic in
                        GutterRow(gutter: index < 9 ? "0\(index + 1)" : "\(index + 1)") {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topic.title)
                                    .font(Theme.Typeface.heading)
                                    .foregroundStyle(Theme.ink)
                                Text(topic.summary)
                                    .font(Theme.Typeface.body)
                                    .lineSpacing(Theme.Typeface.bodyLineSpacing)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            Text("Notes by \(notes.generatedBy) · \(notes.generatedAt.formatted(date: .abbreviated, time: .shortened)). AI can be wrong; check against the transcript.")
                .font(Theme.Typeface.meta)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The checkbox sits in the gutter so the task lines up with every other
    /// list; clicking the text still toggles it, as a checkbox's label does.
    private func actionItemRow(_ item: ActionItem, meeting: Meeting) -> some View {
        let done = actionItemDone(meeting, item.id)
        var spoken = item.task
        if let owner = item.owner { spoken = "\(owner): \(spoken)" }
        if let due = item.due { spoken += " · due \(due)" }

        return HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Toggle(spoken, isOn: done)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: GridColumn.time, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.task)
                    .font(Theme.Typeface.body)
                    .lineSpacing(Theme.Typeface.bodyLineSpacing)
                    .foregroundStyle(done.wrappedValue ? Theme.inkSecondary : Theme.ink)
                    .strikethrough(done.wrappedValue, color: Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if item.owner != nil || item.due != nil {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        if let owner = item.owner {
                            Text(owner).labelStyle()
                        }
                        if let due = item.due {
                            Text("Due \(due)")
                                .font(Theme.Typeface.meta)
                                .foregroundStyle(Theme.inkTertiary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { done.wrappedValue.toggle() }
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func bulletSection(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            section(title) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    let parts = TimestampSuffix.split(item)
                    GutterRow(gutter: parts.time ?? "–") {
                        Text(parts.text)
                            .bodyStyle()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            SectionLabel(title)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                content()
            }
        }
    }

    // MARK: Transcript

    private func transcriptTab(_ meeting: Meeting) -> some View {
        let turns = TranscriptFormatting.mergedTurns(meeting.segments)
        let filter = transcriptFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = filter.isEmpty ? turns : turns.filter { $0.text.localizedCaseInsensitiveContains(filter) }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.Typeface.meta)
                    .foregroundStyle(Theme.inkTertiary)
                    .accessibilityHidden(true)
                TextField("Find in transcript", text: $transcriptFilter)
                    .textFieldStyle(.plain)
                    .font(Theme.Typeface.body)
            }
            .fieldSurface()
            .frame(maxWidth: 320, alignment: .leading)
            .padding(.horizontal, Theme.Space.page)
            .padding(.top, Theme.Space.xl)
            .padding(.bottom, Theme.Space.s)

            if turns.isEmpty {
                EmptyState(word: "no transcript", message: "Nothing was transcribed in this recording.")
            } else if visible.isEmpty {
                EmptyState(word: "no matches", message: "Nothing in the transcript contains “\(filter)”. Check the spelling or try another word.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visible) { turn in
                            transcriptRow(turn)
                        }
                    }
                    .padding(.horizontal, Theme.Space.page)
                    .padding(.top, Theme.Space.s)
                    .padding(.bottom, Theme.Space.page)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Time / speaker / words: three columns on the page grid.
    private func transcriptRow(_ turn: TranscriptSegment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(TranscriptFormatting.timestamp(turn.start))
                .font(Theme.Typeface.mono)
                .monospacedDigit()
                .foregroundStyle(Theme.inkTertiary)
                .frame(width: GridColumn.time, alignment: .leading)
            SpeakerTag(speaker: turn.speaker)
                .frame(width: GridColumn.speaker, alignment: .leading)
            Text(turn.text)
                .font(Theme.Typeface.body)
                .lineSpacing(Theme.Typeface.bodyLineSpacing + 2)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: Theme.Space.measure, alignment: .leading)
        }
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .combine)
    }

    // MARK: Ask

    private func askTab(_ meeting: Meeting) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                Text("Ask anything about this meeting, like “What did we decide about pricing?” or “What did Sam promise?”")
                    .font(Theme.Typeface.body)
                    .lineSpacing(Theme.Typeface.bodyLineSpacing)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Theme.Space.s) {
                    TextField("Your question", text: $question)
                        .textFieldStyle(.plain)
                        .font(Theme.Typeface.body)
                        .fieldSurface()
                        .onSubmit { ask(meeting) }
                    Button("Ask") { ask(meeting) }
                        .buttonStyle(.primary)
                        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || isAsking || meeting.segments.isEmpty)
                }

                if isAsking {
                    HStack(spacing: Theme.Space.s) {
                        ProgressView().controlSize(.small)
                        Text("Reading the transcript…")
                            .font(Theme.Typeface.body)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }

                if let answer {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        SectionLabel("Answer")
                        Text(answer)
                            .font(Theme.Typeface.lead)
                            .tracking(Theme.Typeface.leadTracking)
                            .lineSpacing(Theme.Typeface.bodyLineSpacing + 2)
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, Theme.Space.s)
                }
            }
            .frame(maxWidth: Theme.Space.measure, alignment: .leading)
            .padding(.horizontal, Theme.Space.page)
            .padding(.top, Theme.Space.xxl)
            .padding(.bottom, Theme.Space.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

// MARK: - Page grid

/// Column widths shared by the notes lists and the transcript, so times and
/// text line up from one tab to the next.
private enum GridColumn {
    /// Timestamps ("1:04:05" in SF Mono), list markers and checkboxes.
    static let time: CGFloat = Theme.Space.xxxl
    /// "ME" / "THEM".
    static let speaker: CGFloat = Theme.Space.xxxl
}

/// A list row with a hanging gutter: a mono marker (a time, a number or a
/// dash) on the left, the content in the text column.
private struct GutterRow<Content: View>: View {
    let gutter: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(gutter)
                .font(Theme.Typeface.mono)
                .monospacedDigit()
                .foregroundStyle(Theme.inkTertiary)
                .frame(width: GridColumn.time, alignment: .leading)
                .accessibilityHidden(gutter == "–")
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Notes the AI writes often end with a moment, "… on Thursday [1:24]". This
/// only moves a single trailing [m:ss] or [h:mm:ss] into the gutter for
/// display; anything else is left exactly as written.
private enum TimestampSuffix {
    static func split(_ item: String) -> (text: String, time: String?) {
        let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("]"), let open = trimmed.lastIndex(of: "[") else { return (item, nil) }
        let inner = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
        let parts = inner.split(separator: ":", omittingEmptySubsequences: false)
        let isTime = (2...3).contains(parts.count)
            && parts.allSatisfy { part in (1...2).contains(part.count) && part.allSatisfy { $0.isASCII && $0.isNumber } }
            && parts.dropFirst().allSatisfy { $0.count == 2 }
        let text = trimmed[..<open].trimmingCharacters(in: .whitespaces)
        guard isTime, !text.isEmpty else { return (item, nil) }
        return (text, String(inner))
    }
}

// MARK: - Tabs

/// Notes / Transcript / Ask as a row of words: the selected one in ink and
/// semibold with an ink rule under it, the others secondary. Each is a real
/// button (keyboard focusable, announced as selected to VoiceOver).
private struct DetailTabBar: View {
    @Binding var selection: MeetingDetailView.Tab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            Hairline()
            HStack(alignment: .bottom, spacing: Theme.Space.xl) {
                ForEach(MeetingDetailView.Tab.allCases) { tab in
                    item(tab)
                }
                Spacer(minLength: 0)
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.quick, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View")
    }

    private func item(_ tab: MeetingDetailView.Tab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            // The semibold word, hidden, reserves the width so nothing shifts on selection.
            Text(tab.rawValue)
                .font(Theme.Typeface.heading)
                .hidden()
                .overlay(alignment: .leading) {
                    Text(tab.rawValue)
                        .font(isSelected ? Theme.Typeface.heading : Theme.Typeface.body)
                        .foregroundStyle(isSelected ? Theme.ink : Theme.inkSecondary)
                }
                .padding(.bottom, Theme.Space.m)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isSelected ? Theme.ink : Color.clear)
                        .frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
