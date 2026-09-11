import Foundation
import NaturalLanguage

enum AutomaticTranslationPolicy {
    static func target(
        forHTML html: String,
        preferredTarget: CodexTranslationTarget
    ) -> CodexTranslationTarget? {
        target(for: readableText(fromHTML: html), preferredTarget: preferredTarget)
    }

    static func target(
        for text: String,
        preferredTarget: CodexTranslationTarget
    ) -> CodexTranslationTarget? {
        let sample = normalizedSample(text)
        // Inspect paragraphs independently so target-language headings do not hide foreign prose.
        let passages = sample.components(separatedBy: .newlines).filter { !$0.isEmpty }
        for passage in passages {
            let letters = passage.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            let words = passage.split(whereSeparator: \.isWhitespace)
            let hasNonLatin = passage.unicodeScalars.contains { $0.value > 0x2FF && CharacterSet.letters.contains($0) }
            guard letters >= 4, hasNonLatin || words.count >= 2 else { continue }
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(passage)
            if recognizer.dominantLanguage != preferredTarget.naturalLanguage { return preferredTarget }
        }
        return nil
    }

    private static func readableText(fromHTML html: String) -> String {
        html
            .replacingOccurrences(
                of: #"(?is)<(script|style|pre|code|svg)\b[^>]*>.*?</\1\s*>"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"(?i)</(?:p|div|h[1-6]|li|section)>|<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"&(?:#\d+|#x[0-9a-fA-F]+|[A-Za-z]+);"#, with: " ", options: .regularExpression)
    }

    private static func normalizedSample(_ text: String) -> String {
        let withoutFencedCode = text.replacingOccurrences(
            of: #"(?s)```.*?```"#,
            with: " ",
            options: .regularExpression
        )
        let normalized = withoutFencedCode
            .replacingOccurrences(of: #"`[^`]*`|https?://[^\s]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^\S\n]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(normalized.prefix(8_000))
    }

}
