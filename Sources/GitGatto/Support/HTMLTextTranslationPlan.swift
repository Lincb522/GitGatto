import Foundation

struct HTMLTextTranslationPlan {
    struct Segment: Equatable {
        let range: NSRange
        let text: String
    }

    let html: String
    let segments: [Segment]

    init(html: String) {
        self.html = html
        let source = html as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let protectedRanges = Self.matches(
            pattern: #"<(pre|code|kbd|samp|script|style|svg|math)\b[^>]*>.*?</\1\s*>"#,
            in: html
        )
        let tagRanges = Self.matches(pattern: #"<!--[\s\S]*?-->|<![^>]*>|<[^>]+>"#, in: html)

        var candidates: [Segment] = []
        var cursor = 0
        for tagRange in tagRanges {
            if tagRange.location > cursor {
                Self.appendSegments(
                    in: NSRange(location: cursor, length: tagRange.location - cursor),
                    source: source,
                    protectedRanges: protectedRanges,
                    to: &candidates
                )
            }
            cursor = max(cursor, NSMaxRange(tagRange))
        }
        if cursor < fullRange.length {
            Self.appendSegments(
                in: NSRange(location: cursor, length: fullRange.length - cursor),
                source: source,
                protectedRanges: protectedRanges,
                to: &candidates
            )
        }
        segments = candidates
    }

    var characterCount: Int {
        segments.reduce(0) { $0 + $1.text.count }
    }

    func batches(maxCharacterCount: Int) -> [[Int]] {
        guard maxCharacterCount > 0 else { return [] }
        var result: [[Int]] = []
        var current: [Int] = []
        var currentCount = 0

        for index in segments.indices {
            let count = segments[index].text.count
            if !current.isEmpty, currentCount + count > maxCharacterCount {
                result.append(current)
                current = []
                currentCount = 0
            }
            current.append(index)
            currentCount += count
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    func restoring(_ translations: [String]) -> String? {
        guard translations.count == segments.count else { return nil }
        let result = NSMutableString(string: html)
        for index in segments.indices.reversed() {
            let segment = segments[index]
            let translation = translations[index]
            guard !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            result.replaceCharacters(in: segment.range, with: translation)
        }
        return result as String
    }

    private static func matches(pattern: String, in html: String) -> [NSRange] {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return expression.matches(in: html, range: range).map(\.range)
    }

    private static func appendSegments(
        in range: NSRange,
        source: NSString,
        protectedRanges: [NSRange],
        to segments: inout [Segment]
    ) {
        guard range.length > 0,
              !protectedRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) else {
            return
        }

        let raw = source.substring(with: range)
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              text.unicodeScalars.contains(where: CharacterSet.letters.contains) else {
            return
        }
        let localRange = (raw as NSString).range(of: text)
        guard localRange.location != NSNotFound else { return }
        appendSplitSegments(
            text: text,
            range: NSRange(
                location: range.location + localRange.location,
                length: localRange.length
            ),
            to: &segments
        )
    }

    private static func appendSplitSegments(
        text: String,
        range: NSRange,
        to segments: inout [Segment]
    ) {
        let maximumLength = 6_000
        guard text.count > maximumLength else {
            segments.append(Segment(range: range, text: text))
            return
        }

        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: maximumLength, limitedBy: text.endIndex) ?? text.endIndex
            let partRange = start..<end
            let utf16Range = NSRange(partRange, in: text)
            segments.append(
                Segment(
                    range: NSRange(
                        location: range.location + utf16Range.location,
                        length: utf16Range.length
                    ),
                    text: String(text[partRange])
                )
            )
            start = end
        }
    }
}
