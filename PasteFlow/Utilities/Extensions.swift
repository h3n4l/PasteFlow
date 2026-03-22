import SwiftUI

extension Date {
    func relativeString() -> String {
        let interval = Date().timeIntervalSince(self)
        if interval < 60 { return "just now" }
        else if interval < 3600 { return "\(Int(interval / 60))m ago" }
        else if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        else if interval < 7 * 86400 { return "\(Int(interval / 86400))d ago" }
        else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: self)
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

// Semantic colors are defined in Assets.xcassets/Colors/ and accessed via
// Xcode-generated ColorResource symbols, e.g. Color(.backgroundPrimary).
// No manual Color extension needed.
