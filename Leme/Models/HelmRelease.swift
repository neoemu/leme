import Foundation

struct HelmRelease: Identifiable, Sendable, Hashable {
    let name: String
    let namespace: String
    let revision: Int
    let updated: Date?
    let status: String
    let chart: String
    let appVersion: String

    var id: String { "\(namespace)/\(name)" }

    /// Helm reports lowercase statuses ("deployed", "pending-upgrade");
    /// capitalize the first letter for display while keeping the raw token
    /// recognizable by `Theme.Colors.forStatus`.
    var displayStatus: String {
        guard let first = status.first else { return "Unknown" }
        return first.uppercased() + status.dropFirst()
    }
}

struct HelmReleaseRevision: Identifiable, Sendable, Hashable {
    let revision: Int
    let updated: Date?
    let status: String
    let chart: String
    let appVersion: String
    let description: String

    var id: Int { revision }

    var displayStatus: String {
        guard let first = status.first else { return "Unknown" }
        return first.uppercased() + status.dropFirst()
    }
}

/// Parses the timestamps helm prints, which come in two shapes:
/// - Go's `time.String()` form: "2026-05-09 14:21:11.123456 -0300 -03"
/// - RFC 3339 with up to nanosecond precision: "2026-05-09T14:21:11.123456789-03:00"
enum HelmTimestampParser {
    static func parse(_ raw: String) -> Date? {
        var value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }

        // RFC 3339 never contains spaces; Go's time.String() always does
        // (and may end in a zone abbreviation like "UTC", so don't probe for "T").
        if value.contains(" ") {
            // Go form: keep date, time and numeric offset; drop the zone abbreviation.
            let tokens = value.split(separator: " ")
            guard tokens.count >= 2 else { return nil }
            let offset = tokens.count >= 3 ? String(tokens[2]) : "Z"
            value = "\(tokens[0])T\(tokens[1])\(colonSeparatedOffset(offset))"
        } else if !value.contains("T") {
            return nil
        }

        // ISO8601DateFormatter only understands millisecond fractions.
        value = truncateFraction(value, toDigits: 3)

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    private static func colonSeparatedOffset(_ offset: String) -> String {
        if offset == "Z" || offset.contains(":") { return offset }
        guard offset.count == 5, offset.hasPrefix("+") || offset.hasPrefix("-") else { return offset }
        let hours = offset.prefix(3)
        let minutes = offset.suffix(2)
        return "\(hours):\(minutes)"
    }

    private static func truncateFraction(_ value: String, toDigits digits: Int) -> String {
        guard let dotIndex = value.firstIndex(of: ".") else { return value }
        let fractionStart = value.index(after: dotIndex)
        var fractionEnd = fractionStart
        while fractionEnd < value.endIndex, value[fractionEnd].isNumber {
            fractionEnd = value.index(after: fractionEnd)
        }
        let fraction = value[fractionStart..<fractionEnd].prefix(digits)
        let prefix = value[value.startIndex..<dotIndex]
        let suffix = value[fractionEnd...]
        guard !fraction.isEmpty else { return String(prefix) + String(suffix) }
        return "\(prefix).\(fraction)\(suffix)"
    }
}
