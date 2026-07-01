import CoreLocation
import MapKit

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }

    static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude.toRadians()
        let lat2 = end.latitude.toRadians()
        let deltaLongitude = (end.longitude - start.longitude).toRadians()
        let y = sin(deltaLongitude) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLongitude)
        return (atan2(y, x).toDegrees() + 360).truncatingRemainder(dividingBy: 360)
    }
}

extension Array where Element == CLLocationCoordinate2D {
    var boundingRegion: MKCoordinateRegion {
        guard let first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
        }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude

        for coordinate in self {
            minLatitude = Swift.min(minLatitude, coordinate.latitude)
            maxLatitude = Swift.max(maxLatitude, coordinate.latitude)
            minLongitude = Swift.min(minLongitude, coordinate.longitude)
            maxLongitude = Swift.max(maxLongitude, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let latitudeDelta = Swift.max(maxLatitude - minLatitude, 0.004)
        let longitudeDelta = Swift.max(maxLongitude - minLongitude, 0.004)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta * 1.25,
                longitudeDelta: longitudeDelta * 1.25
            )
        )
    }
}

extension Double {
    func toRadians() -> Double {
        self * .pi / 180
    }

    func toDegrees() -> Double {
        self * 180 / .pi
    }
}
