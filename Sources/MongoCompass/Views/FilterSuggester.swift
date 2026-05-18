import Foundation

// MARK: - Filter bar autocomplete
//
// Architecture mirrors how MongoDB Compass's CodeMirror integration works:
//
//   1. Lexer — tokenises the entire query string (strings with escapes,
//      brackets, commas, colons, identifiers, numbers).
//   2. Context analyzer — walks tokens up to the cursor with a state
//      machine, tracking container stack + position (key / value / element)
//      + parent-field. This is the part that lets autocomplete *stay alive*
//      when the user types `"`, opens a nested `{ ... }`, switches between
//      multiple fields, or types inside `$or: [{ ... }]`.
//   3. Suggestion engine — branches on context: top-level keys vs.
//      comparison operators vs. value snippets vs. BSON types, etc.
//
// All ranges are UTF-16 NSRanges so they line up with NSTextField cursor
// positions exactly — no String.Index ↔ NSRange conversion at call sites.

// MARK: - Public types

enum FilterFieldKind {
    case filter
    case sort
    case projection
}

enum FilterSuggestionKind {
    case fieldName
    case logicalOperator     // $and, $or, $nor, $not, $expr
    case comparisonOperator  // $eq, $gt, $in, $exists, ...
    case arrayOperator       // $all, $elemMatch, $size
    case evaluationOperator  // $regex, $mod, $jsonSchema, $where, $text
    case geoOperator         // $geoIntersects, $near, $nearSphere, ...
    case bsonType            // "string", "int", ... for $type
    case literalValue        // 1, -1, true, false, null, [], {}

    var label: String {
        switch self {
        case .fieldName:           return "field"
        case .logicalOperator:     return "logical"
        case .comparisonOperator:  return "compare"
        case .arrayOperator:       return "array"
        case .evaluationOperator:  return "eval"
        case .geoOperator:         return "geo"
        case .bsonType:            return "type"
        case .literalValue:        return "value"
        }
    }
}

struct FilterSuggestion: Identifiable, Hashable {
    let id = UUID()
    /// Shown in the dropdown row.
    let text: String
    /// What actually gets inserted. Usually equals `text`, but for snippets
    /// like `{ $exists: true }` the row shows a friendly label and the
    /// insertion carries the full snippet body.
    let insertion: String
    /// After insertion, advance the cursor by this many UTF-16 units relative
    /// to the start of the inserted text. Lets us place the caret inside
    /// snippet brackets instead of at the very end.
    let cursorOffsetAfterInsertion: Int?
    let kind: FilterSuggestionKind
    let detail: String

    init(text: String, insertion: String? = nil, cursorOffsetAfterInsertion: Int? = nil,
         kind: FilterSuggestionKind, detail: String) {
        self.text = text
        self.insertion = insertion ?? text
        self.cursorOffsetAfterInsertion = cursorOffsetAfterInsertion
        self.kind = kind
        self.detail = detail
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.kind == rhs.kind
    }
    func hash(into h: inout Hasher) {
        h.combine(text); h.combine(kind.label)
    }
}

// MARK: - Tokens

enum MQLToken {
    case lbrace(NSRange)
    case rbrace(NSRange)
    case lbracket(NSRange)
    case rbracket(NSRange)
    case comma(NSRange)
    case colon(NSRange)
    /// `content` excludes the quotes. `terminated` is false when the
    /// closing quote hasn't been typed yet (cursor parked inside the string).
    case string(content: String, terminated: Bool, range: NSRange, quote: Character)
    case identifier(text: String, range: NSRange)
    case number(text: String, range: NSRange)
    case whitespace(NSRange)
    case unknown(NSRange)

    var range: NSRange {
        switch self {
        case .lbrace(let r), .rbrace(let r), .lbracket(let r), .rbracket(let r),
             .comma(let r), .colon(let r), .whitespace(let r), .unknown(let r):
            return r
        case .string(_, _, let r, _), .identifier(_, let r), .number(_, let r):
            return r
        }
    }
}

enum MQLLexer {
    static func tokenize(_ text: String) -> [MQLToken] {
        let ns = text as NSString
        let n = ns.length
        var tokens: [MQLToken] = []
        var i = 0

        while i < n {
            let start = i
            let c = ns.character(at: i)

            switch c {
            case A.lbrace:
                tokens.append(.lbrace(NSRange(location: i, length: 1))); i += 1
            case A.rbrace:
                tokens.append(.rbrace(NSRange(location: i, length: 1))); i += 1
            case A.lbracket:
                tokens.append(.lbracket(NSRange(location: i, length: 1))); i += 1
            case A.rbracket:
                tokens.append(.rbracket(NSRange(location: i, length: 1))); i += 1
            case A.comma:
                tokens.append(.comma(NSRange(location: i, length: 1))); i += 1
            case A.colon:
                tokens.append(.colon(NSRange(location: i, length: 1))); i += 1
            case A.doubleQuote, A.singleQuote:
                let quote = Character(UnicodeScalar(c)!)
                let openLoc = i
                i += 1
                var terminated = false
                while i < n {
                    let cc = ns.character(at: i)
                    if cc == A.backslash && i + 1 < n {
                        i += 2
                    } else if cc == c {
                        terminated = true
                        i += 1
                        break
                    } else {
                        i += 1
                    }
                }
                let contentStart = openLoc + 1
                let contentEnd = i - (terminated ? 1 : 0)
                let content: String
                if contentEnd > contentStart {
                    content = ns.substring(with: NSRange(location: contentStart, length: contentEnd - contentStart))
                } else {
                    content = ""
                }
                tokens.append(.string(content: content, terminated: terminated,
                                      range: NSRange(location: start, length: i - start),
                                      quote: quote))
            default:
                if Self.isWhitespace(c) {
                    while i < n && Self.isWhitespace(ns.character(at: i)) { i += 1 }
                    tokens.append(.whitespace(NSRange(location: start, length: i - start)))
                } else if Self.isIdentStart(c) {
                    while i < n && Self.isIdentPart(ns.character(at: i)) { i += 1 }
                    let txt = ns.substring(with: NSRange(location: start, length: i - start))
                    tokens.append(.identifier(text: txt, range: NSRange(location: start, length: i - start)))
                } else if Self.isNumberStart(c) {
                    i += 1
                    while i < n && Self.isNumberPart(ns.character(at: i)) { i += 1 }
                    let txt = ns.substring(with: NSRange(location: start, length: i - start))
                    tokens.append(.number(text: txt, range: NSRange(location: start, length: i - start)))
                } else {
                    tokens.append(.unknown(NSRange(location: start, length: 1)))
                    i += 1
                }
            }
        }
        return tokens
    }

    private static func isWhitespace(_ c: unichar) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
    }
    private static func isIdentStart(_ c: unichar) -> Bool {
        (c >= 0x41 && c <= 0x5A) ||   // A...Z
        (c >= 0x61 && c <= 0x7A) ||   // a...z
        c == 0x5F || c == 0x24         // _, $
    }
    private static func isIdentPart(_ c: unichar) -> Bool {
        isIdentStart(c) || (c >= 0x30 && c <= 0x39) || c == 0x2E   // 0-9, .
    }
    private static func isNumberStart(_ c: unichar) -> Bool {
        (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x2B          // 0-9, -, +
    }
    private static func isNumberPart(_ c: unichar) -> Bool {
        (c >= 0x30 && c <= 0x39) ||
        c == 0x2E || c == 0x2D || c == 0x2B ||                       // . - +
        c == 0x65 || c == 0x45                                       // e, E
    }
}

/// ASCII codepoints we match against `unichar` values inside the lexer.
/// Plain hex constants keep the lexer self-contained and avoid the
/// `UInt8(ascii:)` ↔ `UInt16` dance.
private enum A {
    static let lbrace: unichar      = 0x7B  // {
    static let rbrace: unichar      = 0x7D  // }
    static let lbracket: unichar    = 0x5B  // [
    static let rbracket: unichar    = 0x5D  // ]
    static let comma: unichar       = 0x2C  // ,
    static let colon: unichar       = 0x3A  // :
    static let doubleQuote: unichar = 0x22  // "
    static let singleQuote: unichar = 0x27  // '
    static let backslash: unichar   = 0x5C  // backslash
}

// MARK: - Context

enum FilterPosition {
    /// Expecting a field name / operator key. Top-of-stack object is in
    /// `expectKey` (just after `{` or `,`).
    case objectKey
    /// Expecting a value. Just after `:`.
    case objectValue
    /// Inside an array, expecting an element (after `[` or `,`).
    case arrayElement
    /// Cursor sits where a value was just placed — nothing to autocomplete.
    case afterValue
    /// Couldn't pin down the context.
    case unknown
}

enum ContainerKind { case object, array }

struct FilterContext {
    let position: FilterPosition
    let containerStack: [ContainerKind]
    /// The key in the *parent* object whose value is the container the cursor
    /// is inside. For `{ name: { $g| } }` this is `"name"`. For
    /// `{ $or: [{ a: |1 }] }` while inside the inner object this is `"$or"`.
    let parentFieldName: String?

    /// Text of the token the cursor sits inside (empty when cursor is in
    /// whitespace between tokens).
    let partialText: String
    /// Range to overwrite when accepting a suggestion. For identifiers this
    /// is the full identifier; for strings it's the content between the
    /// quotes; for whitespace it's the empty zero-length cursor position.
    let replaceRange: NSRange
    /// True when cursor is parked inside `"..."` (the parser already peeled
    /// off the opening quote). Tells the inserter to append a closing quote.
    let isInsideString: Bool
    let stringNeedsClosing: Bool
    let stringQuote: Character?
}

enum MQLContextAnalyzer {

    private struct Frame {
        var kind: ContainerKind
        var state: State
        /// Key in the parent object whose value opened this frame (e.g. for
        /// `{ name: { $gt: 5 } }`, the inner frame's `openedAsValueOf` is
        /// `"name"`). Inherited from the parent's `lastSeenKey` at the time
        /// of pushing.
        var openedAsValueOf: String?
        /// Most recent key seen at this object's level — used to populate
        /// the *child's* `openedAsValueOf` when a `{` or `[` is pushed next.
        var lastSeenKey: String?
    }

    private enum State {
        case expectKey, afterKey, expectValue, afterValue   // objects
        case expectElement, afterElement                     // arrays
    }

    static func analyze(text: String, cursor: Int) -> FilterContext {
        let tokens = MQLLexer.tokenize(text)
        let cursor = max(0, min(cursor, (text as NSString).length))

        var stack: [Frame] = []
        var captured: FilterContext? = nil

        func currentPosition() -> FilterPosition {
            guard let top = stack.last else { return .objectKey } // top-of-text, expecting `{`/key
            switch (top.kind, top.state) {
            case (.object, .expectKey):     return .objectKey
            case (.object, .afterKey):      return .unknown
            case (.object, .expectValue):   return .objectValue
            case (.object, .afterValue):    return .afterValue
            case (.array, .expectElement):  return .arrayElement
            case (.array, .afterElement):   return .afterValue
            default:                        return .unknown
            }
        }

        func currentParentField() -> String? {
            stack.last?.openedAsValueOf
        }

        func captureAtCursor(position: FilterPosition,
                             partial: String,
                             replace: NSRange,
                             isInString: Bool,
                             needsClosing: Bool,
                             quote: Character?) {
            captured = FilterContext(
                position: position,
                containerStack: stack.map { $0.kind },
                parentFieldName: currentParentField(),
                partialText: partial,
                replaceRange: replace,
                isInsideString: isInString,
                stringNeedsClosing: needsClosing,
                stringQuote: quote
            )
        }

        // Walk tokens applying transitions, capturing context the moment we
        // either reach the cursor (inside a token) or step past it.
        for token in tokens {
            let r = token.range
            let tokenStart = r.location
            let tokenEnd = r.location + r.length

            // Cursor is in whitespace/empty space *before* this token's start.
            if cursor < tokenStart {
                captureAtCursor(
                    position: currentPosition(),
                    partial: "",
                    replace: NSRange(location: cursor, length: 0),
                    isInString: false, needsClosing: false, quote: nil
                )
                break
            }

            // Cursor sits inside (or at the boundary of) this token.
            if cursor <= tokenEnd {
                switch token {
                case .identifier(let txt, let rng):
                    captureAtCursor(
                        position: currentPosition(),
                        partial: txt,
                        replace: rng,
                        isInString: false, needsClosing: false, quote: nil
                    )
                case .string(let content, let terminated, let rng, let quote):
                    // Replace just the content (between the quotes). If the
                    // string is unterminated, the inserter will append the
                    // closing quote.
                    let contentStart = rng.location + 1
                    let contentEnd = rng.location + rng.length - (terminated ? 1 : 0)
                    let replace = NSRange(location: contentStart,
                                          length: max(0, contentEnd - contentStart))
                    captureAtCursor(
                        position: currentPosition(),
                        partial: content,
                        replace: replace,
                        isInString: true,
                        needsClosing: !terminated,
                        quote: quote
                    )
                case .number(let txt, let rng):
                    captureAtCursor(
                        position: currentPosition(),
                        partial: txt,
                        replace: rng,
                        isInString: false, needsClosing: false, quote: nil
                    )
                case .whitespace, .lbrace, .rbrace, .lbracket, .rbracket,
                     .comma, .colon, .unknown:
                    // Cursor is in punctuation/whitespace — no replaceable
                    // token, but state is whatever the position-machine says.
                    captureAtCursor(
                        position: currentPosition(),
                        partial: "",
                        replace: NSRange(location: cursor, length: 0),
                        isInString: false, needsClosing: false, quote: nil
                    )
                }
                break
            }

            // Cursor is past this token entirely — apply transition and move on.
            apply(token: token, stack: &stack)
        }

        if let result = captured {
            return result
        }

        // Cursor past everything — current position after applying all transitions.
        return FilterContext(
            position: currentPosition(),
            containerStack: stack.map { $0.kind },
            parentFieldName: currentParentField(),
            partialText: "",
            replaceRange: NSRange(location: cursor, length: 0),
            isInsideString: false,
            stringNeedsClosing: false,
            stringQuote: nil
        )
    }

    private static func apply(token: MQLToken, stack: inout [Frame]) {
        switch token {
        case .whitespace, .unknown:
            return

        case .lbrace:
            let inheritedKey = stack.last?.lastSeenKey
            // Reset lastSeenKey on the parent because it's now "consumed".
            if !stack.isEmpty { stack[stack.count - 1].lastSeenKey = nil }
            stack.append(Frame(kind: .object, state: .expectKey,
                               openedAsValueOf: inheritedKey, lastSeenKey: nil))

        case .lbracket:
            let inheritedKey = stack.last?.lastSeenKey ?? stack.last?.openedAsValueOf
            if !stack.isEmpty { stack[stack.count - 1].lastSeenKey = nil }
            stack.append(Frame(kind: .array, state: .expectElement,
                               openedAsValueOf: inheritedKey, lastSeenKey: nil))

        case .rbrace:
            if let top = stack.last, top.kind == .object {
                stack.removeLast()
                advanceParentAfterValue(&stack)
            }

        case .rbracket:
            if let top = stack.last, top.kind == .array {
                stack.removeLast()
                advanceParentAfterValue(&stack)
            }

        case .comma:
            guard !stack.isEmpty else { return }
            switch stack[stack.count - 1].kind {
            case .object:
                if stack[stack.count - 1].state == .afterValue {
                    stack[stack.count - 1].state = .expectKey
                    stack[stack.count - 1].lastSeenKey = nil
                }
            case .array:
                if stack[stack.count - 1].state == .afterElement {
                    stack[stack.count - 1].state = .expectElement
                }
            }

        case .colon:
            guard !stack.isEmpty else { return }
            if stack[stack.count - 1].kind == .object,
               stack[stack.count - 1].state == .afterKey {
                stack[stack.count - 1].state = .expectValue
            }

        case .identifier(let txt, _), .string(let txt, _, _, _):
            guard !stack.isEmpty else { return }
            switch stack[stack.count - 1].kind {
            case .object:
                switch stack[stack.count - 1].state {
                case .expectKey:
                    stack[stack.count - 1].state = .afterKey
                    stack[stack.count - 1].lastSeenKey = txt
                case .expectValue:
                    stack[stack.count - 1].state = .afterValue
                default: break
                }
            case .array:
                if stack[stack.count - 1].state == .expectElement {
                    stack[stack.count - 1].state = .afterElement
                }
            }

        case .number:
            guard !stack.isEmpty else { return }
            switch stack[stack.count - 1].kind {
            case .object:
                if stack[stack.count - 1].state == .expectValue {
                    stack[stack.count - 1].state = .afterValue
                }
            case .array:
                if stack[stack.count - 1].state == .expectElement {
                    stack[stack.count - 1].state = .afterElement
                }
            }
        }
    }

    private static func advanceParentAfterValue(_ stack: inout [Frame]) {
        guard !stack.isEmpty else { return }
        switch stack[stack.count - 1].kind {
        case .object:
            if stack[stack.count - 1].state == .expectValue {
                stack[stack.count - 1].state = .afterValue
            }
        case .array:
            if stack[stack.count - 1].state == .expectElement {
                stack[stack.count - 1].state = .afterElement
            }
        }
    }
}

// MARK: - Operator catalog

private enum OperatorCatalog {

    static let logical: [FilterSuggestion] = [
        .init(text: "$and",  insertion: "$and",  kind: .logicalOperator, detail: "all conditions match"),
        .init(text: "$or",   insertion: "$or",   kind: .logicalOperator, detail: "any condition matches"),
        .init(text: "$nor",  insertion: "$nor",  kind: .logicalOperator, detail: "no condition matches"),
        .init(text: "$not",  insertion: "$not",  kind: .logicalOperator, detail: "invert match"),
        .init(text: "$expr", insertion: "$expr", kind: .logicalOperator, detail: "aggregation expression"),
    ]

    static let comparison: [FilterSuggestion] = [
        .init(text: "$eq",  kind: .comparisonOperator, detail: "equals"),
        .init(text: "$ne",  kind: .comparisonOperator, detail: "not equals"),
        .init(text: "$gt",  kind: .comparisonOperator, detail: "greater than"),
        .init(text: "$gte", kind: .comparisonOperator, detail: "greater than or equal"),
        .init(text: "$lt",  kind: .comparisonOperator, detail: "less than"),
        .init(text: "$lte", kind: .comparisonOperator, detail: "less than or equal"),
        .init(text: "$in",  kind: .comparisonOperator, detail: "value in array"),
        .init(text: "$nin", kind: .comparisonOperator, detail: "value not in array"),
        .init(text: "$exists", kind: .comparisonOperator, detail: "field exists"),
        .init(text: "$type", kind: .comparisonOperator, detail: "BSON type matches"),
    ]

    static let evaluation: [FilterSuggestion] = [
        .init(text: "$regex",      kind: .evaluationOperator, detail: "regex match"),
        .init(text: "$options",    kind: .evaluationOperator, detail: "regex flags"),
        .init(text: "$mod",        kind: .evaluationOperator, detail: "modulo result"),
        .init(text: "$jsonSchema", kind: .evaluationOperator, detail: "JSON Schema validation"),
        .init(text: "$where",      kind: .evaluationOperator, detail: "javascript predicate"),
        .init(text: "$text",       kind: .evaluationOperator, detail: "text search"),
        .init(text: "$comment",    kind: .evaluationOperator, detail: "query comment"),
    ]

    static let array: [FilterSuggestion] = [
        .init(text: "$all",       kind: .arrayOperator, detail: "array contains all"),
        .init(text: "$elemMatch", kind: .arrayOperator, detail: "array element matches"),
        .init(text: "$size",      kind: .arrayOperator, detail: "array length equals"),
    ]

    static let geo: [FilterSuggestion] = [
        .init(text: "$geoIntersects", kind: .geoOperator, detail: "geometry intersects"),
        .init(text: "$geoWithin",     kind: .geoOperator, detail: "geometry within"),
        .init(text: "$near",          kind: .geoOperator, detail: "near a point"),
        .init(text: "$nearSphere",    kind: .geoOperator, detail: "near a point (spherical)"),
    ]

    /// All operators that can be used as a key inside `{ field: { ... } }`.
    static var allFieldLevel: [FilterSuggestion] {
        comparison + array + evaluation + geo
    }

    static let bsonTypes: [FilterSuggestion] = [
        "double", "string", "object", "array", "binData", "objectId", "bool",
        "date", "null", "regex", "javascript", "int", "timestamp", "long", "decimal",
    ].map {
        .init(text: $0, insertion: "\"\($0)\"", kind: .bsonType, detail: "BSON type")
    }
}

// MARK: - Suggestion engine

enum FilterSuggester {

    /// Field paths sampled from a few loaded documents. Includes dot-paths
    /// like `address.city`. Caps to keep dropdown sane.
    static func extractFieldPaths(
        from documents: [[String: Any]],
        maxDocs: Int = 8,
        maxDepth: Int = 3,
        maxPaths: Int = 120
    ) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        func walk(_ dict: [String: Any], prefix: String, depth: Int) {
            guard depth <= maxDepth else { return }
            for key in dict.keys.sorted() {
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                if seen.insert(path).inserted {
                    ordered.append(path)
                    if ordered.count >= maxPaths { return }
                }
                if depth < maxDepth, let nested = dict[key] as? [String: Any] {
                    walk(nested, prefix: path, depth: depth + 1)
                }
            }
        }

        for doc in documents.prefix(maxDocs) {
            walk(doc, prefix: "", depth: 1)
            if ordered.count >= maxPaths { break }
        }
        return ordered
    }

    /// Builds the full suggestion list for the current cursor position.
    /// Returns the list together with the range to replace on accept.
    static func complete(
        text: String,
        cursor: Int,
        kind: FilterFieldKind,
        fieldPaths: [String]
    ) -> (suggestions: [FilterSuggestion], context: FilterContext) {
        let ctx = MQLContextAnalyzer.analyze(text: text, cursor: cursor)
        let raw = candidates(for: kind, ctx: ctx, fieldPaths: fieldPaths)
        let filtered = filterAndRank(raw, by: ctx.partialText)
        return (filtered, ctx)
    }

    // MARK: Candidate generation

    private static func candidates(
        for kind: FilterFieldKind,
        ctx: FilterContext,
        fieldPaths: [String]
    ) -> [FilterSuggestion] {
        switch kind {
        case .filter:
            return filterCandidates(ctx: ctx, fields: fieldPaths)
        case .sort:
            switch ctx.position {
            case .objectKey:
                return fieldSuggestions(from: fieldPaths)
            case .objectValue:
                return [
                    .init(text: "1",  kind: .literalValue, detail: "ascending"),
                    .init(text: "-1", kind: .literalValue, detail: "descending"),
                ]
            default:
                return []
            }
        case .projection:
            switch ctx.position {
            case .objectKey:
                return fieldSuggestions(from: fieldPaths)
            case .objectValue:
                return [
                    .init(text: "1", kind: .literalValue, detail: "include field"),
                    .init(text: "0", kind: .literalValue, detail: "exclude field"),
                ]
            default:
                return []
            }
        }
    }

    private static func filterCandidates(ctx: FilterContext, fields: [String]) -> [FilterSuggestion] {
        switch ctx.position {
        case .objectKey:
            return keyCandidatesForFilter(parent: ctx.parentFieldName, fields: fields)

        case .objectValue:
            // Value position. If the parent key is an operator, we can
            // suggest type-appropriate values; otherwise, generic snippets.
            if let parent = ctx.parentFieldName {
                if let typed = valueSuggestionsForOperator(parent) {
                    return typed
                }
            }
            return genericValueSnippets()

        case .arrayElement:
            // `[ ... ]`. If parent is logical-array ($or/$and/$nor), suggest
            // a sub-filter snippet. Otherwise, plain value literals.
            if let parent = ctx.parentFieldName,
               ["$or", "$and", "$nor"].contains(parent) {
                return [
                    .init(text: "{ }",
                          insertion: "{  }",
                          cursorOffsetAfterInsertion: 2,
                          kind: .literalValue,
                          detail: "sub-filter")
                ]
            }
            return genericValueSnippets()

        case .afterValue, .unknown:
            return []
        }
    }

    private static func keyCandidatesForFilter(parent: String?, fields: [String]) -> [FilterSuggestion] {
        // Three macro-cases:
        //   - No parent (top-level)  → field names + logical ops
        //   - Parent is $or/$and/$nor/$elemMatch → sub-filter (fields + logical)
        //   - Parent is anything else (regular field OR $not / $expr inner) → operators

        guard let parent = parent else {
            return fieldSuggestions(from: fields) + OperatorCatalog.logical
        }

        if ["$or", "$and", "$nor", "$elemMatch", "$not"].contains(parent) {
            return fieldSuggestions(from: fields) + OperatorCatalog.logical
        }

        // Field with nested spec — operators apply here.
        return OperatorCatalog.allFieldLevel
    }

    // MARK: Value suggestions per operator

    private static func valueSuggestionsForOperator(_ op: String) -> [FilterSuggestion]? {
        switch op {
        case "$exists":
            return [
                .init(text: "true",  kind: .literalValue, detail: "field exists"),
                .init(text: "false", kind: .literalValue, detail: "field absent"),
            ]
        case "$type":
            return OperatorCatalog.bsonTypes
        case "$in", "$nin", "$all":
            return [
                .init(text: "[ ]",
                      insertion: "[ ]",
                      cursorOffsetAfterInsertion: 2,
                      kind: .literalValue, detail: "array of values"),
            ]
        case "$size":
            return [
                .init(text: "0", kind: .literalValue, detail: "empty array"),
                .init(text: "1", kind: .literalValue, detail: "exactly one"),
            ]
        case "$regex":
            return [
                .init(text: "\"^prefix\"",
                      insertion: "\"^\"",
                      cursorOffsetAfterInsertion: 2,
                      kind: .literalValue, detail: "regex pattern"),
            ]
        case "$options":
            return [
                .init(text: "\"i\"", kind: .literalValue, detail: "case-insensitive"),
                .init(text: "\"im\"", kind: .literalValue, detail: "case-insensitive + multiline"),
            ]
        case "$elemMatch":
            return [
                .init(text: "{ }",
                      insertion: "{  }",
                      cursorOffsetAfterInsertion: 2,
                      kind: .literalValue, detail: "element predicate"),
            ]
        default:
            return nil
        }
    }

    private static func genericValueSnippets() -> [FilterSuggestion] {
        [
            .init(text: "{ $gt: 0 }",
                  insertion: "{ $gt:  }",
                  cursorOffsetAfterInsertion: 7,
                  kind: .comparisonOperator, detail: "greater than snippet"),
            .init(text: "{ $in: [...] }",
                  insertion: "{ $in: [ ] }",
                  cursorOffsetAfterInsertion: 8,
                  kind: .comparisonOperator, detail: "value in array"),
            .init(text: "{ $exists: true }",
                  insertion: "{ $exists: true }",
                  kind: .comparisonOperator, detail: "field exists"),
            .init(text: "{ $regex: \"^…\", $options: \"i\" }",
                  insertion: "{ $regex: \"^\", $options: \"i\" }",
                  cursorOffsetAfterInsertion: 12,
                  kind: .evaluationOperator, detail: "case-insensitive regex"),
            .init(text: "null",  kind: .literalValue, detail: "null"),
            .init(text: "true",  kind: .literalValue, detail: "boolean true"),
            .init(text: "false", kind: .literalValue, detail: "boolean false"),
        ]
    }

    private static func fieldSuggestions(from paths: [String]) -> [FilterSuggestion] {
        paths.map { .init(text: $0, kind: .fieldName, detail: "from sampled docs") }
    }

    // MARK: Ranking

    /// Prefix-rank: exact prefix → contains → all (when token empty). Drops
    /// exact matches (nothing new to type). Caps at 30 rows.
    private static func filterAndRank(_ items: [FilterSuggestion], by token: String) -> [FilterSuggestion] {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Array(items.prefix(30))
        }
        let lower = trimmed.lowercased()
        var prefix: [FilterSuggestion] = []
        var contains: [FilterSuggestion] = []
        for item in items {
            let t = item.text.lowercased()
            if t == lower { continue }
            if t.hasPrefix(lower) {
                prefix.append(item)
            } else if t.contains(lower) {
                contains.append(item)
            }
        }
        return Array((prefix + contains).prefix(30))
    }

    // MARK: Insertion

    /// Build the new (text, cursor) pair after accepting a suggestion at the
    /// given context. Handles closing quotes on unterminated strings and
    /// snippet cursor placement.
    static func apply(
        _ suggestion: FilterSuggestion,
        to text: String,
        context: FilterContext
    ) -> (text: String, cursor: Int) {
        let ns = (text as NSString).mutableCopy() as! NSMutableString
        let range = context.replaceRange

        // Compose the insertion. If we're inside an unterminated string and
        // the suggestion is "atomic" (no balanced quotes/brackets of its own),
        // append the closing quote so the string isn't left dangling.
        var insertion = suggestion.insertion
        if context.isInsideString && context.stringNeedsClosing && !insertion.contains("\"") && !insertion.contains("'") {
            let quote = context.stringQuote.map(String.init) ?? "\""
            insertion += quote
        }

        // Guard against an invalid range (shouldn't happen, but be safe).
        let safeRange: NSRange
        if range.location + range.length <= ns.length {
            safeRange = range
        } else {
            safeRange = NSRange(location: min(range.location, ns.length), length: 0)
        }

        ns.replaceCharacters(in: safeRange, with: insertion)

        let baseCursor = safeRange.location + (insertion as NSString).length
        // For snippets that ship an explicit offset, position the cursor
        // inside the inserted snippet (relative to the *insertion start*).
        let cursor: Int
        if let offset = suggestion.cursorOffsetAfterInsertion {
            cursor = safeRange.location + offset
        } else {
            cursor = baseCursor
        }

        return (ns as String, cursor)
    }
}
