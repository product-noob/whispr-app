import Foundation

/// Post-processing pipeline for transcription text.
/// Order: Voice Commands → Punctuation Cleanup → Filler Removal → Word Dedup → Capitalization → Personal Dictionary → Context Adjustments
struct TextPostProcessor {

    // MARK: - App Context

    enum AppCategory {
        case terminal
        case messaging
        case general
    }

    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.microsoft.VSCode",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.jetbrains.intellij",
        "com.jetbrains.pycharm",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "com.panic.Nova",
        "com.github.atom",
        "com.todesktop.230313mzl4w4u92",  // Cursor
    ]

    private static let messagingBundleIDs: Set<String> = [
        "com.apple.MobileSMS",
        "com.tinyspeck.slackmacgap",
        "ru.keepcoder.Telegram",
        "net.whatsapp.WhatsApp",
        "com.hnc.Discord",
        "com.facebook.archon",  // Messenger
        "com.apple.iChat",
    ]

    static func appCategory(for bundleID: String?) -> AppCategory {
        guard let bundleID else { return .general }
        if terminalBundleIDs.contains(bundleID) { return .terminal }
        if messagingBundleIDs.contains(bundleID) { return .messaging }
        return .general
    }

    // MARK: - Non-English Filtering

    /// Returns true if the text appears to be non-English (Cyrillic, CJK, Arabic, etc.)
    /// Used to catch Parakeet hallucinations in other languages.
    static func appearsNonEnglish(_ text: String) -> Bool {
        let stripped = text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0) }
        guard !stripped.isEmpty else { return false }

        var nonLatinCount = 0
        for scalar in stripped {
            // Latin letters + digits + common symbols are fine
            if CharacterSet.alphanumerics.contains(scalar) {
                // Check if it's actually Latin — alphanumerics includes Cyrillic digits etc.
                let value = scalar.value
                let isBasicLatin = (value >= 0x0020 && value <= 0x007F)       // Basic Latin
                let isLatinSupplement = (value >= 0x00C0 && value <= 0x024F)  // Latin Extended
                if !isBasicLatin && !isLatinSupplement {
                    nonLatinCount += 1
                }
            }
        }

        let ratio = Double(nonLatinCount) / Double(stripped.count)
        return ratio > 0.3 // More than 30% non-Latin chars → likely not English
    }

    // MARK: - F1: Voice Commands

    private static let voiceCommands: [(phrases: [String], replacement: String)] = [
        // Multi-word commands first (longer matches take priority)
        (["new paragraph"], "\n\n"),
        (["new line"], "\n"),
        (["exclamation mark", "exclamation point"], "!"),
        (["question mark"], "?"),
        (["full stop"], "."),
        (["open parenthesis", "open paren"], "("),
        (["close parenthesis", "close paren"], ")"),
        (["semicolon"], ";"),
        (["open quote"], "\""),
        (["close quote"], "\""),
        (["period"], "."),
        (["comma"], ","),
        (["colon"], ":"),
        (["dash", "hyphen"], "-"),
    ]

    static func applyVoiceCommands(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        for command in voiceCommands {
            for phrase in command.phrases {
                // Build regex: whole-word match (case-insensitive)
                // Match when preceded by start-of-string or whitespace, followed by end-of-string or whitespace
                let escaped = NSRegularExpression.escapedPattern(for: phrase)
                guard let regex = try? NSRegularExpression(
                    pattern: "(?<=^|\\s)\(escaped)(?=\\s|$)",
                    options: .caseInsensitive
                ) else { continue }

                // Replace from end to start to preserve ranges
                let nsRange = NSRange(result.startIndex..., in: result)
                let matches = regex.matches(in: result, range: nsRange)

                for match in matches.reversed() {
                    guard let range = Range(match.range, in: result) else { continue }

                    let replacement = command.replacement
                    let isPunctuation = [".", ",", "?", "!", ":", ";", ")", "\"", "-"].contains(replacement)

                    if isPunctuation {
                        // Remove leading space before punctuation if present
                        var expandedStart = range.lowerBound
                        if expandedStart > result.startIndex {
                            let before = result.index(before: expandedStart)
                            if result[before] == " " {
                                expandedStart = before
                            }
                        }
                        result.replaceSubrange(expandedStart..<range.upperBound, with: replacement)
                    } else {
                        result.replaceSubrange(range, with: replacement)
                    }
                }
            }
        }

        return result
    }

    // MARK: - F4: Punctuation and Spacing Cleanup

    static func cleanupPunctuation(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        // Remove space before punctuation: . , ? ! : ; )
        result = result.replacingOccurrences(
            of: "\\s+([.,?!:;)])",
            with: "$1",
            options: .regularExpression
        )

        // Remove space after (
        result = result.replacingOccurrences(
            of: "\\(\\s+",
            with: "(",
            options: .regularExpression
        )

        // Add space after punctuation if followed by a letter (but not for abbreviations like "e.g.")
        result = result.replacingOccurrences(
            of: "([.,?!:;])([A-Za-z])",
            with: "$1 $2",
            options: .regularExpression
        )

        // Remove mixed consecutive punctuation (e.g. ".,") but keep repeated same chars ("..." stays)
        result = result.replacingOccurrences(
            of: "([.,?!:;])(?=[,?!:;])",
            with: "",
            options: .regularExpression
        )

        // Collapse multiple spaces
        result = result.replacingOccurrences(
            of: "\\s{2,}",
            with: " ",
            options: .regularExpression
        )

        // Trim
        result = result.trimmingCharacters(in: .whitespaces)

        return result
    }

    // MARK: - F2: Filler Word Removal (Expanded)

    private static let fillerPhrases: [String] = [
        // Multi-word phrases (remove first, longest first)
        "you know what i mean",
        "and things like that",
        "at the end of the day",
        "to be honest",
        "if you will",
        "or something",
        "or whatever",
        "and stuff",
        "you know,",
        "you know",
        "i mean,",
        "i mean",
        "i guess",
        "sort of",
        "kind of",
    ]

    private static let fillerWords: Set<String> = [
        "uh", "um", "uh,", "um,", "uhh", "umm",
        "er", "err", "ah", "ahh",
        "hmm", "hm", "mm", "mmm",
        "like,",
        "basically", "actually", "literally",
    ]

    // Words that are fillers ONLY at sentence boundaries
    private static let sentenceBoundaryFillers: Set<String> = [
        "right", "so", "well",
    ]

    static func removeFillers(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        // Phase 1: Remove multi-word filler phrases (case-insensitive)
        for phrase in fillerPhrases {
            let escaped = NSRegularExpression.escapedPattern(for: phrase)
            // Match whole phrase at word boundaries
            if let regex = try? NSRegularExpression(
                pattern: "\\b\(escaped)\\b,?\\s*",
                options: .caseInsensitive
            ) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // Phase 2: Remove single filler words
        let words = result.components(separatedBy: " ")
        let filtered = words.filter { !fillerWords.contains($0.lowercased()) }
        result = filtered.joined(separator: " ")

        // Phase 3: Remove sentence-boundary fillers ("right", "so", "well")
        // Only at start of text or after sentence-ending punctuation
        for word in sentenceBoundaryFillers {
            // At start of text: "So we need" → "We need"
            if let regex = try? NSRegularExpression(
                pattern: "^(?i)\(word)\\s+",
                options: []
            ) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
            // After sentence-ending punctuation: ". So we" → ". We"
            if let regex = try? NSRegularExpression(
                pattern: "([.?!])\\s+(?i)\(word)\\s+",
                options: []
            ) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: "$1 "
                )
            }
        }

        // Clean up: collapse multiple spaces, trim
        result = result.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespaces)

        return result
    }

    // MARK: - F9: Repeated/Stuttered Word Deduplication

    static func deduplicateWords(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        // Match a word followed by one or more repetitions of itself (case-insensitive)
        guard let regex = try? NSRegularExpression(
            pattern: "\\b(\\w+)(\\s+\\1)+\\b",
            options: .caseInsensitive
        ) else { return text }

        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: "$1"
        )
    }

    // MARK: - F3: Auto-Capitalization After Punctuation

    static func enforceCapitalization(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        // Capitalize first character
        if let first = result.first, first.isLowercase {
            result = result.prefix(1).uppercased() + result.dropFirst()
        }

        // Capitalize after sentence-ending punctuation followed by whitespace
        if let regex = try? NSRegularExpression(pattern: "([.?!])\\s+(\\w)", options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))

            // Replace from end to preserve ranges
            for match in matches.reversed() {
                let letterRange = match.range(at: 2)
                let letter = nsString.substring(with: letterRange)
                result = (result as NSString).replacingCharacters(in: letterRange, with: letter.uppercased())
            }
        }

        // Capitalize after newlines
        if let regex = try? NSRegularExpression(pattern: "\\n\\s*(\\w)", options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))

            for match in matches.reversed() {
                let letterRange = match.range(at: 1)
                let letter = nsString.substring(with: letterRange)
                result = (result as NSString).replacingCharacters(in: letterRange, with: letter.uppercased())
            }
        }

        return result
    }

    // MARK: - Personal Dictionary

    static func applyDictionary(_ text: String, entries: [DictionaryEntry]) -> String {
        guard !text.isEmpty, !entries.isEmpty else { return text }

        let words = text.components(separatedBy: " ")
        var resultWords: [String] = []

        for word in words {
            // Strip trailing punctuation for matching
            let punctuation = CharacterSet(charactersIn: ".,!?;:")
            let stripped = word.trimmingCharacters(in: punctuation)
            let trailing = String(word.dropFirst(stripped.count))
            let wordLower = stripped.lowercased()

            guard !wordLower.isEmpty else {
                resultWords.append(word)
                continue
            }

            var bestMatch: String?
            var bestScore: Double = 0

            for entry in entries {
                let targetLower = entry.word.lowercased()

                // Stage 1: Exact match
                if wordLower == targetLower {
                    bestMatch = entry.replacement
                    break
                }

                // Stage 2: Fuzzy match via Jaro-Winkler
                let score = StringDistance.jaroWinklerSimilarity(wordLower, targetLower)
                if score > 0.85 && score > bestScore {
                    bestScore = score
                    bestMatch = entry.replacement
                }
            }

            if let match = bestMatch {
                resultWords.append(match + trailing)
            } else {
                resultWords.append(word)
            }
        }

        return resultWords.joined(separator: " ")
    }

    // MARK: - F8: Context-Aware Adjustments

    static func applyContextAdjustments(_ text: String, category: AppCategory) -> String {
        guard !text.isEmpty else { return text }

        switch category {
        case .messaging:
            // In messaging apps, convert double newlines to single (prevent accidental sends)
            return text.replacingOccurrences(of: "\n\n", with: "\n")
        case .terminal, .general:
            return text
        }
    }

    // MARK: - Combined Pipeline

    static func process(_ text: String, config: AppConfig, activeAppBundleID: String? = nil) -> String {
        var result = text

        let category = appCategory(for: activeAppBundleID)

        // 1. Voice commands
        result = applyVoiceCommands(result)

        // 2. Punctuation cleanup
        result = cleanupPunctuation(result)

        // 3. Filler word removal
        if config.fillerWordRemoval {
            result = removeFillers(result)
        }

        // 4. Repeated word deduplication
        result = deduplicateWords(result)

        // 5. Auto-capitalization (skip for terminal/IDE)
        if category != .terminal {
            result = enforceCapitalization(result)
        }

        // 6. Personal dictionary
        result = applyDictionary(result, entries: config.personalDictionary)

        // 7. Context-aware adjustments
        result = applyContextAdjustments(result, category: category)

        return result
    }
}
