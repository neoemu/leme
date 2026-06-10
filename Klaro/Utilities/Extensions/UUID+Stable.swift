import CryptoKit
import Foundation

extension UUID {
    /// Derives a deterministic UUID from a string (name-based, SHA-256 truncated),
    /// so the same input always produces the same UUID across app launches.
    init(stableFrom string: String) {
        let digest = SHA256.hash(data: Data(string.utf8))
        var bytes = Array(digest.prefix(16))
        // Set version (5-style name-based) and RFC 4122 variant bits
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        self = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
