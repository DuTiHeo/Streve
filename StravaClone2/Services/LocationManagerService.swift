import Combine
import CoreLocation
import Foundation

final class LocationManagerService: NSObject, ObservableObject {
    static let shared = LocationManagerService()

    @Published var currentLocation: CLLocation?
    @Published var authStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking: Bool = false
    @Published private(set) var headingDegrees: CLLocationDirection?
    @Published private(set) var currentPaceSecondsPerKm: Double = 0
    @Published var gpsSignalWeak: Bool = false

    private let locationManager = CLLocationManager()
    private var activeActivityType: ActivityType = .run
    private var recentLocations: [CLLocation] = []

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.headingFilter = 2
        locationManager.activityType = .fitness
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
        authStatus = locationManager.authorizationStatus
    }

    func requestAuthorization() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        default:
            authStatus = locationManager.authorizationStatus
        }
    }

    func startTracking(activityType: ActivityType? = nil) {
        if let activityType {
            activeActivityType = activityType
        }
        gpsSignalWeak = false
        recentLocations.removeAll()
        isTracking = true
        locationManager.startUpdatingLocation()
        startHeadingUpdatesIfAvailable()
    }

    func stopTracking() {
        isTracking = false
        recentLocations.removeAll()
        currentPaceSecondsPerKm = 0
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }

    func pauseTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
    }

    func resumeTracking() {
        gpsSignalWeak = false
        recentLocations.removeAll()
        isTracking = true
        locationManager.startUpdatingLocation()
        startHeadingUpdatesIfAvailable()
    }

    private func startHeadingUpdatesIfAvailable() {
        guard CLLocationManager.headingAvailable() else { return }
        locationManager.startUpdatingHeading()
    }

    private func shouldAccept(_ location: CLLocation) -> Bool {
        if location.horizontalAccuracy < 0 { return false }
        if location.horizontalAccuracy > 20 {
            gpsSignalWeak = true
            return false
        }
        if location.timestamp < Date().addingTimeInterval(-10) { return false }
        if location.speed < -0.5, activeActivityType == .run { return false }
        return true
    }

    private func updateRollingPace(with location: CLLocation) {
        recentLocations.append(location)
        let cutoff = Date().addingTimeInterval(-10)
        recentLocations.removeAll { $0.timestamp < cutoff }

        guard recentLocations.count > 1,
              let first = recentLocations.first,
              let last = recentLocations.last else {
            currentPaceSecondsPerKm = 0
            return
        }

        let duration = last.timestamp.timeIntervalSince(first.timestamp)
        let distance = zip(recentLocations.dropLast(), recentLocations.dropFirst())
            .map { $1.distance(from: $0) }
            .reduce(0, +)

        guard duration > 0, distance > 0 else {
            currentPaceSecondsPerKm = 0
            return
        }

        let averageSpeedMetersPerSecond = distance / duration
        currentPaceSecondsPerKm = averageSpeedMetersPerSecond > 0 ? 1000 / averageSpeedMetersPerSecond : 0
    }
}

extension LocationManagerService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authStatus = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isTracking else { return }

        for location in locations where shouldAccept(location) {
            gpsSignalWeak = false
            currentLocation = location
            updateRollingPace(with: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        guard heading >= 0 else { return }
        headingDegrees = heading
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location update failed: \(error.localizedDescription)")
    }
}
