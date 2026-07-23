import Foundation

/// Current-conditions snapshot for the status bar.
struct WeatherSnapshot: Equatable {
    let city: String
    let tempC: Double
    let humidity: Int   // %
    let aqi: Int?       // US AQI (nil if unavailable)
}

/// Fetches current weather + air quality from **Open-Meteo** — free, no API key, no account, fetched
/// natively over `URLSession` (privacy-aligned). Geocodes the city name to coordinates (cached per city),
/// then pulls temperature/humidity and US AQI. Parsing is pure + unit-tested.
@MainActor
final class WeatherService {
    private let session: URLSession
    private var cachedCity = ""
    private var cachedCoord: (lat: Double, lon: Double)?

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)
    }

    /// Resolve `city` and fetch its current conditions, or nil on failure.
    func fetch(city: String) async -> WeatherSnapshot? {
        let name = city.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        let coord: (lat: Double, lon: Double)
        let resolvedName: String
        if cachedCity.caseInsensitiveCompare(name) == .orderedSame, let c = cachedCoord {
            coord = c; resolvedName = name
        } else {
            guard let geo = await geocode(name) else { return nil }
            coord = (geo.lat, geo.lon); resolvedName = geo.name
            cachedCity = name; cachedCoord = coord
        }
        async let weatherData = weather(coord)
        async let aqiData = aqi(coord)
        guard let (t, h) = await weatherData else { return nil }
        return WeatherSnapshot(city: resolvedName, tempC: t, humidity: h, aqi: await aqiData)
    }

    private func get(_ url: URL) async -> Data? {
        do {
            let (d, r) = try await session.data(from: url)
            guard (r as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return d
        } catch { return nil }
    }

    private func geocode(_ name: String) async -> (lat: Double, lon: Double, name: String)? {
        guard let enc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(enc)&count=1&language=en&format=json"),
              let data = await get(url) else { return nil }
        return Self.parseGeocode(data)
    }
    private func weather(_ c: (lat: Double, lon: Double)) async -> (Double, Int)? {
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(c.lat)&longitude=\(c.lon)&current=temperature_2m,relative_humidity_2m"),
              let data = await get(url) else { return nil }
        return Self.parseWeather(data)
    }
    private func aqi(_ c: (lat: Double, lon: Double)) async -> Int? {
        guard let url = URL(string: "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=\(c.lat)&longitude=\(c.lon)&current=us_aqi"),
              let data = await get(url) else { return nil }
        return Self.parseAQI(data)
    }

    // MARK: pure parsing (unit-tested)

    nonisolated static func parseGeocode(_ data: Data) -> (lat: Double, lon: Double, name: String)? {
        struct R: Decodable { let results: [Item]?; struct Item: Decodable { let latitude: Double; let longitude: Double; let name: String } }
        guard let r = try? JSONDecoder().decode(R.self, from: data), let f = r.results?.first else { return nil }
        return (f.latitude, f.longitude, f.name)
    }
    nonisolated static func parseWeather(_ data: Data) -> (Double, Int)? {
        struct R: Decodable { let current: C; struct C: Decodable { let temperature_2m: Double; let relative_humidity_2m: Double } }
        guard let r = try? JSONDecoder().decode(R.self, from: data) else { return nil }
        return (r.current.temperature_2m, Int(r.current.relative_humidity_2m.rounded()))
    }
    nonisolated static func parseAQI(_ data: Data) -> Int? {
        struct R: Decodable { let current: C?; struct C: Decodable { let us_aqi: Double? } }
        guard let r = try? JSONDecoder().decode(R.self, from: data), let v = r.current?.us_aqi else { return nil }
        return Int(v.rounded())
    }
}
