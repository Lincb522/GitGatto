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
        guard sample.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 12 else {
            return nil
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        let language = recognizer.dominantLanguage
        let confidence = language.map {
            recognizer.languageHypotheses(withMaximum: 1)[$0, default: 0]
        } ?? 0

        if confidence >= 0.35, language == preferredTarget.naturalLanguage {
            return nil
        }
        return preferredTarget
    }

    private static func readableText(fromHTML html: String) -> String {
        html
            .replacingOccurrences(
                of: #"(?is)<(script|style|pre|code|svg)\b[^>]*>.*?</\1\s*>"#,
                with: " ",
                options: .regularExpression
            )
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
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(normalized.prefix(8_000))
    }

}
