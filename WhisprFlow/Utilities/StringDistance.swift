import Foundation

/// Jaro-Winkler string similarity (0.0 to 1.0)
enum StringDistance {

    static func jaroWinklerSimilarity(_ s1: String, _ s2: String) -> Double {
        let jaro = jaroSimilarity(s1, s2)
        guard jaro > 0 else { return 0 }

        // Winkler prefix boost (up to 4 chars, weight 0.1)
        let chars1 = Array(s1)
        let chars2 = Array(s2)
        let prefixLen = min(4, min(chars1.count, chars2.count))
        var commonPrefix = 0
        for i in 0..<prefixLen {
            if chars1[i] == chars2[i] { commonPrefix += 1 }
            else { break }
        }

        return jaro + Double(commonPrefix) * 0.1 * (1.0 - jaro)
    }

    private static func jaroSimilarity(_ s1: String, _ s2: String) -> Double {
        let chars1 = Array(s1)
        let chars2 = Array(s2)

        if chars1.isEmpty && chars2.isEmpty { return 1.0 }
        if chars1.isEmpty || chars2.isEmpty { return 0.0 }
        if chars1 == chars2 { return 1.0 }

        let matchWindow = max(chars1.count, chars2.count) / 2 - 1
        guard matchWindow >= 0 else { return 0.0 }

        var s1Matches = [Bool](repeating: false, count: chars1.count)
        var s2Matches = [Bool](repeating: false, count: chars2.count)

        var matches: Double = 0
        var transpositions: Double = 0

        for i in 0..<chars1.count {
            let start = max(0, i - matchWindow)
            let end = min(chars2.count - 1, i + matchWindow)
            guard start <= end else { continue }

            for j in start...end {
                if s2Matches[j] || chars1[i] != chars2[j] { continue }
                s1Matches[i] = true
                s2Matches[j] = true
                matches += 1
                break
            }
        }

        guard matches > 0 else { return 0.0 }

        var k = 0
        for i in 0..<chars1.count {
            guard s1Matches[i] else { continue }
            while !s2Matches[k] { k += 1 }
            if chars1[i] != chars2[k] { transpositions += 1 }
            k += 1
        }

        let m = matches
        let t = transpositions / 2.0
        return (m / Double(chars1.count) + m / Double(chars2.count) + (m - t) / m) / 3.0
    }
}
