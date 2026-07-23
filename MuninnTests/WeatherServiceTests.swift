import XCTest
@testable import Muninn

final class WeatherServiceTests: XCTestCase {

    private func data(_ s: String) -> Data { s.data(using: .utf8)! }

    func testParseGeocode() {
        let json = """
        {"results":[{"id":6077243,"name":"Montréal","latitude":45.50884,"longitude":-73.58781,"country":"Canada"}]}
        """
        let g = WeatherService.parseGeocode(data(json))
        XCTAssertEqual(g?.name, "Montréal")
        XCTAssertEqual(g?.lat ?? 0, 45.50884, accuracy: 0.0001)
        XCTAssertEqual(g?.lon ?? 0, -73.58781, accuracy: 0.0001)
    }

    func testParseGeocodeEmpty() {
        XCTAssertNil(WeatherService.parseGeocode(data(#"{"generationtime_ms":0.1}"#)))
        XCTAssertNil(WeatherService.parseGeocode(data(#"{"results":[]}"#)))
    }

    func testParseWeather() {
        let json = #"{"current":{"time":"2026-07-23T14:00","temperature_2m":21.6,"relative_humidity_2m":58.4}}"#
        let w = WeatherService.parseWeather(data(json))
        XCTAssertEqual(w?.0 ?? 0, 21.6, accuracy: 0.001)
        XCTAssertEqual(w?.1, 58)   // rounded
    }

    func testParseAQI() {
        XCTAssertEqual(WeatherService.parseAQI(data(#"{"current":{"us_aqi":41.0}}"#)), 41)
        XCTAssertNil(WeatherService.parseAQI(data(#"{"current":{"us_aqi":null}}"#)))
        XCTAssertNil(WeatherService.parseAQI(data(#"{"current":{}}"#)))
    }

    func testAQIColorBands() {
        XCTAssertEqual(StatusBarView.aqiColor(25), .systemGreen)
        XCTAssertEqual(StatusBarView.aqiColor(75), .systemYellow)
        XCTAssertEqual(StatusBarView.aqiColor(120), .systemOrange)
        XCTAssertEqual(StatusBarView.aqiColor(175), .systemRed)
        XCTAssertEqual(StatusBarView.aqiColor(250), .systemPurple)
        XCTAssertEqual(StatusBarView.aqiColor(400), .systemBrown)
    }
}
