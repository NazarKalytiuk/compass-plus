import SwiftUI

@MainActor
struct DocumentEditorView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    enum Mode {
        case insert
        case edit([String: Any])
    }

    enum JSONFormat: String, CaseIterable, Identifiable {
        case json = "JSON"
        case ejson = "EJSON"
        var id: String { rawValue }
    }

    let mode: Mode

    @State private var jsonText: String = ""
    @State private var originalText: String = ""
    @State private var jsonFormat: JSONFormat = .json
    @State private var lintIssues: [LintIssue] = []
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var validator: [String: Any]?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            editorBody
            footer
        }
        .frame(width: 920, height: 600)
        .background(Theme.surface0)
        .onAppear {
            initializeJSON()
            revalidate()
            Task { await loadValidator() }
        }
    }

    /// Best-effort fetch of the collection's `$jsonSchema` validator. Used by
    /// runLint to surface required-field and type-mismatch issues.
    private func loadValidator() async {
        guard let db = viewModel.activeTab.selectedDatabase,
              let coll = viewModel.activeTab.selectedCollection else { return }
        if let v = try? await viewModel.mongoService.getValidator(database: db, collection: coll) {
            validator = v
            revalidate()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            breadcrumb

            if hasUnsavedChanges {
                Text("unsaved").pillBadge(.accent)
            }

            Spacer()

            Button {
                formatJSON()
            } label: {
                HStack(spacing: 6) {
                    Text("⌘⇧F")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                    Text("Format")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textSoft)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .help("Auto-format JSON")

            Button {
                revalidate()
            } label: {
                Text("Validate")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Re-run lint checks")

            Segmented(
                items: JSONFormat.allCases,
                label: { Text($0.rawValue) },
                selection: $jsonFormat
            )
            .disabled(true)
            .opacity(0.55)
            .help("EJSON is not yet supported")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface1)
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isConnected ? Theme.success : Theme.textMuted)
                .frame(width: 7, height: 7)
                .padding(.trailing, 2)

            if let db = viewModel.activeTab.selectedDatabase {
                Text(db)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            if let coll = viewModel.activeTab.selectedCollection {
                Text(coll)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            Text(isInsert ? "insert" : "edit")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.primaryDeep)
        }
    }

    // MARK: - Editor body (split: editor pane + lint panel)

    private var editorBody: some View {
        HStack(alignment: .top, spacing: 16) {
            editorPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            lintPanel
                .frame(width: 320)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(isInsert ? "Insert document" : "Edit document")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.codeFg)

                Text(headerSub)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.codeMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)

                miniDarkPill(charsetLabel)
                miniDarkPill(lineEndingLabel)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(jsonText, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.codeMuted)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy JSON")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            TextEditor(text: $jsonText)
                .scrollContentBackground(.hidden)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Theme.codeFg)
                .tint(Theme.primary)
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
                .background(Color.clear)
        }
        .background(Theme.codeBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
        .onChange(of: jsonText) { _, _ in revalidate() }
    }

    private func miniDarkPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Theme.codeMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
    }

    private var headerSub: String {
        let db = viewModel.activeTab.selectedDatabase ?? "—"
        let coll = viewModel.activeTab.selectedCollection ?? "—"
        return "\(db).\(coll) · \(isInsert ? "new BSON document" : "edit existing")"
    }

    // MARK: - Lint panel

    private var lintPanel: some View {
        let errs = lintIssues.filter { $0.severity == .error }.count
        let warns = lintIssues.filter { $0.severity == .warning }.count
        let infos = lintIssues.filter { $0.severity == .info }.count

        return VStack(alignment: .leading, spacing: 0) {
            Text("Schema lint")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("Local JSON parser · structure checks")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 2)
                .padding(.bottom, 12)

            HStack(spacing: 6) {
                if errs > 0 {
                    Text("\(errs) \(errs == 1 ? "error" : "errors")").pillBadge(.danger)
                }
                if warns > 0 {
                    Text("\(warns) \(warns == 1 ? "warning" : "warnings")").pillBadge(.warning)
                }
                if infos > 0 {
                    Text("\(infos) \(infos == 1 ? "hint" : "hints")").pillBadge(.info)
                }
                if errs == 0 && warns == 0 && infos == 0 {
                    Text("All clear").pillBadge(.success)
                }
            }
            .padding(.bottom, 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    if lintIssues.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(Theme.success).frame(width: 8, height: 8).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No structural issues detected.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSoft)
                                Text("Ready to \(isInsert ? "insert" : "save").")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(Theme.successTint.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        ForEach(lintIssues) { issue in
                            lintItemView(issue)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
    }

    private func lintItemView(_ issue: LintIssue) -> some View {
        let bg: Color = {
            switch issue.severity {
            case .error:   return Theme.dangerTint
            case .warning: return Theme.warningTint
            case .info:    return Theme.infoTint
            }
        }()
        let markerColor: Color = {
            switch issue.severity {
            case .error:   return Theme.danger
            case .warning: return Theme.warning
            case .info:    return Theme.info
            }
        }()
        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(markerColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Text(issueMeta(issue))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func issueMeta(_ issue: LintIssue) -> String {
        var parts: [String] = []
        if let line = issue.line { parts.append("line \(line)") }
        if let validator = issue.validator { parts.append(validator) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text(footerMeta)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.textMuted)

            if let saveError {
                Text("•")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted.opacity(0.6))
                Text(saveError)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.dangerDeep)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            if isSaving {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }

            Button("Cancel") { dismiss() }
                .buttonStyle(.ghost)

            if isInsert {
                Button {
                    save(keepOpen: true)
                } label: {
                    Text("Insert & clone")
                }
                .buttonStyle(.ghost)
                .disabled(hasErrors || isSaving)
                .help("Insert this document, clear _id, keep editor open for the next one")
            }

            Button {
                save()
            } label: {
                Text(isInsert ? "Insert document" : "Save changes")
            }
            .buttonStyle(.accent)
            .disabled(hasErrors || isSaving || !hasUnsavedChanges && !isInsert)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface1)
    }

    private var footerMeta: String {
        let lines = jsonText.components(separatedBy: "\n").count
        let bytes = jsonText.data(using: .utf8)?.count ?? 0
        let cursor = "" // SwiftUI's TextEditor doesn't expose cursor position
        var s = "\(lines) line\(lines == 1 ? "" : "s") · \(bytes) B"
        if !cursor.isEmpty { s += " · \(cursor)" }
        return s
    }

    // MARK: - State helpers

    private var isInsert: Bool {
        if case .insert = mode { return true }
        return false
    }

    /// Charset is always UTF-8 in-memory; if the user pasted invalid bytes
    /// the `data(using:)` round-trip would fail and we surface that.
    private var charsetLabel: String {
        jsonText.data(using: .utf8) != nil ? "UTF-8" : "INVALID"
    }

    private var lineEndingLabel: String {
        jsonText.contains("\r\n") ? "CRLF" : "LF"
    }

    private var hasErrors: Bool { lintIssues.contains { $0.severity == .error } }
    private var hasUnsavedChanges: Bool { jsonText != originalText }

    private func initializeJSON() {
        switch mode {
        case .insert:
            jsonText = "{\n  \n}"
        case .edit(let document):
            var editableDoc = document
            editableDoc.removeValue(forKey: "_id")
            if let data = try? JSONSerialization.data(withJSONObject: editableDoc, options: [.prettyPrinted, .sortedKeys]),
               let s = String(data: data, encoding: .utf8) {
                jsonText = s
            } else {
                jsonText = "{}"
            }
        }
        originalText = jsonText
    }

    // MARK: - Lint engine

    private func revalidate() {
        lintIssues = runLint(jsonText)
    }

    private func runLint(_ text: String) -> [LintIssue] {
        var issues: [LintIssue] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            issues.append(LintIssue(severity: .error,
                                    message: "Document is empty. Provide a JSON object.",
                                    line: 1, validator: "json parser"))
            return issues
        }
        guard let data = trimmed.data(using: .utf8) else {
            issues.append(LintIssue(severity: .error,
                                    message: "Invalid text encoding.",
                                    line: nil, validator: "json parser"))
            return issues
        }

        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            guard let dict = obj as? [String: Any] else {
                issues.append(LintIssue(severity: .error,
                                        message: "Root element must be a JSON object ({…}).",
                                        line: 1, validator: "structure"))
                return issues
            }
            if dict.isEmpty {
                issues.append(LintIssue(severity: .warning,
                                        message: "Empty object — no fields to \(isInsert ? "insert" : "save").",
                                        line: 1, validator: "structure"))
            }
            if case .insert = mode, dict["_id"] != nil {
                issues.append(LintIssue(severity: .info,
                                        message: "An explicit _id was provided. MongoDB will respect it; ensure it is unique within the collection.",
                                        line: lineForKey("_id", in: text), validator: "structure"))
            }
            if let validator {
                issues.append(contentsOf: lintAgainstSchema(dict: dict, schema: validator, text: text))
            } else {
                issues.append(contentsOf: lintWithTypeHeuristic(dict: dict, text: text))
            }
        } catch let err as NSError {
            let raw = err.userInfo[NSDebugDescriptionErrorKey] as? String ?? err.localizedDescription
            issues.append(LintIssue(
                severity: .error,
                message: cleanParserError(raw),
                line: parseErrorLine(from: raw),
                validator: "json parser"))
        }
        return issues
    }

    // MARK: - Schema-driven lint

    /// Walk `$jsonSchema.properties` against the parsed dict: flag required
    /// missing fields, type mismatches, and enum violations. Insert mode
    /// surfaces missing required as errors; edit mode treats them as info
    /// since updates may be partial.
    private func lintAgainstSchema(dict: [String: Any], schema: [String: Any], text: String) -> [LintIssue] {
        var issues: [LintIssue] = []

        let required = (schema["required"] as? [String]) ?? []
        let properties = (schema["properties"] as? [String: [String: Any]]) ?? [:]

        // Required-field check
        for field in required where field != "_id" {
            if dict[field] == nil {
                let sev: LintIssue.Severity = isInsert ? .error : .info
                issues.append(LintIssue(
                    severity: sev,
                    message: "Missing required field “\(field)”.",
                    line: nil,
                    validator: "$jsonSchema.required"))
            }
        }

        // Per-property checks
        for (field, value) in dict {
            guard let spec = properties[field] else {
                if let additional = schema["additionalProperties"] as? Bool, additional == false {
                    issues.append(LintIssue(
                        severity: .warning,
                        message: "Field “\(field)” isn't declared in the schema (additionalProperties: false).",
                        line: lineForKey(field, in: text),
                        validator: "$jsonSchema.additionalProperties"))
                }
                continue
            }

            // bsonType / type — both forms are accepted by $jsonSchema.
            let expected: [String] = Self.expectedTypes(from: spec)
            if !expected.isEmpty {
                let actual = Self.bsonTypeName(of: value)
                if !Self.typeMatches(actual: actual, expected: expected) {
                    issues.append(LintIssue(
                        severity: .error,
                        message: "Field “\(field)” should be \(expected.joined(separator: " | ")) but is \(actual).",
                        line: lineForKey(field, in: text),
                        validator: "$jsonSchema.bsonType"))
                }
            }

            if let enumValues = spec["enum"] as? [Any] {
                let asStrings = enumValues.map { "\($0)" }
                let actualString = "\(value)"
                if !asStrings.contains(actualString) {
                    issues.append(LintIssue(
                        severity: .error,
                        message: "Field “\(field)” must be one of: \(asStrings.joined(separator: ", ")).",
                        line: lineForKey(field, in: text),
                        validator: "$jsonSchema.enum"))
                }
            }
        }

        return issues
    }

    /// Type heuristic fallback used when no `$jsonSchema` validator is set on
    /// the collection. Flags numeric / boolean strings.
    private func lintWithTypeHeuristic(dict: [String: Any], text: String) -> [LintIssue] {
        var issues: [LintIssue] = []
        for (k, v) in dict {
            guard let s = v as? String else { continue }
            let trimmedVal = s.trimmingCharacters(in: .whitespaces)
            guard !trimmedVal.isEmpty else { continue }
            if Int(trimmedVal) != nil || Double(trimmedVal) != nil {
                issues.append(LintIssue(
                    severity: .warning,
                    message: "Field “\(k)” is a string but looks numeric (\"\(trimmedVal)\"). Did you mean \(trimmedVal)?",
                    line: lineForKey(k, in: text),
                    validator: "type heuristic"))
            } else if ["true", "false", "TRUE", "FALSE"].contains(trimmedVal) {
                issues.append(LintIssue(
                    severity: .warning,
                    message: "Field “\(k)” is a string but looks boolean (\"\(trimmedVal)\"). Did you mean \(trimmedVal.lowercased())?",
                    line: lineForKey(k, in: text),
                    validator: "type heuristic"))
            }
        }
        return issues
    }

    private static func expectedTypes(from spec: [String: Any]) -> [String] {
        if let one = spec["bsonType"] as? String { return [one] }
        if let many = spec["bsonType"] as? [String] { return many }
        if let one = spec["type"] as? String { return [one] }
        if let many = spec["type"] as? [String] { return many }
        return []
    }

    private static func bsonTypeName(of value: Any) -> String {
        if value is NSNull { return "null" }
        if let b = value as? NSNumber, CFGetTypeID(b) == CFBooleanGetTypeID() { return "bool" }
        if value is String { return "string" }
        if value is [Any] { return "array" }
        if value is [String: Any] { return "object" }
        if let n = value as? NSNumber {
            // JSONSerialization can't distinguish int / long / double here.
            // Match either int or double when the schema specifies either.
            let s = n.stringValue
            return s.contains(".") ? "double" : "int"
        }
        return "unknown"
    }

    private static func typeMatches(actual: String, expected: [String]) -> Bool {
        if expected.contains(actual) { return true }
        // Soft int<->long<->double<->number alias mapping
        let numericPool: Set<String> = ["int", "long", "double", "decimal", "number", "integer"]
        if numericPool.contains(actual) && expected.contains(where: numericPool.contains) {
            return true
        }
        if actual == "object" && expected.contains("object") { return true }
        return false
    }

    private func cleanParserError(_ raw: String) -> String {
        var s = raw
        if let r = s.range(of: " around character") {
            s = String(s[..<r.lowerBound])
        }
        if !s.hasSuffix(".") { s += "." }
        return s
    }

    private func parseErrorLine(from raw: String) -> Int? {
        guard let match = raw.range(of: "around line ", options: .caseInsensitive) else {
            return nil
        }
        let rest = raw[match.upperBound...]
        let digits = rest.prefix(while: { $0.isNumber })
        return Int(digits)
    }

    private func lineForKey(_ key: String, in text: String) -> Int? {
        let needle = "\"\(key)\""
        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() where line.contains(needle) {
            return i + 1
        }
        return nil
    }

    // MARK: - Actions

    private func formatJSON() {
        let trimmed = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return }
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            let formatted = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            if let s = String(data: formatted, encoding: .utf8) {
                jsonText = s
            }
        } catch {
            saveError = "Cannot format: \(error.localizedDescription)"
        }
    }

    private func save(keepOpen: Bool = false) {
        revalidate()
        guard !hasErrors else { return }

        isSaving = true
        saveError = nil

        Task {
            switch mode {
            case .insert:
                await viewModel.insertDocument(jsonText)
                if viewModel.error == nil {
                    if keepOpen {
                        // Strip _id so the next insert gets a fresh ObjectId,
                        // keep the rest of the payload for quick variants.
                        jsonText = Self.removingIdField(from: jsonText)
                        originalText = jsonText
                    } else {
                        dismiss()
                    }
                } else {
                    saveError = viewModel.error
                }
            case .edit(let originalDoc):
                let docId = extractDocumentId(originalDoc)
                await viewModel.updateDocument(id: docId, json: jsonText)
                if viewModel.error == nil {
                    dismiss()
                } else {
                    saveError = viewModel.error
                }
            }
            isSaving = false
        }
    }

    /// Strip the top-level "_id" key from a JSON object string so the next
    /// insertion gets a fresh ObjectId. Returns the input unchanged if it
    /// can't be re-serialized as a dict.
    private static func removingIdField(from json: String) -> String {
        guard let data = json.data(using: .utf8),
              var dict = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [String: Any] else {
            return json
        }
        dict.removeValue(forKey: "_id")
        guard let out = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: out, encoding: .utf8) else {
            return json
        }
        return s
    }
}

// MARK: - Lint issue

struct LintIssue: Identifiable {
    enum Severity { case error, warning, info }
    let id = UUID()
    let severity: Severity
    let message: String
    let line: Int?
    let validator: String?
}
