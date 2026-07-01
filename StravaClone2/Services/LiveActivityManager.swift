import ActivityKit
import Foundation

final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activity: Activity<ActivityTrackerAttributes>?
    private var lastContentState = ActivityTrackerAttributes.ContentState(
        elapsedSeconds: 0,
        distanceMeters: 0,
        paceSecondsPerKm: 0,
        activityType: ActivityType.run.liveActivityLabel
    )

    private init() {}

    func startLiveActivity(for session: ActivitySession) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = ActivityTrackerAttributes(sessionID: session.id.uuidString)
        let state = ActivityTrackerAttributes.ContentState(
            elapsedSeconds: Int(session.totalDuration),
            distanceMeters: session.totalDistance,
            paceSecondsPerKm: session.averagePace,
            activityType: session.activityType.liveActivityLabel
        )
        lastContentState = state

        do {
            activity = try Activity<ActivityTrackerAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("Could not start Live Activity: \(error.localizedDescription)")
        }
    }

    func updateLiveActivity(elapsed: Int, distance: Double, pace: Double) {
        guard let activity else { return }

        lastContentState = ActivityTrackerAttributes.ContentState(
            elapsedSeconds: elapsed,
            distanceMeters: distance,
            paceSecondsPerKm: pace,
            activityType: lastContentState.activityType
        )

        Task {
            await activity.update(ActivityContent(state: lastContentState, staleDate: nil))
        }
    }

    func endLiveActivity() {
        guard let activity else { return }
        let finalState = lastContentState
        self.activity = nil

        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }
}
