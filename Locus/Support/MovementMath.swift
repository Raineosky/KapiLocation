import Foundation

/// Pure geometry kept separate from the developer tunnel for offline tests.
enum MovementMath {
    static func clampedSpeed(_ kmh: Double) -> Double {
        kmh.isFinite ? min(300, max(0.1, kmh)) : 5
    }

    static func normalizedLongitude(_ longitude: Double) -> Double {
        let value = (longitude + 180).truncatingRemainder(dividingBy: 360)
        return (value < 0 ? value + 360 : value) - 180
    }

    static func interpolate(latitude: Double, longitude: Double,
                            toLatitude: Double, toLongitude: Double,
                            fraction: Double) -> (latitude: Double, longitude: Double) {
        let t = min(1, max(0, fraction))
        // Spherical interpolation keeps speed consistent even across the date line.
        func vector(_ lat: Double, _ lon: Double) -> (Double, Double, Double) {
            let p = lat * .pi / 180, l = lon * .pi / 180
            return (cos(p) * cos(l), cos(p) * sin(l), sin(p))
        }
        let a = vector(latitude, longitude), b = vector(toLatitude, toLongitude)
        let angle = acos(min(1, max(-1, a.0*b.0 + a.1*b.1 + a.2*b.2)))
        if abs(sin(angle)) < 1e-10 {
            return (latitude + (toLatitude - latitude) * t,
                    normalizedLongitude(longitude + normalizedLongitude(toLongitude - longitude) * t))
        }
        let u = sin((1-t)*angle)/sin(angle), v = sin(t*angle)/sin(angle)
        let x = u*a.0 + v*b.0, y = u*a.1 + v*b.1, z = u*a.2 + v*b.2
        return (atan2(z, hypot(x,y)) * 180 / .pi, atan2(y,x) * 180 / .pi)
    }

    static func offset(latitude: Double, longitude: Double,
                       eastMeters: Double, northMeters: Double) -> (latitude: Double, longitude: Double) {
        let angularDistance = hypot(eastMeters, northMeters) / 6378137
        let bearing = atan2(eastMeters, northMeters)
        let lat = latitude * .pi / 180, lon = longitude * .pi / 180
        let sine = sin(lat)*cos(angularDistance) + cos(lat)*sin(angularDistance)*cos(bearing)
        let nextLat = asin(min(1, max(-1, sine)))
        let nextLon = lon + atan2(sin(bearing)*sin(angularDistance)*cos(lat),
                                 cos(angularDistance)-sin(lat)*sin(nextLat))
        return (nextLat * 180 / .pi, normalizedLongitude(nextLon * 180 / .pi))
    }
}
