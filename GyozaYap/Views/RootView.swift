import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var recorder: RecordingController

    @State private var selection: Meeting.ID?
    @State private var search = ""
    @State private var pendingDelete: Meeting?

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
        let meetings = store.search(search)
        return List(selection: $selection) {
            if let error = store.loadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            ForEach(meetings) { meeting in
                VStack(alignment: .leading, spacing: 3) {
                    Text(meeting.title)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
                        Text("·")
                        Text(TranscriptFormatting.timestamp(meeting.duration))
                        if meeting.notes != nil {
                            Image(systemName: "sparkles")
                                .help("Has AI notes")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(meeting.id)
                .contextMenu {
                    Button("Delete…", role: .destructive) { pendingDelete = meeting }
                }
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search all meetings")
        .overlay {
            if meetings.isEmpty && store.loadError == nil {
                if search.isEmpty {
                    ContentUnavailableView(
                        "No meetings yet",
                        systemImage: "waveform.circle",
                        description: Text("Start a recording, or join a call and GyozaYap will offer to record it.")
                    )
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
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
        } else {
            ContentUnavailableView {
                Label("GyozaYap", systemImage: "waveform.and.mic")
            } description: {
                Text("Turn meeting yap into notes. Everything is transcribed on this Mac.")
            } actions: {
                Button("Start recording") { recorder.requestStart(sourceApp: nil) }
                    .disabled(recorder.phase != .idle)
            }
        }
    }
}
