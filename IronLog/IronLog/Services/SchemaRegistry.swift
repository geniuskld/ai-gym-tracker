import Foundation

enum SchemaRegistry {
    static let supported: [String: Set<String>] = [
        "strength": ["1.0"],
    ]

    static func isSupported(type: String, version: String) -> Bool {
        supported[type]?.contains(version) ?? false
    }
}
