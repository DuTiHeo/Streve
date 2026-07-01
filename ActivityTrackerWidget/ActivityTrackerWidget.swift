import ActivityKit
import SwiftUI
import WidgetKit

struct ActivityTrackerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ActivityTrackerAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.formattedDistance, systemImage: "location.fill")
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Label(context.state.formattedPace, systemImage: "speedometer")
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.formattedElapsed)
                        .font(.headline.monospacedDigit())
                }
            } compactLeading: {
                Image(systemName: iconName(for: context.state.activityType))
            } compactTrailing: {
                Text(context.state.formattedDistance)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: iconName(for: context.state.activityType))
            }
            .keylineTint(.orange)
        }
    }

    private func iconName(for activityType: String) -> String {
        switch activityType {
        case "Walking":
            return "figure.walk"
        case "Riding":
            return "figure.outdoor.cycle"
        default:
            return "figure.run"
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<ActivityTrackerAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "figure.run")
                    .foregroundStyle(.orange)
                Text("ACTIVITY TRACKER - \(context.state.activityType)")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Divider()
                .overlay(Color.orange.opacity(0.55))

            HStack {
                LiveActivityStat(value: context.state.formattedElapsed, label: "Time")
                LiveActivityStat(value: context.state.formattedDistance, label: "Distance")
                LiveActivityStat(value: context.state.formattedPace, label: "Pace")
            }
        }
        .padding()
        .foregroundStyle(.white)
    }
}

private struct LiveActivityStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}

@main
struct ActivityTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        ActivityTrackerLiveActivity()
    }
}
