import Foundation

func close(_ actual: Double, _ expected: Double, tolerance: Double = 1e-6) {
    precondition(abs(actual - expected) <= tolerance, "Expected \(expected), got \(actual)")
}
close(MovementMath.clampedSpeed(.nan), 5)
close(MovementMath.clampedSpeed(.infinity), 5)
close(MovementMath.clampedSpeed(-1), 0.1)
close(MovementMath.clampedSpeed(500), 300)
close(MovementMath.clampedSpeed(7.2)/3.6, 2)
let midpoint = MovementMath.interpolate(latitude: 0, longitude: 179.9,
                                         toLatitude: 0, toLongitude: -179.9, fraction: 0.5)
close(abs(midpoint.longitude), 180)
close(midpoint.latitude, 0)
let endpoint = MovementMath.interpolate(latitude: 24.9, longitude: 121.3,
                                         toLatitude: 25, toLongitude: 121.4, fraction: 1)
close(endpoint.latitude, 25)
close(endpoint.longitude, 121.4)
let east = MovementMath.offset(latitude: 0, longitude: 0, eastMeters: 1000, northMeters: 0)
close(east.latitude, 0)
close(east.longitude, 1000/6378137 * 180 / .pi)
let north = MovementMath.offset(latitude: 89.999, longitude: 0, eastMeters: 0, northMeters: 1000)
precondition(north.latitude.isFinite && (-90...90).contains(north.latitude))
precondition(north.longitude.isFinite && (-180...180).contains(north.longitude))
print("MovementMath: all checks passed")

// MARK: GoogleMapsLink
func expectCoord(_ input: GoogleMapsLink.Input?, _ lat: Double, _ lon: Double, _ label: String) {
    guard case .coordinate(let c)? = input else { preconditionFailure("\(label): expected coordinate, got \(String(describing: input))") }
    close(c.latitude, lat); close(c.longitude, lon)
}
expectCoord(GoogleMapsLink.classify("24.93452, 121.37124"), 24.93452, 121.37124, "plain comma")
expectCoord(GoogleMapsLink.classify(" 24.93452,121.37124 "), 24.93452, 121.37124, "plain no space")
expectCoord(GoogleMapsLink.classify("(25.0339640, 121.5644720)"), 25.033964, 121.564472, "parenthesised")
expectCoord(GoogleMapsLink.classify("https://www.google.com/maps/place/%E5%8F%B0%E5%8C%97101/@25.0339687,121.5622835,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d25.033964!4d121.5644722"), 25.033964, 121.5644722, "place !3d!4d wins over @")
expectCoord(GoogleMapsLink.classify("https://www.google.com.tw/maps/@24.9345,121.3712,15z"), 24.9345, 121.3712, "camera @")
expectCoord(GoogleMapsLink.classify("https://maps.google.com/?q=24.9345,121.3712"), 24.9345, 121.3712, "q=")
expectCoord(GoogleMapsLink.classify("https://www.google.com/maps/search/?api=1&query=24.9345%2C121.3712"), 24.9345, 121.3712, "query= encoded comma")
expectCoord(GoogleMapsLink.classify("https://www.google.com/maps/search/24.9345,+121.3712?entry=ttu"), 24.9345, 121.3712, "search path")
expectCoord(GoogleMapsLink.classify("https://www.google.com/maps/dir/?api=1&destination=24.9345,121.3712"), 24.9345, 121.3712, "destination")
if case .link(let u)? = GoogleMapsLink.classify("臺北101\nhttps://maps.app.goo.gl/AbCdEf123") {
    precondition(u.absoluteString == "https://maps.app.goo.gl/AbCdEf123", "short link extracted")
} else { preconditionFailure("short link in share text") }
precondition(GoogleMapsLink.classify("全家便利商店") == nil, "plain name is not a link")
precondition(GoogleMapsLink.classify("https://example.com/@24.9,121.3") == nil, "non-Google host ignored")
precondition(GoogleMapsLink.classify("124.5, 121.3") == nil, "latitude out of range")
precondition(GoogleMapsLink.placeName(fromURLString: "https://maps.google.com/maps?q=%E8%87%BA%E5%8C%97101&ftid=0x1") == "臺北101", "q name")
let body = "<meta content=\"https://maps.google.com/maps/api/staticmap?center=24.9345%2C121.3712&amp;zoom=15\" property=\"og:image\">"
precondition(GoogleMapsLink.coordinate(fromPageBody: body) == .init(latitude: 24.9345, longitude: 121.3712), "page body center")
print("GoogleMapsLink: all checks passed")
