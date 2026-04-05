import SwiftUI
import AppKit

// MARK: - MongoJSONEditor
//
// SwiftUI wrapper around NSTextView that provides:
//  * monospaced text editing
//  * dark theme matching app palette
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
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(red: 0.0, green: 0.118, blue: 0.169, alpha: 1.0)  // Theme.midnight
        textView.textColor = .white
        textView.insertionPointColor = NSColor(red: 0.0, green: 0.929, blue: 0.392, alpha: 1.0)  // Theme.green
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(red: 0.0, green: 0.929, blue: 0.392, alpha: 0.25)
        ]

        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(red: 0.0, green: 0.118, blue: 0.169, alpha: 1.0)
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        textView.string = text
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
        textView.textColor = isDisabled ? NSColor.white.withAlphaComponent(0.5) : .white
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        /// Guards against re-entrant auto-completion while inserting the completion itself.
        private var isCompleting = false

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if text != textView.string {
                text = textView.string
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
