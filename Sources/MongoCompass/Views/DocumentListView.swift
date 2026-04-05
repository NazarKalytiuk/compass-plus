import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct DocumentListView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var showInsertSheet = false
    @State private var editingDocument: [String: Any]?
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var deleteDocumentId: String?
    @State private var viewMode: ViewMode = .cards
    @State private var showStatsPopover = false
    @State private var collectionStats: [String: Any]?
    @State private var showCodeGenSheet = false
    @State private var codeGenLanguage: CodeLanguage = .python
    @State private var showExportFormatMenu = false
    @State private var showImportFormatMenu = false
    @State private var isExportingDocuments = false
    @State private var isImportingDocuments = false
    @State private var exportFormat: ExportFormat = .jsonArray
    @State private var importFormat: ImportFormat = .jsonArray
    @State private var importExportError: String?

    enum ViewMode {
        case cards, table
    }

    var body: some View {
        VStack(spacing: 0) {
            queryBar
            ThemedDivider()
            toolbarRow
            ThemedDivider()

            if let error = viewModel.error {
                errorBanner(error)
            }

            if let error = importExportError {
                errorBanner(error)
            }

            if viewModel.isLoading {
                loadingView
            } else if viewModel.activeTab.selectedCollection == nil {
                noCollectionView
            } else if viewModel.documents.isEmpty {
                emptyStateView
            } else {
                documentDisplayArea
            }

            ThemedDivider()
            paginationBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.midnight)
        .sheet(isPresented: $showInsertSheet) {
            DocumentEditorView(mode: .insert)
        }
        .sheet(isPresented: $showEditSheet) {
            if let doc = editingDocument {
                DocumentEditorView(mode: .edit(doc))
            }
        }
        .sheet(isPresented: $showCodeGenSheet) {
            codeGenerationSheet
        }
        .alert("Delete Document", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let id = deleteDocumentId {
                    Task {
                        await viewModel.deleteDocument(id: id)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this document? This action cannot be undone.")
        }
        .fileExporter(
            isPresented: $isExportingDocuments,
            document: DocumentsExportDocument(documents: viewModel.documents, format: exportFormat),
            contentType: exportFormat == .csv ? .commaSeparatedText : .json,
            defaultFilename: "export.\(exportFormat == .csv ? "csv" : "json")"
        ) { result in
            if case .failure(let error) = result {
                importExportError = "Export failed: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $isImportingDocuments,
            allowedContentTypes: [.json, .commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    // MARK: - Query Bar

    private var queryBar: some View {
        @Bindable var viewModel = viewModel
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Filter")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("{\"field\": \"value\"}", text: $viewModel.activeTab.filter)
                        .textFieldStyle(.themed)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sort")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("{\"field\": 1}", text: $viewModel.activeTab.sort)
                        .textFieldStyle(.themed)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Projection")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("{\"field\": 1}", text: $viewModel.activeTab.projection)
                        .textFieldStyle(.themed)
                }
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Skip")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("0", value: $viewModel.activeTab.skip, format: .number)
                        .textFieldStyle(.themed)
                        .frame(width: 80)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Limit")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("20", value: $viewModel.activeTab.limit, format: .number)
                        .textFieldStyle(.themed)
                        .frame(width: 80)
                }

                Spacer()

                Button {
                    viewModel.activeTab.filter = ""
                    viewModel.activeTab.sort = ""
                    viewModel.activeTab.projection = ""
                    viewModel.activeTab.skip = 0
                    viewModel.activeTab.limit = 20
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset")
                    }
                }
                .buttonStyle(.ghost)

                Button {
                    Task {
                        await viewModel.refreshDocuments()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                        Text("Find")
                    }
                }
                .buttonStyle(.accent)
            }
        }
        .padding(14)
        .background(Theme.surface.opacity(0.4))
    }

    // MARK: - Toolbar Row

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            // Insert
            Button {
                showInsertSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .toolbarIconButton()
            .buttonStyle(.plain)
            .help("Insert Document")

            // Export menu
            Menu {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Button(format.rawValue) {
                        exportFormat = format
                        isExportingDocuments = true
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .toolbarIconButton()
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)
            .help("Export Documents")

            // Import menu
            Menu {
                ForEach(ImportFormat.allCases, id: \.self) { format in
                    Button(format.rawValue) {
                        importFormat = format
                        isImportingDocuments = true
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .toolbarIconButton()
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)
            .help("Import Documents")

            // Stats
            Button {
                Task {
                    collectionStats = await viewModel.getCollectionStats()
                    showStatsPopover = true
                }
            } label: {
                Image(systemName: "info.circle")
            }
            .toolbarIconButton()
            .buttonStyle(.plain)
            .help("Collection Stats")
            .popover(isPresented: $showStatsPopover) {
                statsPopover
            }

            // Code generation
            Button {
                showCodeGenSheet = true
            } label: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            }
            .toolbarIconButton()
            .buttonStyle(.plain)
            .help("Generate Code")

            Spacer()

            // Document count
            Text("\(viewModel.documents.count) of \(viewModel.documentCount) documents")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)

            // View mode toggle
            HStack(spacing: 2) {
                Button {
                    viewMode = .cards
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .toolbarIconButton(isActive: viewMode == .cards)
                .buttonStyle(.plain)

                Button {
                    viewMode = .table
                } label: {
                    Image(systemName: "tablecells")
                }
                .toolbarIconButton(isActive: viewMode == .table)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surface.opacity(0.3))
    }

    // MARK: - Document Display

    @ViewBuilder
    private var documentDisplayArea: some View {
        switch viewMode {
        case .cards:
            cardView
        case .table:
            tableView
        }
    }

    // MARK: - Card View

    private var cardView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(viewModel.documents.enumerated()), id: \.offset) { index, doc in
                    documentCard(doc, index: index)
                }
            }
            .padding(14)
        }
    }

    private func documentCard(_ doc: [String: Any], index: Int) -> some View {
        let docId = extractDocumentId(doc)
        let jsonString = prettyPrintJSON(doc)

        return VStack(alignment: .leading, spacing: 8) {
            // Header with _id
            HStack {
                HStack(spacing: 6) {
                    Text("_id:")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.green)
                    Text(docId)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer()

                // Actions
                HStack(spacing: 4) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(jsonString, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .toolbarIconButton()
                    .buttonStyle(.plain)
                    .help("Copy JSON")

                    Button {
                        editingDocument = doc
                        showEditSheet = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .toolbarIconButton()
                    .buttonStyle(.plain)
                    .help("Edit Document")

                    Button {
                        deleteDocumentId = docId
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Theme.crimson)
                    }
                    .toolbarIconButton()
                    .buttonStyle(.plain)
                    .help("Delete Document")
                }
            }

            ThemedDivider()

            // JSON body with syntax highlighting
            syntaxHighlightedJSON(jsonString)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle(padding: 12, cornerRadius: 8)
    }

    // MARK: - Syntax Highlighted JSON

    private func syntaxHighlightedJSON(_ json: String) -> some View {
        let lines = json.components(separatedBy: "\n")

        return VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                colorizedJSONLine(line)
            }
        }
    }

    private func colorizedJSONLine(_ line: String) -> some View {
        // Simple syntax highlighting: keys in green, strings in sky blue, numbers in amber, booleans in crimson
        var attributedParts: [(String, Color)] = []
        var remaining = line[line.startIndex...]

        while !remaining.isEmpty {
            // Try to match a key (e.g. "key":)
            if let quoteStart = remaining.firstIndex(of: "\"") {
                // Add any preceding text
                if quoteStart > remaining.startIndex {
                    let prefix = String(remaining[remaining.startIndex..<quoteStart])
                    attributedParts.append((prefix, Theme.textSecondary))
                }

                let afterQuote = remaining.index(after: quoteStart)
                if afterQuote < remaining.endIndex,
                   let closeQuote = remaining[afterQuote...].firstIndex(of: "\"") {
                    let content = String(remaining[quoteStart...closeQuote])
                    let afterClose = remaining.index(after: closeQuote)

                    // Check if this is a key (followed by :)
                    let restAfterClose = remaining[afterClose...]
                    let trimmed = restAfterClose.drop(while: { $0 == " " })
                    if trimmed.first == ":" {
                        attributedParts.append((content, Theme.green))
                    } else {
                        attributedParts.append((content, Theme.skyBlue))
                    }

                    remaining = remaining[afterClose...]
                } else {
                    // No closing quote found
                    attributedParts.append((String(remaining), Theme.textSecondary))
                    remaining = remaining[remaining.endIndex...]
                }
            } else {
                // No more quotes; colorize numbers, booleans, null
                let text = String(remaining)
                attributedParts.append(contentsOf: colorizeNonStringTokens(text))
                remaining = remaining[remaining.endIndex...]
            }
        }

        return HStack(spacing: 0) {
            ForEach(Array(attributedParts.enumerated()), id: \.offset) { _, part in
                Text(part.0)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(part.1)
            }
        }
    }

    private func colorizeNonStringTokens(_ text: String) -> [(String, Color)] {
        var results: [(String, Color)] = []
        let scanner = text as NSString
        let pattern = #"(true|false|null|(\-?\d+\.?\d*([eE][+-]?\d+)?))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [(text, Theme.textSecondary)]
        }

        var lastEnd = 0
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: scanner.length))
        for match in matches {
            if match.range.location > lastEnd {
                let prefix = scanner.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                results.append((prefix, Theme.textSecondary))
            }
            let matched = scanner.substring(with: match.range)
            if matched == "true" || matched == "false" {
                results.append((matched, Theme.crimson))
            } else if matched == "null" {
                results.append((matched, Theme.amber))
            } else {
                results.append((matched, Theme.amber))
            }
            lastEnd = match.range.location + match.range.length
        }
        if lastEnd < scanner.length {
            let suffix = scanner.substring(from: lastEnd)
            results.append((suffix, Theme.textSecondary))
        }
        return results
    }

    // MARK: - Table View

    private var tableView: some View {
        let allKeys = collectAllKeys()

        return ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    Text("#")
                        .frame(width: 40, alignment: .center)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)

                    ForEach(allKeys, id: \.self) { key in
                        Text(key)
                            .frame(minWidth: 120, alignment: .leading)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.green)
                            .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 8)
                .background(Theme.surface)

                ThemedDivider()

                // Data rows
                ForEach(Array(viewModel.documents.enumerated()), id: \.offset) { index, doc in
                    HStack(spacing: 0) {
                        Text("\(viewModel.activeTab.skip + index + 1)")
                            .frame(width: 40, alignment: .center)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)

                        ForEach(allKeys, id: \.self) { key in
                            let value = doc[key]
                            Text(stringValue(value))
                                .frame(minWidth: 120, alignment: .leading)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 6)
                    .background(index % 2 == 0 ? Color.clear : Theme.surface.opacity(0.3))
                    .contextMenu {
                        Button("Edit") {
                            editingDocument = doc
                            showEditSheet = true
                        }
                        Button("Copy JSON") {
                            let json = prettyPrintJSON(doc)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(json, forType: .string)
                        }
                        Button("Delete", role: .destructive) {
                            deleteDocumentId = extractDocumentId(doc)
                            showDeleteAlert = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pagination Bar

    private var paginationBar: some View {
        HStack {
            Button {
                viewModel.previousPage()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Previous")
                }
            }
            .buttonStyle(.ghost)
            .disabled(viewModel.activeTab.skip == 0)

            Spacer()

            if viewModel.documentCount > 0 {
                let start = viewModel.activeTab.skip + 1
                let end = min(viewModel.activeTab.skip + viewModel.documents.count, viewModel.documentCount)
                Text("Showing \(start)-\(end) of \(viewModel.documentCount) documents")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button {
                viewModel.nextPage()
            } label: {
                HStack(spacing: 4) {
                    Text("Next")
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(.ghost)
            .disabled(viewModel.activeTab.skip + viewModel.activeTab.limit >= viewModel.documentCount)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surface.opacity(0.3))
    }

    // MARK: - Stats Popover

    private var statsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Collection Stats")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)

            ThemedDivider()

            if let stats = collectionStats {
                ForEach(Array(stats.keys.sorted()), id: \.self) { key in
                    HStack {
                        Text(key)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(stringValue(stats[key]))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
            } else {
                Text("Loading...")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(16)
        .frame(width: 350)
        .background(Theme.surface)
    }

    // MARK: - Code Generation Sheet

    private var codeGenerationSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Generate Code")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Done") {
                    showCodeGenSheet = false
                }
                .buttonStyle(.accent)
            }

            Picker("Language", selection: $codeGenLanguage) {
                ForEach(CodeLanguage.allCases, id: \.self) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.segmented)

            let code = viewModel.generateFindCode(language: codeGenLanguage)

            ScrollView {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.midnight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy to Clipboard")
                }
            }
            .buttonStyle(.ghost)
        }
        .padding(20)
        .frame(width: 600, height: 450)
        .background(Theme.surface)
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading documents...")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noCollectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
            Text("Select a collection")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text("Choose a database and collection from the sidebar to view documents.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
            Text("No documents found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text("Try adjusting your filter or insert a new document.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)

            Button {
                showInsertSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Insert Document")
                }
            }
            .buttonStyle(.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.crimson)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.crimson)
                .lineLimit(2)
            Spacer()
            Button {
                viewModel.error = nil
                importExportError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.crimson.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Theme.crimson.opacity(0.1))
    }

    // MARK: - Helpers

    private func collectAllKeys() -> [String] {
        var keySet = Set<String>()
        for doc in viewModel.documents {
            for key in doc.keys {
                keySet.insert(key)
            }
        }
        var sorted = keySet.sorted()
        // Move _id to front
        if let idIndex = sorted.firstIndex(of: "_id") {
            sorted.remove(at: idIndex)
            sorted.insert("_id", at: 0)
        }
        return sorted
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    try await viewModel.importDocuments(format: importFormat, from: url)
                } catch {
                    importExportError = "Import failed: \(error.localizedDescription)"
                }
            }
        case .failure(let error):
            importExportError = "Import failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Documents Export Document (for fileExporter)

struct DocumentsExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }

    let data: Data

    init(documents: [[String: Any]], format: ExportFormat) {
        switch format {
        case .jsonArray:
            self.data = (try? JSONSerialization.data(
                withJSONObject: documents,
                options: [.prettyPrinted, .sortedKeys]
            )) ?? Data()
        case .ndjson:
            let lines = documents.compactMap { doc -> String? in
                guard let data = try? JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys]) else { return nil }
                return String(data: data, encoding: .utf8)
            }
            self.data = lines.joined(separator: "\n").data(using: .utf8) ?? Data()
        case .csv:
            var keys = Set<String>()
            for doc in documents { keys.formUnion(doc.keys) }
            let sortedKeys = keys.sorted()
            var csvLines = [sortedKeys.joined(separator: ",")]
            for doc in documents {
                let row = sortedKeys.map { key -> String in
                    let val = stringValue(doc[key])
                    if val.contains(",") || val.contains("\"") || val.contains("\n") {
                        return "\"\(val.replacingOccurrences(of: "\"", with: "\"\""))\""
                    }
                    return val
                }
                csvLines.append(row.joined(separator: ","))
            }
            self.data = csvLines.joined(separator: "\n").data(using: .utf8) ?? Data()
        }
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Free Functions (shared helpers)

func prettyPrintJSON(_ dict: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
          let string = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return string
}

func extractDocumentId(_ doc: [String: Any]) -> String {
    if let id = doc["_id"] {
        return stringValue(id)
    }
    return "unknown"
}

func stringValue(_ value: Any?) -> String {
    guard let value = value else { return "null" }
    switch value {
    case let str as String:
        return str
    case let num as NSNumber:
        return num.stringValue
    case let bool as Bool:
        return bool ? "true" : "false"
    case let dict as [String: Any]:
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{...}"
    case let arr as [Any]:
        if let data = try? JSONSerialization.data(withJSONObject: arr, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "[...]"
    default:
        return "\(value)"
    }
}
