import Foundation

/// Turns Google Maps share links, Google Maps URLs and plain "lat, lng" text
/// into coordinates. No API key needed.
///
/// The parsing half is pure Foundation (no CoreLocation) so it can be checked
/// offline by `Tests/main.swift`.
enum GoogleMapsLink {
    struct Coordinate: Equatable {
        let latitude: Double
        let longitude: Double
    }

    /// What a piece of pasted / typed text looks like.
    enum Input: Equatable {
        /// Already a coordinate ("24.93, 121.37" or a full Google Maps URL that carries one).
        case coordinate(Coordinate)
        /// A Google Maps link that must be opened first (short link, or no coordinate in it).
        case link(URL)
    }

    // MARK: - Recognise input

    static func classify(_ text: String) -> Input? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let coord = plainCoordinate(trimmed) { return .coordinate(coord) }
        guard let url = firstGoogleMapsURL(in: trimmed) else { return nil }
        if let coord = coordinate(fromURLString: url.absoluteString) { return .coordinate(coord) }
        return .link(url)
    }

    /// "24.9345, 121.3712" / "24.9345,121.3712" / "24.9345 121.3712"
    static func plainCoordinate(_ text: String) -> Coordinate? {
        let pattern = #"^\s*\(?\s*(-?\d{1,2}(?:\.\d+)?)\s*[,，\s]\s*(-?\d{1,3}(?:\.\d+)?)\s*\)?\s*$"#
        guard let m = firstMatch(pattern, in: text), m.count == 2 else { return nil }
        return validated(m[0], m[1])
    }

    /// Finds the first Google Maps URL inside share text such as
    /// "臺北101\nhttps://maps.app.goo.gl/AbCd".
    static func firstGoogleMapsURL(in text: String) -> URL? {
        let pattern = #"https?://[^\s<>"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            var raw = String(text[r])
            while let last = raw.last, ")].,，。".contains(last) { raw.removeLast() }
            if let url = URL(string: raw), isGoogleMapsHost(url) { return url }
        }
        return nil
    }

    static func isGoogleMapsHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "maps.app.goo.gl" || host == "goo.gl" || host == "g.co" { return true }
        if host.hasPrefix("maps.google.") { return true }
        if host == "google.com" || host.hasSuffix(".google.com") || host.contains(".google.") {
            return url.path.hasPrefix("/maps") || host.hasPrefix("maps.")
        }
        return false
    }

    // MARK: - Read coordinates out of a URL (or a page body)

    /// Order matters: the place marker (!3d…!4d…) is the exact spot, while
    /// "@lat,lng" is only where the map camera was.
    static func coordinate(fromURLString raw: String) -> Coordinate? {
        let text = raw.removingPercentEncoding ?? raw
        let patterns = [
            #"!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)"#,
            #"[?&](?:q|query|ll|sll|daddr|destination|center)=(-?\d+(?:\.\d+)?)\s*,\s*\+?(-?\d+(?:\.\d+)?)"#,
            #"/place/(-?\d+(?:\.\d+)?)\s*,\s*\+?(-?\d+(?:\.\d+)?)"#,
            #"/search/(-?\d+(?:\.\d+)?)\s*,\s*\+?(-?\d+(?:\.\d+)?)"#,
            #"@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)"#,
        ]
        for pattern in patterns {
            if let m = firstMatch(pattern, in: text), m.count == 2, let c = validated(m[0], m[1]) {
                return c
            }
        }
        return nil
    }

    /// Fallback for pages whose final URL carries no coordinate: Google embeds the
    /// place location in the HTML (static map preview / APP_INITIALIZATION_STATE).
    static func coordinate(fromPageBody body: String) -> Coordinate? {
        let patterns = [
            #"!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)"#,
            #"center=(-?\d+\.\d+)(?:%2C|,)(-?\d+\.\d+)"#,
            #"markers=(-?\d+\.\d+)(?:%2C|,)(-?\d+\.\d+)"#,
            #"\[\s*null\s*,\s*null\s*,\s*(-?\d+\.\d{3,})\s*,\s*(-?\d+\.\d{3,})\s*\]"#,
        ]
        for pattern in patterns {
            if let m = firstMatch(pattern, in: body), m.count == 2, let c = validated(m[0], m[1]) {
                return c
            }
        }
        return nil
    }

    /// Place name to fall back on ("?q=臺北101" or "/place/臺北101/").
    static func placeName(fromURLString raw: String) -> String? {
        let text = raw.removingPercentEncoding ?? raw
        for pattern in [#"[?&](?:q|query)=([^&]+)"#, #"/place/([^/@?]+)"#] {
            if let m = firstMatch(pattern, in: text), let name = m.first {
                let cleaned = name.replacingOccurrences(of: "+", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty, plainCoordinate(cleaned) == nil { return cleaned }
            }
        }
        return nil
    }

    // MARK: - Network (short links)

    struct Resolved {
        var coordinate: Coordinate?
        var placeName: String?
    }

    /// Follows the short link's redirects, then reads the coordinate from the final
    /// URL, or from the page if the URL has none. Returns a place name when only
    /// that could be found so the caller can search for it.
    static func resolve(_ url: URL) async throws -> Resolved {
        var request = URLRequest(url: url, timeoutInterval: 15)
        // A mobile Safari UA gets the lightweight page with the place embedded.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        request.setValue("zh-TW,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        let finalURL = response.url?.absoluteString ?? url.absoluteString
        if let c = coordinate(fromURLString: finalURL) {
            return Resolved(coordinate: c, placeName: placeName(fromURLString: finalURL))
        }
        let body = String(decoding: data.prefix(1_500_000), as: UTF8.self)
        return Resolved(coordinate: coordinate(fromPageBody: body),
                        placeName: placeName(fromURLString: finalURL))
    }

    // MARK: - Helpers

    private static func validated(_ latText: String, _ lonText: String) -> Coordinate? {
        guard let lat = Double(latText), let lon = Double(lonText),
              (-90...90).contains(lat), (-180...180).contains(lon),
              !(lat == 0 && lon == 0) else { return nil }
        return Coordinate(latitude: lat, longitude: lon)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (1..<match.numberOfRanges).compactMap { i in
            Range(match.range(at: i), in: text).map { String(text[$0]) }
        }
    }
}
