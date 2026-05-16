import SwiftUI
import AppKit

// MARK: - MongoJSONEditor
//
// SwiftUI wrapper around NSTextView that provides:
//  * monospaced text editing
//  * "Leaf & Midnight" dark code surface (Theme.codeBg)
//  * line-number gutter (Theme.textOnDarkMuted)
//  * lightweight JSON syntax highlighting:
//      - strings  → Theme.codeString  (#69ff87)
//      - keywords → Theme.codeKeyword (#84d7b2) — true/false/null
//      - numbers  → Theme.warning subdued
//      - braces / punctuation → Theme.textOnDarkMuted
//  * automatic completion of MongoDB aggregation operators when the user types `$`
//
// The completion catalog is defined in `MongoOperatorCatalog` below. Completion is
// triggered automatically via `complete(_:)` whenever the token immediately preceding
// the cursor starts with `$` and has at least one character after the dollar sign.
//

struct MongoJSONEditor: NSViewRepresentable {
    @Binding var text: String
    var isValid: Bool = true
    var isDisabled: Bool = false

    // MARK: Color constants — mirrored from Theme tokens (NSColor side).

    private static let codeBgNS = NSColor(red: 0.0, green: 0.118, blue: 0.169, alpha: 1.0)        // Theme.codeBg
    private static let accentNS = NSColor(red: 0.0, green: 0.929, blue: 0.392, alpha: 1.0)        // Theme.accent
    private static let textOnDark = NSColor.white                                                  // Theme.textOnDark
    private static let textOnDarkMuted = NSColor.white.withAlphaComponent(0.62)                    // Theme.textOnDarkMuted
    private static let codeString = NSColor(red: 0.412, green: 1.0, blue: 0.529, alpha: 1.0)      // Theme.codeString
    private static let codeKeyword = NSColor(red: 0.518, green: 0.843, blue: 0.698, alpha: 1.0)   // Theme.codeKeyword
    private static let codeNumber = NSColor(red: 0.961, green: 0.651, blue: 0.137, alpha: 0.92)   // Theme.warning (subdued)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.drawsBackground = true
        textView.backgroundColor = Self.codeBgNS
        textView.textColor = Self.textOnDark
        textView.insertionPointColor = Self.accentNS
        textView.selectedTextAttributes = [
            .backgroundColor: Self.accentNS.withAlphaComponent(0.25)
        ]

        scrollView.drawsBackground = true
        scrollView.backgroundColor = Self.codeBgNS
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        // Line-number gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler

        textView.string = text
        Self.applySyntaxHighlight(textView: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let cursorLocation = textView.selectedRange().location
            textView.string = text
            // Restore cursor as best we can.
            let clamped = min(cursorLocation, text.utf16.count)
            textView.setSelectedRange(NSRange(location: clamped, length: 0))
        }
        textView.isEditable = !isDisabled
        textView.textColor = isDisabled
            ? Self.textOnDark.withAlphaComponent(0.5)
            : Self.textOnDark
        Self.applySyntaxHighlight(textView: textView)
        (scrollView.verticalRulerView as? LineNumberRulerView)?.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, applyHighlight: { textView in
            Self.applySyntaxHighlight(textView: textView)
        })
    }

    // MARK: - Syntax Highlighting

    fileprivate static func applySyntaxHighlight(textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let fullText = textView.string as NSString
        let fullRange = NSRange(location: 0, length: fullText.length)
        guard fullRange.length > 0 else { return }

        let baseFont = textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        storage.beginEditing()
        // Reset to default punctuation muted color.
        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: textOnDarkMuted
        ], range: fullRange)

        // Strings — including keys (the JSON parser doesn't distinguish, both look the same).
        let stringPattern = "\"(?:\\\\.|[^\"\\\\])*\""
        if let regex = try? NSRegularExpression(pattern: stringPattern, options: []) {
            regex.enumerateMatches(in: textView.string, options: [], range: fullRange) { match, _, _ in
                guard let r = match?.range else { return }
                storage.addAttribute(.foregroundColor, value: codeString, range: r)
            }
        }

        // Numbers (integers, decimals, scientific).
        let numberPattern = "(?<![\\w.])-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?(?![\\w.])"
        if let regex = try? NSRegularExpression(pattern: numberPattern, options: []) {
            regex.enumerateMatches(in: textView.string, options: [], range: fullRange) { match, _, _ in
                guard let r = match?.range else { return }
                // Skip if inside a string — the string pass already owns these ranges.
                let attrs = storage.attributes(at: r.location, effectiveRange: nil)
                if let color = attrs[.foregroundColor] as? NSColor, color == codeString { return }
                storage.addAttribute(.foregroundColor, value: codeNumber, range: r)
            }
        }

        // Keywords / literals: true / false / null.
        let keywordPattern = "\\b(?:true|false|null)\\b"
        if let regex = try? NSRegularExpression(pattern: keywordPattern, options: []) {
            regex.enumerateMatches(in: textView.string, options: [], range: fullRange) { match, _, _ in
                guard let r = match?.range else { return }
                let attrs = storage.attributes(at: r.location, effectiveRange: nil)
                if let color = attrs[.foregroundColor] as? NSColor, color == codeString { return }
                storage.addAttribute(.foregroundColor, value: codeKeyword, range: r)
            }
        }

        storage.endEditing()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let applyHighlight: (NSTextView) -> Void
        /// Guards against re-entrant auto-completion while inserting the completion itself.
        private var isCompleting = false

        init(text: Binding<String>, applyHighlight: @escaping (NSTextView) -> Void) {
            self._text = text
            self.applyHighlight = applyHighlight
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if text != textView.string {
                text = textView.string
            }
            applyHighlight(textView)
            if let scrollView = textView.enclosingScrollView,
               let ruler = scrollView.verticalRulerView as? LineNumberRulerView {
                ruler.needsDisplay = true
            }
            guard !isCompleting else { return }
            maybeTriggerCompletion(textView: textView)
        }

        /// Automatically show the completion popup when the user has just typed
        /// inside a token that starts with `$`.
        private func maybeTriggerCompletion(textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            guard selectedRange.length == 0, selectedRange.location > 0 else { return }
            let partial = currentDollarToken(textView: textView, cursor: selectedRange.location)
            guard let token = partial, token.count >= 2 else { return }  // e.g. "$m"
            // Schedule on main so we don't recurse into text storage notifications.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isCompleting = true
                textView.complete(nil)
                self.isCompleting = false
            }
        }

        // MARK: Completion API

        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            guard let nsString = textView.string as NSString? else { return [] }
            let partial = nsString.substring(with: charRange)
            // Only complete tokens that start with `$`.
            guard partial.hasPrefix("$") else { return [] }
            let lowerPartial = partial.lowercased()
            let matches = MongoOperatorCatalog.all
                .filter { $0.lowercased().hasPrefix(lowerPartial) }
                .sorted { lhs, rhs in
                    // Exact-match rank first, then shorter operators (more likely).
                    if lhs.count != rhs.count { return lhs.count < rhs.count }
                    return lhs < rhs
                }
            if matches.isEmpty { return [] }
            index?.pointee = 0
            return matches
        }

        /// Compute the range of the `$`-prefixed token ending at `cursor`.
        func textView(
            _ textView: NSTextView,
            rangeForUserCompletion charRange: NSRange
        ) -> NSRange {
            let nsString = textView.string as NSString
            // Walk back from cursor to the most recent `$` character while we're
            // still looking at identifier chars.
            var start = charRange.location
            while start > 0 {
                let prev = start - 1
                let ch = nsString.character(at: prev)
                guard let scalar = Unicode.Scalar(ch) else { break }
                let char = Character(scalar)
                if char == "$" {
                    start = prev
                    break
                }
                if !char.isLetter && !char.isNumber && char != "_" {
                    break
                }
                start = prev
            }
            let length = charRange.location + charRange.length - start
            return NSRange(location: start, length: length)
        }

        private func currentDollarToken(textView: NSTextView, cursor: Int) -> String? {
            let nsString = textView.string as NSString
            var start = cursor
            while start > 0 {
                let prev = start - 1
                let ch = nsString.character(at: prev)
                guard let scalar = Unicode.Scalar(ch) else { break }
                let char = Character(scalar)
                if char == "$" {
                    start = prev
                    let range = NSRange(location: start, length: cursor - start)
                    return nsString.substring(with: range)
                }
                if !char.isLetter && !char.isNumber && char != "_" {
                    return nil
                }
                start = prev
            }
            return nil
        }
    }
}

// MARK: - Line Number Ruler

/// Lightweight gutter that draws line numbers in the muted on-dark token.
final class LineNumberRulerView: NSRulerView {
    private weak var hostTextView: NSTextView?

    private static let gutterBg = NSColor(red: 0.0, green: 0.118, blue: 0.169, alpha: 1.0)      // Theme.codeBg
    private static let gutterFg = NSColor.white.withAlphaComponent(0.45)                         // muted on-dark

    init(textView: NSTextView) {
        self.hostTextView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 36
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        // Background fill.
        Self.gutterBg.setFill()
        rect.fill()

        guard
            let textView = hostTextView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else { return }

        let nsString = textView.string as NSString
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Find line number for the first visible character.
        var lineNumber = 1
        let preceding = NSRange(location: 0, length: charRange.location)
        nsString.enumerateSubstrings(in: preceding, options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            lineNumber += 1
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: Self.gutterFg
        ]

        // Walk visible lines and draw their numbers.
        var index = charRange.location
        let end = NSMaxRange(charRange)
        while index < end || (index == 0 && nsString.length == 0) {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            let glyphIdx = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
            let yInRuler = lineRect.minY - visibleRect.minY + textView.textContainerInset.height

            let label = "\(lineNumber)" as NSString
            let labelSize = label.size(withAttributes: attrs)
            let drawRect = NSRect(
                x: ruleThickness - labelSize.width - 8,
                y: yInRuler + (lineRect.height - labelSize.height) / 2,
                width: labelSize.width,
                height: labelSize.height
            )
            label.draw(in: drawRect, withAttributes: attrs)

            lineNumber += 1
            if lineRange.length == 0 { break }
            index = NSMaxRange(lineRange)
            if nsString.length == 0 { break }
        }
    }
}

// MARK: - Operator Catalog

enum MongoOperatorCatalog {

    /// Curated list of MongoDB aggregation pipeline stage operators + expression operators.
    /// Used by the autocomplete engine when the user types a `$`-prefixed token.
    static let all: [String] = stageOperators + expressionOperators + variables

    /// Pipeline stage operators (also used in the stage type picker).
    static let stageOperators: [String] = [
        "$addFields", "$bucket", "$bucketAuto", "$collStats", "$count", "$densify",
        "$facet", "$fill", "$geoNear", "$graphLookup", "$group", "$indexStats",
        "$limit", "$lookup", "$match", "$merge", "$out", "$project", "$redact",
        "$replaceRoot", "$replaceWith", "$sample", "$search", "$set", "$setWindowFields",
        "$skip", "$sort", "$sortByCount", "$unionWith", "$unset", "$unwind",
        "$vectorSearch"
    ]

    /// Expression operators used inside stage bodies.
    static let expressionOperators: [String] = [
        // Arithmetic
        "$abs", "$add", "$ceil", "$divide", "$exp", "$floor", "$ln", "$log", "$log10",
        "$mod", "$multiply", "$pow", "$round", "$sqrt", "$subtract", "$trunc",
        // Array
        "$arrayElemAt", "$arrayToObject", "$concatArrays", "$filter", "$first", "$in",
        "$indexOfArray", "$isArray", "$last", "$map", "$objectToArray", "$range",
        "$reduce", "$reverseArray", "$size", "$slice", "$zip",
        // Boolean / Comparison
        "$and", "$not", "$or", "$cmp", "$eq", "$gt", "$gte", "$lt", "$lte", "$ne",
        // Conditional
        "$cond", "$ifNull", "$switch",
        // Date
        "$dateAdd", "$dateDiff", "$dateFromParts", "$dateFromString", "$dateSubtract",
        "$dateToParts", "$dateToString", "$dateTrunc", "$dayOfMonth", "$dayOfWeek",
        "$dayOfYear", "$hour", "$isoDayOfWeek", "$isoWeek", "$isoWeekYear",
        "$millisecond", "$minute", "$month", "$second", "$toDate", "$week", "$year",
        // String
        "$concat", "$indexOfBytes", "$indexOfCP", "$ltrim", "$regexFind", "$regexFindAll",
        "$regexMatch", "$replaceAll", "$replaceOne", "$rtrim", "$split", "$strLenBytes",
        "$strLenCP", "$strcasecmp", "$substr", "$substrBytes", "$substrCP", "$toLower",
        "$toString", "$toUpper", "$trim",
        // Type
        "$convert", "$isNumber", "$toBool", "$toDecimal", "$toDouble", "$toInt",
        "$toLong", "$toObjectId", "$type",
        // Accumulator / group
        "$addToSet", "$avg", "$bottom", "$bottomN", "$count", "$firstN", "$lastN",
        "$max", "$maxN", "$mergeObjects", "$min", "$push", "$stdDevPop", "$stdDevSamp",
        "$sum", "$top", "$topN",
        // Set
        "$allElementsTrue", "$anyElementTrue", "$setDifference", "$setEquals",
        "$setIntersection", "$setIsSubset", "$setUnion",
        // Window (for $setWindowFields)
        "$denseRank", "$derivative", "$documentNumber", "$expMovingAvg", "$integral",
        "$rank", "$shift",
        // Text / search
        "$meta",
        // Literal
        "$literal"
    ]

    /// Aggregation system variables — commonly typed after `$$`.
    static let variables: [String] = [
        "$$ROOT", "$$CURRENT", "$$REMOVE", "$$DESCEND", "$$PRUNE", "$$KEEP", "$$NOW",
        "$$CLUSTER_TIME"
    ]
}
