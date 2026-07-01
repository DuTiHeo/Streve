# System Architecture & Technical Specification: Personal Activity Tracker (iOS)

> **Target AI Agent:** This document is written for an AI coding assistant (Claude, Gemini CLI, etc.) to implement from scratch. Every section contains enough detail to generate compilable Swift code without follow-up questions. Read the entire document before writing any code.

---

## 1. Project Overview & Feasibility

**Goal:** A single-user iOS app that tracks outdoor activities (Run / Walk / Ride) using GPS, displays a live map with route overlay, shows a Lock Screen Live Activity, and exports a PNG summary or a 3D flyover video on completion.

**Feasibility:** ✅ Fully achievable by one developer (or AI agent). There is no backend, no authentication, no social layer. All data is local.

**Minimum Deployment Target:** iOS 17.0  
**Language:** Swift 5.9+  
**IDE:** Xcode 15+

---

## 2. Xcode Project Setup (Do This First)

### 2.1 Create Project
- Template: **App** (not Document App)
- Interface: **SwiftUI**
- Storage: **SwiftData**
- Bundle ID: `com.personal.activitytracker`

### 2.2 Required Capabilities (Signing & Capabilities tab)
Add the following capabilities:
- **Background Modes** → check `Location updates`
- **Push Notifications** (required by ActivityKit)

### 2.3 Info.plist Keys to Add
```xml
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Activity Tracker needs your location to record your route.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>Activity Tracker needs your location to record your route.</string>

<key>NSMotionUsageDescription</key>
<string>Used for step counting and auto-pause detection.</string>
```

### 2.4 Add Widget Extension Target
- File → New → Target → **Widget Extension**
- Name: `ActivityTrackerWidget`
- Include Live Activity: ✅ YES
- This creates a separate target that shares data models via a **Shared Swift Package** or direct file inclusion.

---

## 3. Full Folder Structure

```
ActivityTracker/
├── ActivityTrackerApp.swift          # @main entry point
├── Models/
│   ├── ActivitySession.swift         # SwiftData model
│   ├── LocationPoint.swift           # SwiftData model
│   └── ActivityType.swift            # Enum: run, walk, ride
├── Services/
│   ├── LocationManagerService.swift  # GPS tracking singleton
│   ├── MotionService.swift           # CoreMotion step/cadence
│   ├── LiveActivityManager.swift     # ActivityKit integration
│   └── PersistenceController.swift   # SwiftData stack
├── ViewModels/
│   ├── TrackingViewModel.swift       # Active tracking logic + state machine
│   └── HistoryViewModel.swift        # Past sessions list + export trigger
├── Views/
│   ├── HomeView.swift                # Activity type picker + Start button
│   ├── TrackingView.swift            # Live map + stats overlay
│   ├── SummaryView.swift             # Post-activity summary + export buttons
│   └── HistoryView.swift             # List of past sessions
├── Export/
│   ├── PNGExportService.swift        # UIGraphicsImageRenderer route card
│   └── FlyoverExportService.swift    # MKMapView + AVAssetWriter video
├── Extensions/
│   ├── CLLocationCoordinate2D+Math.swift
│   └── Double+Formatting.swift
└── ActivityTrackerWidget/
    ├── ActivityTrackerWidget.swift
    └── ActivityAttributes.swift      # Shared Live Activity attributes
```

---

## 4. Data Models

### 4.1 `ActivityType.swift`
```swift
enum ActivityType: String, Codable, CaseIterable {
    case run  = "Run"
    case walk = "Walk"
    case ride = "Ride"

    var icon: String {
        switch self {
        case .run:  return "figure.run"
        case .walk: return "figure.walk"
        case .ride: return "figure.outdoor.cycle"
        }
    }
}
```

### 4.2 `LocationPoint.swift`
```swift
@Model
final class LocationPoint {
    var latitude:    Double
    var longitude:   Double
    var altitude:    Double
    var speed:       Double   // m/s, -1 if invalid
    var timestamp:   Date
    var accuracy:    Double   // horizontal accuracy in meters

    init(from location: CLLocation) {
        self.latitude   = location.coordinate.latitude
        self.longitude  = location.coordinate.longitude
        self.altitude   = location.altitude
        self.speed      = location.speed
        self.timestamp  = location.timestamp
        self.accuracy   = location.horizontalAccuracy
    }
}
```

### 4.3 `ActivitySession.swift`
```swift
@Model
final class ActivitySession {
    var id:              UUID
    var activityType:    ActivityType
    var startTime:       Date
    var endTime:         Date?
    var totalDistance:   Double     // meters
    var totalDuration:   TimeInterval // seconds (excludes paused time)
    var elevationGain:   Double     // meters
    @Relationship(deleteRule: .cascade)
    var locationPoints:  [LocationPoint]

    // Computed helpers (not persisted)
    var averagePace: Double {   // seconds per km
        guard totalDistance > 0 else { return 0 }
        return totalDuration / (totalDistance / 1000)
    }
    var coordinates: [CLLocationCoordinate2D] {
        locationPoints
            .sorted { $0.timestamp < $1.timestamp }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    init(type: ActivityType) {
        self.id             = UUID()
        self.activityType   = type
        self.startTime      = Date()
        self.totalDistance  = 0
        self.totalDuration  = 0
        self.elevationGain  = 0
        self.locationPoints = []
    }
}
```

---

## 5. State Machine (Critical — Implement Exactly)

`TrackingViewModel` must implement this state machine. **No other state transitions are valid.**

```
                    ┌─────────────────────────────────────────────┐
                    │                                             │
         tapStart   ▼          tapPause        tapResume         │
[idle] ──────────► [tracking] ──────────► [paused] ──────────► [tracking]
                       │
                       │ tapFinish (only valid from tracking OR paused)
                       ▼
                  [finishing]   ← async: save to SwiftData
                       │
                       │ onSaveComplete
                       ▼
                  [completed(session: ActivitySession)]
```

```swift
enum TrackingState: Equatable {
    case idle
    case tracking
    case paused
    case finishing
    case completed(session: ActivitySession)
}
```

**Rules:**
- `tapPause`: stops accepting new GPS points, stops distance accumulation, pauses Live Activity timer.
- `tapResume`: resumes GPS acceptance; adds a `nil` separator in coordinates to break the polyline (so paused gap is not drawn).
- `tapFinish`: valid from `.tracking` or `.paused`. Transitions to `.finishing`, saves session asynchronously, then transitions to `.completed`.
- In `.paused` state, the map still displays but the orange polyline is frozen.

---

## 6. Core Services

### 6.1 `LocationManagerService.swift`

```swift
// Singleton. Publish via @Observable or ObservableObject.
// Key configuration:
locationManager.desiredAccuracy              = kCLLocationAccuracyBest
locationManager.distanceFilter               = 5          // update every 5 meters
locationManager.allowsBackgroundLocationUpdates = true
locationManager.pausesLocationUpdatesAutomatically = false
locationManager.showsBackgroundLocationIndicator   = true  // blue pill in status bar
```

**GPS Filtering Logic (inside `locationManager(_:didUpdateLocations:)`):**
```
Reject point if:
  - location.horizontalAccuracy < 0       (invalid)
  - location.horizontalAccuracy > 20      (too inaccurate)
  - location.timestamp < Date() - 10      (stale, older than 10s)
  - speed < -0.5 AND activityType == .run (stationary noise)
```

**Distance Calculation:**
```swift
// Use CLLocation.distance(from:) — do NOT implement Haversine manually
let delta = newLocation.distance(from: previousLocation)  // returns meters
```

**Pace Calculation:**
```swift
// Rolling 10-second average speed
var recentPoints: [LocationPoint] = []  // sliding window
// pace (sec/km) = 1000 / averageSpeedInMPS
```

**Published Properties:**
```swift
@Published var currentLocation:  CLLocation?
@Published var authStatus:        CLAuthorizationStatus = .notDetermined
@Published var isTracking:        Bool = false
```

**Methods:**
```swift
func requestAuthorization()
func startTracking()   // call when user taps Start
func stopTracking()    // call when finishing
func pauseTracking()
func resumeTracking()
```

### 6.2 `MotionService.swift`

```swift
// Uses CMMotionActivityManager for auto-pause and CMPedometer for step count.
// Auto-pause: if CMMotionActivity.stationary == true for > 15 seconds,
//             post Notification "ShouldAutoPause"
// TrackingViewModel observes this notification and transitions to .paused.

let pedometer = CMPedometer()
// Start with: pedometer.startUpdates(from: session.startTime)
// Exposes: @Published var stepCount: Int
```

### 6.3 `LiveActivityManager.swift`

**ActivityAttributes struct** (in shared file, used by both app target and widget target):
```swift
struct ActivityTrackerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var distanceMeters: Double
        var paceSecondsPerKm: Double
        var activityType: String
    }
    var sessionID: String
}
```

**Methods:**
```swift
func startLiveActivity(for session: ActivitySession)
// Calls Activity<ActivityTrackerAttributes>.request(...)

func updateLiveActivity(elapsed: Int, distance: Double, pace: Double)
// Calls activity.update(using: newContentState)
// Call this every 5 seconds from TrackingViewModel

func endLiveActivity()
// Calls activity.end(dismissalPolicy: .immediate)
```

### 6.4 `PersistenceController.swift`

```swift
@MainActor
class PersistenceController {
    static let shared = PersistenceController()
    let container: ModelContainer

    init() {
        let schema = Schema([ActivitySession.self, LocationPoint.self])
        container = try! ModelContainer(for: schema)
    }
}
```

**Save pattern (call from TrackingViewModel on finish):**
```swift
let context = PersistenceController.shared.container.mainContext
context.insert(completedSession)
try context.save()
```

---

## 7. ViewModels

### 7.1 `TrackingViewModel.swift`

**Responsibilities:**
- Owns the state machine (see Section 5)
- Subscribes to `LocationManagerService` via Combine or Swift Concurrency
- Drives `LiveActivityManager` updates every 5 seconds using a `Timer`
- Accumulates `totalDistance`, `totalDuration`, `elevationGain`
- Formats values for display

**Published/Observable properties for UI:**
```swift
var state:            TrackingState = .idle
var elapsedTime:      String = "00:00"     // mm:ss
var currentPace:      String = "--:--"     // mm:ss per km
var totalDistance:    String = "0.00 km"
var stepCount:        String = "0"
var coordinates:      [[CLLocationCoordinate2D]] = [[]]
// Note: coordinates is an array of SEGMENTS (inner array).
// A new segment is appended each time tracking resumes from pause.
// This allows drawing a broken polyline that skips the paused gap.
```

**Timer logic:**
```swift
// Start a 1-second timer when state = .tracking
// Increment elapsedSeconds counter
// Every 5 seconds, call LiveActivityManager.update(...)
// Stop timer when state = .paused or .finishing
```

### 7.2 `HistoryViewModel.swift`

```swift
@Observable class HistoryViewModel {
    var sessions: [ActivitySession] = []

    func loadSessions(context: ModelContext) {
        let descriptor = FetchDescriptor<ActivitySession>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        sessions = (try? context.fetch(descriptor)) ?? []
    }
}
```

---

## 8. Views

### 8.1 `HomeView.swift`
- 3 buttons for activity type selection (Run / Walk / Ride) using SF Symbols
- Large "Start" button → triggers `TrackingViewModel.tapStart(type:)`
- Navigates to `TrackingView` on start (use `.fullScreenCover` or `NavigationStack`)
- Bottom tab bar: Home | History

### 8.2 `TrackingView.swift`

**Map component:**
```swift
Map(position: $cameraPosition) {
    // Draw each segment as a separate MapPolyline
    ForEach(viewModel.coordinates.indices, id: \.self) { i in
        MapPolyline(coordinates: viewModel.coordinates[i])
            .stroke(.orange, lineWidth: 4)
    }
    // Current location dot
    if let loc = locationService.currentLocation {
        Annotation("", coordinate: loc.coordinate) {
            Circle()
                .fill(.blue)
                .frame(width: 16)
                .overlay(Circle().stroke(.white, lineWidth: 2))
        }
    }
}
.mapStyle(.standard(elevation: .realistic))
.onChange(of: locationService.currentLocation) { _, newLoc in
    // Auto-follow: update cameraPosition to center on user
    if let c = newLoc?.coordinate {
        cameraPosition = .region(MKCoordinateRegion(
            center: c,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        ))
    }
}
```

**Stats HUD (bottom overlay):**
```
┌─────────────────────────────────────┐
│  00:00        0.00 km       --:-- /km│
│  Time         Distance        Pace   │
├─────────────────────────────────────┤
│   [⏸ Pause]            [🏁 Finish]  │
└─────────────────────────────────────┘
```
- Dark semi-transparent background (`.ultraThinMaterial`)
- Orange accent color
- Pause button becomes Resume when state is `.paused`

### 8.3 `SummaryView.swift`
Shown when `TrackingState == .completed(let session)`.

Displays:
- Activity type, date, duration, distance, pace, elevation gain
- Static map snapshot (use `MKMapSnapshotter` to render route as image)
- Two export buttons: **"Export PNG"** and **"Export Flyover Video"**
- Both buttons show a loading indicator during export
- On export completion: show `ShareSheet` (`UIActivityViewController`)

### 8.4 `HistoryView.swift`
- `List` of past `ActivitySession` entries
- Each row: date, activity type icon, distance, duration
- Tap → `SummaryView` for that session (read-only, export still available)

---

## 9. Lock Screen / Dynamic Island (Widget Target)

**File: `ActivityTrackerWidget.swift`** (inside Widget Extension target)

```swift
struct ActivityTrackerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ActivityTrackerAttributes.self) { context in
            // Lock Screen banner UI
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.formattedDistance, systemImage: "location.fill")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Label(context.state.formattedPace, systemImage: "speedometer")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.formattedElapsed)
                        .font(.headline)
                }
            } compactLeading: {
                Image(systemName: "figure.run")
            } compactTrailing: {
                Text(context.state.formattedDistance)
            } minimal: {
                Image(systemName: "figure.run")
            }
        }
    }
}
```

**Lock Screen layout (dark bg, orange accent):**
```
╔══════════════════════════════════╗
║  🏃  ACTIVITY TRACKER — Running  ║
║  ────────────────────────────── ║
║  01:23:45    5.42 km    5:12/km  ║
║   Time       Distance    Pace    ║
╚══════════════════════════════════╝
```

---

## 10. Export Services

### 10.1 `PNGExportService.swift`

**Input:** `ActivitySession` (with `coordinates` and stats)  
**Output:** `UIImage` (transparent PNG)

**Steps:**
1. Compute bounding box of all coordinates. Add 10% padding.
2. Normalize all coordinates to fit a `1080×1080` canvas.
3. Use `UIGraphicsImageRenderer(size: CGSize(width: 1080, height: 1080))`:
   - Background: black `UIColor.black.setFill()`
   - Route: `UIBezierPath` → `UIColor.orange.setStroke()`, lineWidth = 6
   - Rounded caps: `bezierPath.lineCapStyle = .round`
4. Draw stat overlay in bottom-left corner:
   ```
   Distance: 5.42 km
   Duration: 01:23:45
   Pace:     5:12 /km
   Date:     Jun 19, 2026
   ```
5. Optionally draw a small activity type icon (SF Symbol rendered via `UIImage(systemName:)`)
6. Return the rendered `UIImage`

### 10.2 `FlyoverExportService.swift`

**Input:** `ActivitySession`  
**Output:** URL to `.mp4` file in `FileManager.default.temporaryDirectory`

**⚠️ This is the most complex feature. Implement it last.**

**Setup:**
```swift
// Must run on main thread (MKMapView requires it)
// Create an off-screen MKMapView — DO NOT add to the view hierarchy
let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 1080, height: 1920))
mapView.mapType = .hybridFlyover
mapView.isZoomEnabled = false
mapView.isScrollEnabled = false
mapView.isUserInteractionEnabled = false

// Draw the route polyline on the map
let polyline = MKPolyline(coordinates: coords, count: coords.count)
mapView.addOverlay(polyline)
mapView.delegate = self  // for MKMapViewDelegate to style the overlay
```

**Camera Path:**
```swift
// Subsample coordinates to ~200 camera positions for a smooth path
let cameraCoords = stride(from: 0, to: coords.count, by: max(1, coords.count / 200))
    .map { coords[$0] }

// For each position i, create:
let camera = MKMapCamera(
    lookingAtCenter:  cameraCoords[i],
    fromDistance:     300,   // meters above ground
    pitch:            60,    // degrees (0 = top-down, 90 = horizon)
    heading:          bearing(from: cameraCoords[i], to: cameraCoords[min(i+1, ...)])
)
```

**Bearing helper:**
```swift
func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
    let lat1 = from.latitude.toRadians()
    let lat2 = to.latitude.toRadians()
    let dLon = (to.longitude - from.longitude).toRadians()
    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
    return (atan2(y, x).toDegrees() + 360).truncatingRemainder(dividingBy: 360)
}
```

**Frame Rendering & Encoding:**
```swift
// AVAssetWriter setup
let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
let settings: [String: Any] = [
    AVVideoCodecKey:  AVVideoCodecType.h264,
    AVVideoWidthKey:  1080,
    AVVideoHeightKey: 1920,
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, ...)
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

// Target: 30 fps, ~10 seconds total = 300 frames
let fps: Int32 = 30
let totalFrames = 300

for frameIndex in 0..<totalFrames {
    // 1. Set camera to interpolated position
    let progress = Double(frameIndex) / Double(totalFrames)
    let coordIndex = Int(progress * Double(cameraCoords.count - 1))
    mapView.camera = cameraAtIndex(coordIndex)

    // 2. Wait for map tile rendering (critical — use semaphore + MKMapView delegate)
    //    Hook into mapViewDidFinishRenderingMap to know when it's ready.

    // 3. Capture frame
    UIGraphicsBeginImageContextWithOptions(mapView.bounds.size, true, 1.0)
    mapView.layer.render(in: UIGraphicsGetCurrentContext()!)
    let frameImage = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()

    // 4. Convert UIImage → CVPixelBuffer → feed to adaptor
    let time = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
    adaptor.append(pixelBuffer, withPresentationTime: time)
}

input.markAsFinished()
await writer.finishWriting()
```

**Memory Warning:** Release the off-screen `mapView` immediately after export completes. Each snapshot holds significant memory.

---

## 11. Error Handling Strategy

| Scenario | Handling |
|---|---|
| Location permission denied | Show inline prompt in `HomeView` with "Open Settings" button. Disable Start button. |
| GPS accuracy degraded mid-run | Filter out bad points (see Section 6.1). Show brief toast "GPS signal weak". |
| App killed in background | On next launch, check for incomplete `ActivitySession` (endTime == nil). Offer to discard or keep partial data. |
| SwiftData save failure | Log error, show alert "Could not save session. Data may be lost." |
| Flyover map tiles not loaded | Timeout after 3 seconds per frame; use previous frame if timeout occurs. |
| Live Activity not supported | Wrap `ActivityKit` calls in `#available(iOS 16.2, *)` and `ActivityAuthorizationInfo().areActivitiesEnabled`. |

---

## 12. Permissions Flow (First Launch)

```
App Launch
    │
    ├─► Check CLAuthorizationStatus
    │       .notDetermined → requestAlwaysAuthorization()
    │       .denied / .restricted → show PermissionDeniedView
    │       .authorizedAlways → proceed
    │
    ├─► Check CMMotionActivityManager.isActivityAvailable()
    │       false → disable auto-pause silently (not critical)
    │
    └─► Check ActivityAuthorizationInfo().areActivitiesEnabled
            false → disable Live Activity silently (not critical)
```

---

## 13. Implementation Order (Suggested for AI Agent)

Build in this order to always have a runnable app at each step:

1. **Models** → `ActivityType`, `LocationPoint`, `ActivitySession`
2. **PersistenceController** → verify SwiftData schema compiles
3. **LocationManagerService** → request auth, log GPS points to console
4. **TrackingViewModel** → state machine, connect to LocationService
5. **HomeView + TrackingView** → basic map with orange polyline
6. **Background tracking** → verify blue pill appears when screen is off
7. **LiveActivityManager + Widget** → Lock Screen stats
8. **SummaryView** → display stats after finish, save to SwiftData
9. **HistoryView** → list past sessions
10. **PNGExportService** → route card image
11. **FlyoverExportService** → 3D video (implement last, most complex)

---

## 14. Acceptance Criteria

The app is considered complete when:

- [ ] User can select Run / Walk / Ride and tap Start
- [ ] Orange polyline draws in real-time on the map as the user moves
- [ ] Map camera follows the user's position automatically
- [ ] Locking the screen shows a Live Activity with elapsed time, distance, pace
- [ ] Tapping Pause freezes the polyline; tapping Resume continues it (with a gap)
- [ ] Tapping Finish saves the session and navigates to SummaryView
- [ ] SummaryView shows all stats and a static map snapshot of the route
- [ ] "Export PNG" produces a 1080×1080 image shareable via the system share sheet
- [ ] "Export Flyover" produces an .mp4 video and shares it via the system share sheet
- [ ] Past sessions are listed in HistoryView and viewable individually
- [ ] All features work without an internet connection (except map tiles)

---

## 15. Key Dependencies

| Feature | Framework | Notes |
|---|---|---|
| UI | SwiftUI | iOS 17+ features encouraged |
| GPS | CoreLocation | `CLLocationManager` |
| Motion | CoreMotion | `CMPedometer`, `CMMotionActivityManager` |
| Map | MapKit | SwiftUI `Map` view (iOS 17 API) |
| Lock Screen | ActivityKit | iOS 16.2+ |
| Database | SwiftData | iOS 17+ |
| PNG Export | UIKit | `UIGraphicsImageRenderer` |
| Video Export | AVFoundation | `AVAssetWriter` |
| Map Snapshot | MapKit | `MKMapSnapshotter` (summary), off-screen `MKMapView` (flyover) |

**No third-party dependencies required.**
