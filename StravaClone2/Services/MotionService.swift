import Combine
import CoreMotion
import Foundation

extension Notification.Name {
    static let shouldAutoPause = Notification.Name("ShouldAutoPause")
}

final class MotionService: ObservableObject {
    static let shared = MotionService()

    @Published private(set) var stepCount: Int = 0

    private let pedometer = CMPedometer()
    private let activityManager = CMMotionActivityManager()
    private var stationaryTimer: Timer?

    private init() {}

    func start(sessionStart: Date) {
        stepCount = 0

        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: sessionStart) { [weak self] data, error in
                guard error == nil, let data else { return }
                DispatchQueue.main.async {
                    self?.stepCount = data.numberOfSteps.intValue
                }
            }
        }

        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: .main) { [weak self] activity in
                self?.handle(activity)
            }
        }
    }

    func stop() {
        pedometer.stopUpdates()
        activityManager.stopActivityUpdates()
        stationaryTimer?.invalidate()
        stationaryTimer = nil
    }

    private func handle(_ activity: CMMotionActivity?) {
        guard let activity else { return }

        if activity.stationary {
            guard stationaryTimer == nil else { return }
            stationaryTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { _ in
                NotificationCenter.default.post(name: .shouldAutoPause, object: nil)
            }
        } else {
            stationaryTimer?.invalidate()
            stationaryTimer = nil
        }
    }
}
