import Foundation

enum ContentType: String, Codable, CaseIterable {
    case text
    case code
    case link
    case image
    case file
}
