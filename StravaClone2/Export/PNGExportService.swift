import CoreLocation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum PNGExportError: LocalizedError {
    case missingRenderedImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .missingRenderedImage:
            "Could not create the transparent route image."
        case .encodingFailed:
            "Could not encode the route card as a PNG file."
        }
    }
}

@MainActor
final class PNGExportService {
    func render(session: ActivitySession) -> UIImage {
        let size = CGSize(width: 1080, height: 1080)
        let coordinates = session.coordinates
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            context.cgContext.setBlendMode(.copy)
            UIColor.clear.setFill()
            context.fill(rect)
            context.cgContext.setBlendMode(.normal)

            drawRoute(coordinates, in: size)
            drawIcon(for: session.activityType, in: size)
            drawStats(for: session, in: size)
        }
    }

    func makePNGData(session: ActivitySession) throws -> Data {
        let image = render(session: session)
        guard let cgImage = image.cgImage else { throw PNGExportError.missingRenderedImage }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw PNGExportError.encodingFailed
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw PNGExportError.encodingFailed }

        return data as Data
    }

    func writePNGFile(session: ActivitySession) throws -> URL {
        let data = try makePNGData(session: session)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("activity-summary-\(session.id.uuidString).png")
        try data.write(to: url, options: [.atomic])
        return url
    }

    private func drawRoute(_ coordinates: [CLLocationCoordinate2D], in size: CGSize) {
        guard coordinates.count > 1 else { return }

        let points = normalizedPoints(for: coordinates, in: size.insetBy(dx: 96, dy: 120))
        let path = UIBezierPath()

        for (index, point) in points.enumerated() {
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        UIColor.black.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 12
        path.stroke()

        UIColor.orange.setStroke()
        path.lineWidth = 7
        path.stroke()
    }

    private func drawIcon(for type: ActivityType, in size: CGSize) {
        guard let icon = UIImage(systemName: type.icon) else { return }

        let configuration = UIImage.SymbolConfiguration(pointSize: 56, weight: .semibold)
        let configuredIcon = icon.withConfiguration(configuration)

        configuredIcon
            .withTintColor(.black.withAlphaComponent(0.35), renderingMode: .alwaysOriginal)
            .draw(in: CGRect(x: 76, y: 76, width: 72, height: 72))

        configuredIcon
            .withTintColor(.orange, renderingMode: .alwaysOriginal)
            .draw(in: CGRect(x: 72, y: 72, width: 72, height: 72))
    }

    private func drawStats(for session: ActivitySession, in size: CGSize) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineSpacing = 8

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 34, weight: .semibold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph,
            .strokeColor: UIColor.black.withAlphaComponent(0.65),
            .strokeWidth: -3
        ]

        let dateText = session.startTime.formatted(date: .abbreviated, time: .omitted)
        let text = """
        Distance: \(session.totalDistance.kilometersText)
        Duration: \(session.totalDuration.longClockText)
        Pace:     \(session.averagePace.paceText) /km
        Date:     \(dateText)
        """

        text.draw(
            in: CGRect(x: 72, y: size.height - 278, width: size.width - 144, height: 220),
            withAttributes: attributes
        )
    }

    private func normalizedPoints(for coordinates: [CLLocationCoordinate2D], in rect: CGRect) -> [CGPoint] {
        let minLatitude = coordinates.map(\.latitude).min() ?? 0
        let maxLatitude = coordinates.map(\.latitude).max() ?? 0
        let minLongitude = coordinates.map(\.longitude).min() ?? 0
        let maxLongitude = coordinates.map(\.longitude).max() ?? 0

        let latitudeRange = max(maxLatitude - minLatitude, 0.0001)
        let longitudeRange = max(maxLongitude - minLongitude, 0.0001)

        return coordinates.map { coordinate in
            let x = rect.minX + ((coordinate.longitude - minLongitude) / longitudeRange) * rect.width
            let y = rect.minY + (1 - ((coordinate.latitude - minLatitude) / latitudeRange)) * rect.height
            return CGPoint(x: x, y: y)
        }
    }
}

private extension CGSize {
    func insetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        CGRect(x: dx, y: dy, width: width - dx * 2, height: height - dy * 2)
    }
}
