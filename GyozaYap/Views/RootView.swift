import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var recorder: RecordingController

    @State private var selection: Meeting.ID?
    @State private var search = ""
    @State private var pendingDelete: Meeting?

    init(initialSelection: Meeting.ID? = nil) {
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            detail
        }
        .sheet(item: $recorder.pendingStart) { request in
            StartRecordingSheet(
                sourceApp: request.sourceApp,
                onStart: { title, mode, consent in
                    recorder.pendingStart = nil
                    Task { await recorder.start(title: title, mode: mode, consent: consent, sourceApp: request.sourceApp) }
                },
                onCancel: { recorder.pendingStart = nil }
            )
        }
        .onChange(of: recorder.lastSavedMeetingID) { _, id in
            if let id {
                selection = id
            }
        }
        .alert("Couldn't record", isPresented: Binding(
            get: { recorder.errorMessage != nil },
            set: { if !$0 { recorder.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recorder.errorMessage ?? "")
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.title ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let meeting = pendingDelete {
                    if selection == meeting.id {
                        selection = nil
                    }
                    store.delete(meeting.id)
                }
                pendingDelete = nil
            }
        } message: {
            Text("The transcript and notes are removed from this Mac. This can't be undone.")
        }
    }

    private var sidebar: some View {
        MeetingSidebar(selection: $selection, search: search, onDelete: { pendingDelete = $0 })
            .searchable(text: $search, placement: .sidebar, prompt: "Search all meetings")
            .toolbar {
                ToolbarItem {
                    Button {
                        recorder.requestStart(sourceApp: nil)
                    } label: {
                        Label("New recording", systemImage: "record.circle")
                    }
                    .help("New recording (⌘R)")
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(recorder.phase != .idle)
                }
            }
    }

    @ViewBuilder
    private var detail: some View {
        if recorder.phase != .idle {
            RecordingView()
        } else if let selection {
            MeetingDetailView(meetingID: selection)
                .id(selection)
        } else if store.meetings.isEmpty && store.loadError == nil {
            // The first run: the one moment the library itself is the subject.
            EmptyState(
                word: "no meetings",
                message: "Start a recording, or join a call and GyozaYap will offer to record it. Everything is transcribed on this Mac."
            ) {
                StartAction(style: .primary, isEnabled: recorder.phase == .idle) {
                    recorder.requestStart(sourceApp: nil)
                }
            }
            .detailPlaceholder()
        } else {
            LibraryOverview(meetings: store.meetings) {
                StartAction(style: .quiet, isEnabled: recorder.phase == .idle) {
                    recorder.requestStart(sourceApp: nil)
                }
            }
        }
    }
}

// MARK: - Sidebar

/// The library column: meetings grouped by when they happened and set as
/// type, a title over a quiet line of date and duration. Selection, search
/// and the delete confirmation belong to `RootView`.
struct MeetingSidebar: View {
    @EnvironmentObject private var store: MeetingStore
    @Binding var selection: Meeting.ID?
    var search: String = ""
    var onDelete: (Meeting) -> Void = { _ in }

    var body: some View {
        let meetings = store.search(search)
        List(selection: $selection) {
            if let error = store.loadError {
                LoadErrorRow(message: error)
            }
            ForEach(MeetingGroup.grouped(meetings, now: Date())) { group in
                Section {
                    ForEach(group.meetings) { meeting in
                        MeetingRow(meeting: meeting, dateStyle: group.dateStyle)
                            .tag(meeting.id)
                            .contextMenu {
                                Button("Delete…", role: .destructive) { onDelete(meeting) }
                            }
                    }
                } header: {
                    // Inset to the rows' text on the left and their trailing
                    // labels on the right, so the rule ends where the column does.
                    SectionLabel(group.title)
                        .padding(.leading, 2)
                        .padding(.trailing, Theme.Space.m)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay(alignment: .topLeading) {
            if meetings.isEmpty && store.loadError == nil {
                SidebarNote(search: search)
            }
        }
    }
}

/// One meeting in the library: its title in ink, and under it the date and
/// duration, quiet and in figures that line up from row to row.
private struct MeetingRow: View {
    let meeting: Meeting
    let dateStyle: MeetingGroup.DateStyle
    /// Increased while the row is selected in a focused list. The selection
    /// is filled with the accent then: dark graphite in light mode, light
    /// graphite in dark mode (light enough for the text cursor to show), so
    /// the row switches to the inverse ink.
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        let onFill = prominence == .increased
        VStack(alignment: .leading, spacing: 3) {
            Text(meeting.title)
                .font(Theme.Typeface.heading)
                .foregroundStyle(onFill ? AnyShapeStyle(Theme.inkInverse) : AnyShapeStyle(Theme.ink))
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(dateText)
                    .font(Theme.Typeface.meta)
                    .monospacedDigit()
                Text("·")
                    .font(Theme.Typeface.meta)
                Text(TranscriptFormatting.timestamp(meeting.duration))
                    .font(Theme.Typeface.mono)
                Spacer(minLength: Theme.Space.s)
                if meeting.notes != nil {
                    Text("Notes")
                        .font(Theme.Typeface.label)
                        .tracking(Theme.Typeface.labelTracking)
                        .textCase(.uppercase)
                        .help("Has AI notes")
                }
            }
            .lineLimit(1)
            .foregroundStyle(onFill ? AnyShapeStyle(Theme.inkInverse.opacity(0.75)) : AnyShapeStyle(Theme.inkTertiary))
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private var dateText: String {
        let date = meeting.startedAt
        switch dateStyle {
        case .time:
            return date.formatted(date: .omitted, time: .shortened)
        case .weekday:
            return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        case .day:
            return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }
}

/// Meetings that share a heading in the sidebar: Today, Yesterday, This
/// week, then one group per month. Presentation only: the store's order,
/// newest first, is kept.
private struct MeetingGroup: Identifiable {
    /// How much of the date a row still needs once its heading has said the rest.
    enum DateStyle {
        case time
        case weekday
        case day
    }

    let id: String
    let dateStyle: DateStyle
    var meetings: [Meeting]

    var title: String { id }

    static func grouped(_ meetings: [Meeting], now: Date, calendar: Calendar = .current) -> [MeetingGroup] {
        var groups: [MeetingGroup] = []
        var index: [String: Int] = [:]
        for meeting in meetings {
            let (title, style) = heading(for: meeting.startedAt, now: now, calendar: calendar)
            if let position = index[title] {
                groups[position].meetings.append(meeting)
            } else {
                index[title] = groups.count
                groups.append(MeetingGroup(id: title, dateStyle: style, meetings: [meeting]))
            }
        }
        return groups
    }

    private static func heading(for date: Date, now: Date, calendar: Calendar) -> (String, DateStyle) {
        if calendar.isDate(date, inSameDayAs: now) {
            return ("Today", .time)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return ("Yesterday", .time)
        }
        if let week = calendar.dateInterval(of: .weekOfYear, for: now), week.contains(date), date < now {
            return ("This week", .weekday)
        }
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        let month = sameYear
            ? date.formatted(.dateTime.month(.wide))
            : date.formatted(.dateTime.month(.wide).year())
        return (month, .day)
    }
}

/// The store couldn't read the library: a real failure, so its label is red,
/// inline at the top of the list it affects.
private struct LoadErrorRow: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Library")
                .font(Theme.Typeface.label)
                .tracking(Theme.Typeface.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(Theme.live)
            Text(message)
                .font(Theme.Typeface.meta)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityElement(children: .combine)
    }
}

/// What the sidebar says when it has no rows: a quiet line for an empty
/// library (the detail pane carries the big word), or a plain no-results note.
private struct SidebarNote: View {
    let search: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if search.isEmpty {
                Text("Library").labelStyle()
                Text("Your recordings appear here.")
                    .font(Theme.Typeface.meta)
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                Text("No results")
                    .font(Theme.Typeface.heading)
                    .foregroundStyle(Theme.ink)
                Text("Nothing matches “\(search)”. Try another word, or something that was said in the meeting.")
                    .font(Theme.Typeface.meta)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Theme.Space.l + Theme.Space.xs)
        .padding(.top, Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Detail placeholders

/// The detail pane with a library but no meeting open, set like the poster:
/// the library's figures in a top row of columns, and one lowercase line at
/// the bottom saying what to do.
private struct LibraryOverview<Action: View>: View {
    let meetings: [Meeting]
    @ViewBuilder var action: () -> Action

    var body: some View {
        EmptyState(
            word: "select a meeting",
            message: "Choose one from the list to read its notes and transcript, or start a new recording.",
            action: action
        )
        .overlay(alignment: .topLeading) {
            ViewThatFits(in: .horizontal) {
                figures(includeStorage: true)
                figures(includeStorage: false)
            }
            .padding(Theme.Space.page)
        }
        .detailPlaceholder()
    }

    private func figures(includeStorage: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.xxl) {
            MetaPair(label: "Library", value: meetings.count == 1 ? "1 meeting" : "\(meetings.count) meetings")
            MetaPair(label: "Recorded",
                     value: TranscriptFormatting.timestamp(meetings.reduce(0) { $0 + $1.duration }),
                     monospaced: true)
            if let latest = meetings.first {
                MetaPair(label: "Latest", value: latest.startedAt.formatted(date: .abbreviated, time: .omitted))
            }
            if includeStorage {
                MetaPair(label: "Stored", value: "On this Mac")
            }
        }
        .fixedSize()
    }
}

private extension View {
    /// Fills the detail pane on the canvas, never narrower than a readable
    /// column. The split view measures its detail at very narrow widths; at
    /// those the display word and the message wrap a word per line and ask
    /// for more height than the window has, which pushes the whole split
    /// view off the window. A floor on the width keeps that measurement sane.
    func detailPlaceholder() -> some View {
        self.frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
    }
}

/// "Start recording" with its shortcut beside it, in the weight the screen
/// calls for: filled when it is the screen's one action, quiet otherwise.
private struct StartAction: View {
    enum Style {
        case primary
        case quiet
    }

    let style: Style
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            switch style {
            case .primary:
                Button("Start recording", action: action)
                    .buttonStyle(.primary)
                    .disabled(!isEnabled)
            case .quiet:
                Button("Start recording", action: action)
                    .buttonStyle(.quiet)
                    .disabled(!isEnabled)
            }
            KeyCap("⌘R")
        }
    }
}
