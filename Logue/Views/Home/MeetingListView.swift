import SwiftUI

/// Minimal fallback view - should rarely be shown due to auto-select
struct MeetingListView: View {
    @Environment(MeetingStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack {
            ProgressView()
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppThemeConstants.contentBackground)
        .navigationTitle("Meetings")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    let meeting = store.createMeeting(
                        title: "Meeting \(Date.now.formatted(date: .abbreviated, time: .shortened))"
                    )
                    store.selectedMeetingID = meeting.id
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel("New Meeting")
                }
                .help("New Meeting")
            }
        }
        .onAppear {
            // Ensure a meeting is selected or created
            if store.selectedMeetingID == nil {
                if store.activeMeetings.isEmpty {
                    _ = store.createMeeting(
                        title: "Untitled Meeting",
                        mode: .inPerson,
                        template: .general
                    )
                } else if let first = store.activeMeetings.first {
                    store.selectedMeetingID = first.id
                }
            }
        }
    }
}
