import Foundation

/// Session identifiers accepted by the runtime's `/live` endpoint: `[A-Za-z0-9._:-]{1,128}`.
/// The client must always generate and pass its own id; the server never reports the one it creates.
enum SessionID {
    private static let allowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-"
    )

    static func make() -> String {
        "ios-" + UUID().uuidString.lowercased()
    }

    static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else { return false }
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Short suffix for display in chips ("…3f9a2c1d").
    static func short(_ value: String, length: Int = 8) -> String {
        String(value.suffix(length))
    }
}
