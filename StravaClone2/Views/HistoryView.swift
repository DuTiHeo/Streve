import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = HistoryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.sessions.isEmpty {
                    ContentUnavailableView(
                        "No Activities",
                        systemImage: "figure.run",
                        description: Text("Finished activities will appear here.")
                    )
                } else {
                    List(viewModel.sessions, id: \.id) { session in
                        NavigationLink {
                            SummaryView(session: session)
                        } label: {
                            HistoryRow(session: session)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .onAppear {
                viewModel.loadSessions(context: modelContext)
            }
            .refreshable {
                viewModel.loadSessions(context: modelContext)
            }
        }
    }
}

private struct HistoryRow: View {
    let session: ActivitySession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.activityType.icon)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 38, height: 38)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                Text(session.activityType.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(session.totalDistance.kilometersText)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Text(session.totalDuration.shortClockText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
