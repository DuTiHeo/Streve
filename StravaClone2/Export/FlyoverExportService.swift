@preconcurrency import AVFoundation
import CoreLocation
import MapKit
import UIKit

enum FlyoverExportError: LocalizedError {
    case routeTooShort
    case writerSetupFailed
    case pixelBufferCreationFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .routeTooShort:
            return "The route needs at least two GPS points to export a flyover."
        case .writerSetupFailed:
            return "Could not set up the video writer."
        case .pixelBufferCreationFailed:
            return "Could not render a video frame."
        case .exportFailed:
            return "The flyover video export did not complete."
        }
    }
}

@MainActor
final class FlyoverExportService {
    private let videoSize = CGSize(width: 1080, height: 1920)
    private let fps: Int32 = 30
    private let introFrames = 45
    private let travelFrames = 240
    private let outroFrames = 45
    private let flyoverCameraDistance: CLLocationDistance = 650
    private let topDownCameraDistance: CLLocationDistance = 2200
    private let flyoverCameraPitch: CGFloat = 62
    private let topDownCameraPitch: CGFloat = 0

    private var totalFrames: Int {
        introFrames + travelFrames + outroFrames
    }

    func export(session: ActivitySession) async throws -> URL {
        let routeSamples = session.locationPoints
            .sorted { $0.timestamp < $1.timestamp }
            .map {
                RouteSample(
                    coordinate: $0.coordinate,
                    altitude: $0.altitude,
                    timestamp: $0.timestamp
                )
            }
        guard routeSamples.count > 1 else { throw FlyoverExportError.routeTooShort }

        let route = RouteSampler(samples: routeSamples)
        guard route.totalDistance > 1 else { throw FlyoverExportError.routeTooShort }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("activity-flyover-\(UUID().uuidString).mp4")

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(videoSize.width),
                AVVideoHeightKey: Int(videoSize.height)
            ]
        )
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(videoSize.width),
                kCVPixelBufferHeightKey as String: Int(videoSize.height),
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
        )

        guard writer.canAdd(input) else { throw FlyoverExportError.writerSetupFailed }
        writer.add(input)

        guard writer.startWriting() else { throw writer.error ?? FlyoverExportError.writerSetupFailed }
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<totalFrames {
            try Task.checkCancellation()

            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            let state = playbackState(for: frameIndex)
            let currentCoordinate = route.coordinate(atProgress: state.routeProgress)
            let visibleCoordinates = route.visibleCoordinates(through: state.routeProgress)
            let stats = route.stats(
                atProgress: state.routeProgress,
                fallbackDuration: session.totalDuration
            )

            let image = await renderFrame(
                fullCoordinates: route.coordinates,
                visibleCoordinates: visibleCoordinates,
                currentCoordinate: currentCoordinate,
                camera: camera(progress: state.routeProgress, cameraBlend: state.cameraBlend, route: route),
                stats: stats,
                activityTitle: session.activityType.rawValue
            )

            guard let pixelBuffer = makePixelBuffer(from: image, adaptor: adaptor) else {
                throw FlyoverExportError.pixelBufferCreationFailed
            }

            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }

        input.markAsFinished()
        let writerBox = UncheckedSendableBox(value: writer)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                let writer = writerBox.value
                if writer.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: writer.error ?? FlyoverExportError.exportFailed)
                }
            }
        }

        return outputURL
    }

    private func renderFrame(
        fullCoordinates: [CLLocationCoordinate2D],
        visibleCoordinates: [CLLocationCoordinate2D],
        currentCoordinate: CLLocationCoordinate2D,
        camera: MKMapCamera,
        stats: FlyoverFrameStats,
        activityTitle: String
    ) async -> UIImage {
        let options = MKMapSnapshotter.Options()
        options.size = videoSize
        options.scale = 1
        options.camera = camera
        options.mapType = .hybridFlyover

        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            return drawRoute(
                on: snapshot,
                visibleCoordinates: visibleCoordinates,
                currentCoordinate: currentCoordinate,
                stats: stats,
                activityTitle: activityTitle
            )
        } catch {
            return drawFallbackRoute(
                fullCoordinates: fullCoordinates,
                visibleCoordinates: visibleCoordinates,
                currentCoordinate: currentCoordinate,
                stats: stats,
                activityTitle: activityTitle
            )
        }
    }

    private func drawRoute(
        on snapshot: MKMapSnapshotter.Snapshot,
        visibleCoordinates: [CLLocationCoordinate2D],
        currentCoordinate: CLLocationCoordinate2D,
        stats: FlyoverFrameStats,
        activityTitle: String
    ) -> UIImage {
        UIGraphicsImageRenderer(size: videoSize).image { _ in
            snapshot.image.draw(in: CGRect(origin: .zero, size: videoSize))

            drawPath(points: visibleCoordinates.map { snapshot.point(for: $0) })
            drawCurrentPoint(at: snapshot.point(for: currentCoordinate))
            drawStatsOverlay(stats: stats, activityTitle: activityTitle)
        }
    }

    private func drawFallbackRoute(
        fullCoordinates: [CLLocationCoordinate2D],
        visibleCoordinates: [CLLocationCoordinate2D],
        currentCoordinate: CLLocationCoordinate2D,
        stats: FlyoverFrameStats,
        activityTitle: String
    ) -> UIImage {
        UIGraphicsImageRenderer(size: videoSize).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: videoSize))

            let rect = CGRect(x: 96, y: 220, width: videoSize.width - 192, height: videoSize.height - 440)
            let bounds = CoordinateBounds(coordinates: fullCoordinates)
            let points = normalizedPoints(for: visibleCoordinates, in: rect, bounds: bounds)
            drawPath(points: points)
            drawCurrentPoint(at: normalizedPoint(for: currentCoordinate, in: rect, bounds: bounds))
            drawStatsOverlay(stats: stats, activityTitle: activityTitle)
        }
    }

    private func drawPath(points: [CGPoint]) {
        guard points.count > 1 else { return }

        let path = UIBezierPath()
        for (index, point) in points.enumerated() {
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        UIColor.black.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 12
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()

        UIColor.orange.setStroke()
        path.lineWidth = 7
        path.stroke()
    }

    private func drawCurrentPoint(at point: CGPoint) {
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)).fill()

        UIColor.orange.setFill()
        UIBezierPath(ovalIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)).fill()
    }

    private func drawStatsOverlay(stats: FlyoverFrameStats, activityTitle: String) {
        drawTopGradient()

        drawText(
            "ACTIVITY",
            in: CGRect(x: 0, y: 74, width: videoSize.width, height: 64),
            font: UIFont.systemFont(ofSize: 54, weight: .black),
            color: .white,
            alignment: .center
        )

        drawText(
            activityTitle,
            in: CGRect(x: 0, y: 142, width: videoSize.width, height: 38),
            font: UIFont.systemFont(ofSize: 26, weight: .semibold),
            color: UIColor.white.withAlphaComponent(0.9),
            alignment: .center
        )

        let columnWidth = videoSize.width / 3
        let top: CGFloat = 204
        drawStatColumn(
            label: "Pace",
            value: stats.paceText,
            unit: "/km",
            rect: CGRect(x: 0, y: top, width: columnWidth, height: 154)
        )
        drawStatColumn(
            label: "Elevation",
            value: stats.elevationText,
            unit: "m",
            rect: CGRect(x: columnWidth, y: top, width: columnWidth, height: 154)
        )
        drawStatColumn(
            label: "Distance",
            value: stats.distanceText,
            unit: "km",
            rect: CGRect(x: columnWidth * 2, y: top, width: columnWidth, height: 154)
        )
    }

    private func drawTopGradient() {
        guard let context = UIGraphicsGetCurrentContext(),
              let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.black.withAlphaComponent(0.62).cgColor,
                    UIColor.black.withAlphaComponent(0.38).cgColor,
                    UIColor.clear.cgColor
                ] as CFArray,
                locations: [0, 0.58, 1]
              ) else { return }

        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: videoSize.width / 2, y: 0),
            end: CGPoint(x: videoSize.width / 2, y: 460),
            options: []
        )
    }

    private func drawStatColumn(label: String, value: String, unit: String, rect: CGRect) {
        drawText(
            label,
            in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 34),
            font: UIFont.systemFont(ofSize: 24, weight: .bold),
            color: UIColor.white.withAlphaComponent(0.82),
            alignment: .center
        )
        drawText(
            value,
            in: CGRect(x: rect.minX, y: rect.minY + 36, width: rect.width, height: 72),
            font: UIFont.monospacedDigitSystemFont(ofSize: 58, weight: .heavy),
            color: .white,
            alignment: .center
        )
        drawText(
            unit,
            in: CGRect(x: rect.minX, y: rect.minY + 110, width: rect.width, height: 38),
            font: UIFont.systemFont(ofSize: 28, weight: .semibold),
            color: UIColor.white.withAlphaComponent(0.9),
            alignment: .center
        )
    }

    private func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment

        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.65)
        shadow.shadowBlurRadius = 7
        shadow.shadowOffset = CGSize(width: 0, height: 2)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .shadow: shadow
        ]

        text.draw(in: rect, withAttributes: attributes)
    }

    private func camera(progress: Double, cameraBlend: Double, route: RouteSampler) -> MKMapCamera {
        let currentDistance = route.totalDistance * min(max(progress, 0), 1)
        let lookAheadDistance = min(max(route.totalDistance * 0.04, 25), 120)
        let current = route.coordinate(atDistance: currentDistance)
        let forwardDistance = min(currentDistance + lookAheadDistance, route.totalDistance)
        let backwardDistance = max(currentDistance - lookAheadDistance, 0)
        let cameraBlend = min(max(cameraBlend, 0), 1)

        let heading: CLLocationDirection
        if forwardDistance - currentDistance > 1 {
            heading = CLLocationCoordinate2D.bearing(
                from: current,
                to: route.coordinate(atDistance: forwardDistance)
            )
        } else {
            heading = CLLocationCoordinate2D.bearing(
                from: route.coordinate(atDistance: backwardDistance),
                to: current
            )
        }

        return MKMapCamera(
            lookingAtCenter: current,
            fromDistance: interpolate(from: topDownCameraDistance, to: flyoverCameraDistance, ratio: cameraBlend),
            pitch: interpolate(from: topDownCameraPitch, to: flyoverCameraPitch, ratio: cameraBlend),
            heading: heading
        )
    }

    private func playbackState(for frameIndex: Int) -> FlyoverPlaybackState {
        if frameIndex < introFrames {
            let progress = Double(frameIndex) / Double(max(introFrames - 1, 1))
            return FlyoverPlaybackState(routeProgress: 0, cameraBlend: smoothedProgress(progress))
        }

        if frameIndex < introFrames + travelFrames {
            let travelIndex = frameIndex - introFrames
            let progress = Double(travelIndex) / Double(max(travelFrames - 1, 1))
            return FlyoverPlaybackState(routeProgress: smoothedProgress(progress), cameraBlend: 1)
        }

        let outroIndex = frameIndex - introFrames - travelFrames
        let progress = Double(outroIndex) / Double(max(outroFrames - 1, 1))
        return FlyoverPlaybackState(routeProgress: 1, cameraBlend: 1 - smoothedProgress(progress))
    }

    private func smoothedProgress(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    private func interpolate(from start: Double, to end: Double, ratio: Double) -> Double {
        start + (end - start) * min(max(ratio, 0), 1)
    }

    private func normalizedPoints(
        for coordinates: [CLLocationCoordinate2D],
        in rect: CGRect,
        bounds: CoordinateBounds
    ) -> [CGPoint] {
        coordinates.map { normalizedPoint(for: $0, in: rect, bounds: bounds) }
    }

    private func normalizedPoint(
        for coordinate: CLLocationCoordinate2D,
        in rect: CGRect,
        bounds: CoordinateBounds
    ) -> CGPoint {
        let x = rect.minX + ((coordinate.longitude - bounds.minLongitude) / bounds.longitudeRange) * rect.width
        let y = rect.minY + (1 - ((coordinate.latitude - bounds.minLatitude) / bounds.latitudeRange)) * rect.height
        return CGPoint(x: x, y: y)
    }

    private func makePixelBuffer(
        from image: UIImage,
        adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) -> CVPixelBuffer? {
        guard let pool = adaptor.pixelBufferPool else { return nil }

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(videoSize.width),
            height: Int(videoSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: videoSize))

        guard let cgImage = image.cgImage else { return nil }
        context.draw(cgImage, in: CGRect(origin: .zero, size: videoSize))

        return pixelBuffer
    }
}

private struct FlyoverPlaybackState {
    let routeProgress: Double
    let cameraBlend: Double
}

private struct FlyoverFrameStats {
    let distance: CLLocationDistance
    let elevationGain: CLLocationDistance
    let pace: TimeInterval

    var paceText: String {
        pace.paceText
    }

    var elevationText: String {
        String(format: "%.0f", elevationGain)
    }

    var distanceText: String {
        String(format: distance >= 10_000 ? "%.1f" : "%.2f", distance / 1000)
    }
}

private struct RouteSample {
    let coordinate: CLLocationCoordinate2D
    let altitude: CLLocationDistance
    let timestamp: Date
}

private struct RouteSampler {
    private let samples: [RouteSample]
    let coordinates: [CLLocationCoordinate2D]
    private let cumulativeDistances: [CLLocationDistance]
    private let cumulativeElevationGains: [CLLocationDistance]
    private let cumulativeElapsedTimes: [TimeInterval]
    let totalDistance: CLLocationDistance

    init(samples: [RouteSample]) {
        var filteredSamples: [RouteSample] = []

        for sample in samples {
            guard let previous = filteredSamples.last else {
                filteredSamples.append(sample)
                continue
            }

            if previous.coordinate.distance(to: sample.coordinate) >= 0.5 {
                filteredSamples.append(sample)
            }
        }

        if filteredSamples.count < 2, let first = samples.first, let last = samples.last {
            filteredSamples = [first, last]
        }

        self.samples = filteredSamples
        self.coordinates = filteredSamples.map(\.coordinate)

        var distances = [CLLocationDistance]()
        var elevationGains = [CLLocationDistance]()
        var elapsedTimes = [TimeInterval]()
        var total: CLLocationDistance = 0
        var elevationGain: CLLocationDistance = 0
        let startTime = filteredSamples.first?.timestamp ?? Date()

        for index in filteredSamples.indices {
            if index == filteredSamples.startIndex {
                distances.append(0)
                elevationGains.append(0)
                elapsedTimes.append(0)
            } else {
                total += filteredSamples[index - 1].coordinate.distance(to: filteredSamples[index].coordinate)
                elevationGain += max(filteredSamples[index].altitude - filteredSamples[index - 1].altitude, 0)
                distances.append(total)
                elevationGains.append(elevationGain)
                elapsedTimes.append(max(0, filteredSamples[index].timestamp.timeIntervalSince(startTime)))
            }
        }

        self.cumulativeDistances = distances
        self.cumulativeElevationGains = elevationGains
        self.cumulativeElapsedTimes = elapsedTimes
        self.totalDistance = total
    }

    func coordinate(atProgress progress: Double) -> CLLocationCoordinate2D {
        coordinate(atDistance: totalDistance * min(max(progress, 0), 1))
    }

    func coordinate(atDistance targetDistance: CLLocationDistance) -> CLLocationCoordinate2D {
        guard coordinates.count > 1, totalDistance > 0 else {
            return coordinates.first ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }

        let targetDistance = min(max(targetDistance, 0), totalDistance)
        if targetDistance <= 0 {
            return coordinates[0]
        }

        for index in 1..<coordinates.count where cumulativeDistances[index] >= targetDistance {
            let previousDistance = cumulativeDistances[index - 1]
            let segmentDistance = cumulativeDistances[index] - previousDistance
            guard segmentDistance > 0 else { return coordinates[index] }

            let ratio = (targetDistance - previousDistance) / segmentDistance
            return CLLocationCoordinate2D.interpolate(
                from: coordinates[index - 1],
                to: coordinates[index],
                ratio: ratio
            )
        }

        return coordinates[coordinates.count - 1]
    }

    func stats(atProgress progress: Double, fallbackDuration: TimeInterval) -> FlyoverFrameStats {
        let targetDistance = totalDistance * min(max(progress, 0), 1)
        let elapsed = elapsedTime(atDistance: targetDistance, fallbackDuration: fallbackDuration)
        let elevationGain = interpolatedValue(
            in: cumulativeElevationGains,
            atDistance: targetDistance
        )
        let pace = targetDistance > 1 ? elapsed / (targetDistance / 1000) : 0

        return FlyoverFrameStats(
            distance: targetDistance,
            elevationGain: elevationGain,
            pace: pace
        )
    }

    func visibleCoordinates(through progress: Double) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 1, totalDistance > 0 else { return coordinates }

        let targetDistance = totalDistance * min(max(progress, 0), 1)
        var visibleCoordinates = [coordinates[0]]

        for index in 1..<coordinates.count {
            if cumulativeDistances[index] < targetDistance {
                visibleCoordinates.append(coordinates[index])
            } else {
                visibleCoordinates.append(coordinate(atDistance: targetDistance))
                break
            }
        }

        return visibleCoordinates
    }

    private func elapsedTime(
        atDistance targetDistance: CLLocationDistance,
        fallbackDuration: TimeInterval
    ) -> TimeInterval {
        let elapsedTime = interpolatedValue(in: cumulativeElapsedTimes, atDistance: targetDistance)
        if elapsedTime > 0 {
            return elapsedTime
        }

        return fallbackDuration * min(max(targetDistance / max(totalDistance, 1), 0), 1)
    }

    private func interpolatedValue(
        in values: [Double],
        atDistance targetDistance: CLLocationDistance
    ) -> Double {
        guard values.count == cumulativeDistances.count, values.count > 1, totalDistance > 0 else {
            return values.last ?? 0
        }

        let targetDistance = min(max(targetDistance, 0), totalDistance)
        if targetDistance <= 0 {
            return values[0]
        }

        for index in 1..<cumulativeDistances.count where cumulativeDistances[index] >= targetDistance {
            let previousDistance = cumulativeDistances[index - 1]
            let segmentDistance = cumulativeDistances[index] - previousDistance
            guard segmentDistance > 0 else { return values[index] }

            let ratio = (targetDistance - previousDistance) / segmentDistance
            return values[index - 1] + (values[index] - values[index - 1]) * ratio
        }

        return values[values.count - 1]
    }
}

private struct CoordinateBounds {
    let minLatitude: Double
    let minLongitude: Double
    let latitudeRange: Double
    let longitudeRange: Double

    init(coordinates: [CLLocationCoordinate2D]) {
        let minLatitude = coordinates.map(\.latitude).min() ?? 0
        let maxLatitude = coordinates.map(\.latitude).max() ?? 0
        let minLongitude = coordinates.map(\.longitude).min() ?? 0
        let maxLongitude = coordinates.map(\.longitude).max() ?? 0

        self.minLatitude = minLatitude
        self.minLongitude = minLongitude
        self.latitudeRange = max(maxLatitude - minLatitude, 0.0001)
        self.longitudeRange = max(maxLongitude - minLongitude, 0.0001)
    }
}

private extension CLLocationCoordinate2D {
    static func interpolate(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        ratio: Double
    ) -> CLLocationCoordinate2D {
        let ratio = min(max(ratio, 0), 1)
        return CLLocationCoordinate2D(
            latitude: start.latitude + (end.latitude - start.latitude) * ratio,
            longitude: start.longitude + (end.longitude - start.longitude) * ratio
        )
    }
}

private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}
