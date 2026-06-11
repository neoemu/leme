import Foundation

extension String {
    /// Parses Kubernetes CPU resource quantity strings.
    /// Examples: "250m" → 0.25 cores, "1" → 1.0, "1500m" → 1.5, "2.5" → 2.5
    func parseKubernetesCPU() -> Double {
        let trimmed = trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("m") {
            let value = String(trimmed.dropLast())
            return (Double(value) ?? 0) / 1000.0
        }
        if trimmed.hasSuffix("n") {
            let value = String(trimmed.dropLast())
            return (Double(value) ?? 0) / 1_000_000_000.0
        }
        return Double(trimmed) ?? 0
    }

    /// Parses Kubernetes memory resource quantity strings to bytes.
    /// Examples: "1Ki" → 1024, "1Mi" → 1048576, "1Gi" → 1073741824, "1Ti" → 1099511627776
    /// Also handles: "1K" → 1000, "1M" → 1000000, "1G" → 1000000000
    /// Plain numbers are treated as bytes.
    func parseKubernetesMemory() -> Double {
        let trimmed = trimmingCharacters(in: .whitespaces)

        // Binary suffixes (Ki, Mi, Gi, Ti, Pi, Ei)
        if trimmed.hasSuffix("Ki") {
            let value = String(trimmed.dropLast(2))
            return (Double(value) ?? 0) * 1024
        }
        if trimmed.hasSuffix("Mi") {
            let value = String(trimmed.dropLast(2))
            return (Double(value) ?? 0) * 1024 * 1024
        }
        if trimmed.hasSuffix("Gi") {
            let value = String(trimmed.dropLast(2))
            return (Double(value) ?? 0) * 1024 * 1024 * 1024
        }
        if trimmed.hasSuffix("Ti") {
            let value = String(trimmed.dropLast(2))
            return (Double(value) ?? 0) * 1024 * 1024 * 1024 * 1024
        }
        if trimmed.hasSuffix("Pi") {
            let value = String(trimmed.dropLast(2))
            return (Double(value) ?? 0) * 1024 * 1024 * 1024 * 1024 * 1024
        }
        if trimmed.hasSuffix("Ei") {
            let value = String(trimmed.dropLast(2))
            return (Double(value) ?? 0) * 1024 * 1024 * 1024 * 1024 * 1024 * 1024
        }

        // Decimal suffixes (K, M, G, T, P, E) — note: not the same as binary
        let decimalSuffixes: [(String, Double)] = [
            ("E", 1e18), ("P", 1e15), ("T", 1e12),
            ("G", 1e9), ("M", 1e6), ("K", 1e3),
        ]
        for (suffix, multiplier) in decimalSuffixes {
            if trimmed.hasSuffix(suffix) && !trimmed.hasSuffix("\(suffix)i") {
                let value = String(trimmed.dropLast(suffix.count))
                return (Double(value) ?? 0) * multiplier
            }
        }

        // Exponent notation (e.g., "1e3" = 1000)
        if trimmed.contains("e") || trimmed.contains("E") {
            return Double(trimmed) ?? 0
        }

        // Plain number = bytes
        return Double(trimmed) ?? 0
    }

    /// Convenience: parse memory and return in GiB.
    func parseKubernetesMemoryGiB() -> Double {
        parseKubernetesMemory() / (1024 * 1024 * 1024)
    }
}
