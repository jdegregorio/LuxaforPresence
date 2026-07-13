import Foundation

/// An exact 24-bit color sent to the Luxafor solid-color endpoint.
struct LuxaforColor: Equatable, Hashable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    static let off = LuxaforColor(red: 0, green: 0, blue: 0)
    static let red = LuxaforColor(red: 255, green: 0, blue: 0)
    static let yellow = LuxaforColor(red: 255, green: 255, blue: 0)

    var hex: String {
        String(format: "%02X%02X%02X", red, green, blue)
    }

    var localHex: String {
        "#\(hex)"
    }
}
