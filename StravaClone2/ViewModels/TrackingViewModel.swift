import Combine
import CoreLocation
import Foundation
import SwiftData

enum TrackingState: Equatable {
    case idle
    case tracking
    case paused
    case finishing
    case completed(session: ActivitySession)

    static func == (lhs: TrackingState, rhs: TrackingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.tracking, .tracking), (.paused, .paused), (.finishing, .finishing):
            return true
        case let (.completed(left), .completed(right)):
            return left.id == right.id
        default:
            return false
        }
    }
}

@MainActor
final class TrackingViewModel: ObservableObject {
    private static let liveActivityUpdateIntervalSeconds = 2

    @Published private(set) var state: TrackingState = .idle
    @Published private(set) var elapsedTime: String = "00:00"
    @Published private(set) var currentPace: String = "--:--"
    @Published private(set) var totalDistance: String = "0.00 km"
    @Published private(set) var stepCount: String = "0"
    @Published private(set) var coordinates: [[CLLocationCoordinate2D]] = [[]]
    @Published var saveErrorMessage: String?
    @Published var gpsSignalWeakMessage: String?

    private let locationService: LocationManagerService
    private let motionService: MotionService
    private let liveActivityManager: LiveActivityManager
    private let persistenceController: PersistenceController

    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var elapsedSeconds = 0
    private var previousLocation: CLLocation?
    private var currentSession: ActivitySession?
    private var lastLiveActivityUpdate = 0

    init() {
        self.locationService = LocationManagerService.shared
        self.motionService = MotionService.shared
        self.liveActivityManager = LiveActivityManager.shared
        self.persistenceController = PersistenceController.shared
        bindServices()
    }

    init(
        locationService: LocationManagerService,
        motionService: MotionService,
        liveActivityManager: LiveActivityManager,
        persistenceController: PersistenceController
    ) {
        self.locationService = locationService
        self.motionService = motionService
        self.liveActivityManager = liveActivityManager
        self.persistenceController = persistenceController
        bindServices()
    }

    func tapStart(type: ActivityType) {
        guard state == .idle else { return }

        let session = ActivitySession(type: type)
        currentSession = session
        coordinates = [[]]
        elapsedSeconds = 0
        previousLocation = nil
        lastLiveActivityUpdate = 0
        refreshDisplayValues()

        state = .tracking
        locationService.requestAuthorization()
        locationService.startTracking(activityType: type)
        motionService.start(sessionStart: session.startTime)
        liveActivityManager.startLiveActivity(for: session)
        startTimer()
    }

    func tapPause() {
        guard state == .tracking else { return }
        state = .paused
        stopTimer()
        locationService.pauseTracking()
        liveActivityManager.updateLiveActivity(
            elapsed: elapsedSeconds,
            distance: currentSession?.totalDistance ?? 0,
            pace: currentSession?.averagePace ?? 0
        )
    }

    func tapResume() {
        guard state == .paused else { return }
        coordinates.append([])
        previousLocation = nil
        state = .tracking
        locationService.resumeTracking()
        startTimer()
    }

    func tapFinish() {
        guard state == .tracking || state == .paused, let session = currentSession else { return }

        state = .finishing
        stopTimer()
        locationService.stopTracking()
        motionService.stop()
        liveActivityManager.endLiveActivity()

        session.endTime = Date()
        session.totalDuration = TimeInterval(elapsedSeconds)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let context = persistenceController.container.mainContext
                context.insert(session)
                try context.save()
            } catch {
                saveErrorMessage = "Could not save session. Data may be lost."
                print("SwiftData save failed: \(error.localizedDescription)")
            }

            state = .completed(session: session)
        }
    }

    func reset() {
        stopTimer()
        locationService.stopTracking()
        motionService.stop()
        liveActivityManager.endLiveActivity()
        currentSession = nil
        previousLocation = nil
        coordinates = [[]]
        elapsedSeconds = 0
        lastLiveActivityUpdate = 0
        elapsedTime = "00:00"
        currentPace = "--:--"
        totalDistance = "0.00 km"
        stepCount = "0"
        state = .idle
    }

    private func bindServices() {
        locationService.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.handle(location)
            }
            .store(in: &cancellables)

        locationService.$gpsSignalWeak
            .removeDuplicates()
            .sink { [weak self] weakSignal in
                self?.gpsSignalWeakMessage = weakSignal ? "GPS signal weak" : nil
            }
            .store(in: &cancellables)

        motionService.$stepCount
            .sink { [weak self] count in
                self?.stepCount = "\(count)"
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .shouldAutoPause)
            .sink { [weak self] _ in
                self?.tapPause()
            }
            .store(in: &cancellables)
    }

    private func handle(_ location: CLLocation) {
        guard state == .tracking, let session = currentSession else { return }

        let point = LocationPoint(from: location)
        session.locationPoints.append(point)

        if let previousLocation {
            let delta = location.distance(from: previousLocation)
            session.totalDistance += delta

            let altitudeDelta = location.altitude - previousLocation.altitude
            if altitudeDelta > 0 {
                session.elevationGain += altitudeDelta
            }
        }

        previousLocation = location

        if coordinates.isEmpty {
            coordinates = [[]]
        }
        coordinates[coordinates.count - 1].append(location.coordinate)

        refreshDisplayValues()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard state == .tracking else { return }
        elapsedSeconds += 1
        currentSession?.totalDuration = TimeInterval(elapsedSeconds)
        refreshDisplayValues()

        if elapsedSeconds - lastLiveActivityUpdate >= Self.liveActivityUpdateIntervalSeconds {
            lastLiveActivityUpdate = elapsedSeconds
            liveActivityManager.updateLiveActivity(
                elapsed: elapsedSeconds,
                distance: currentSession?.totalDistance ?? 0,
                pace: displayPaceSeconds
            )
        }
    }

    private var displayPaceSeconds: Double {
        if locationService.currentPaceSecondsPerKm > 0 {
            return locationService.currentPaceSecondsPerKm
        }
        return currentSession?.averagePace ?? 0
    }

    private func refreshDisplayValues() {
        elapsedTime = TimeInterval(elapsedSeconds).shortClockText
        totalDistance = (currentSession?.totalDistance ?? 0).kilometersText
        currentPace = displayPaceSeconds.paceText
    }
}
