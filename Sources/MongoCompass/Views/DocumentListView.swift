import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct DocumentListView: View {
    @Environment(AppViewModel.self) private var viewModel

    enum ViewMode: String, CaseIterable, Identifiable {
        case tree = "Tree"
        case table = "Table"
        case json = "JSON"
        var id: String { rawValue }
    }

    @State private var viewMode: ViewMode = .tree

    @State private var showInsertSheet = false
    @State private var editingDocument: [String: Any]?
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var deleteDocumentId: String?

    @State private var showStatsPopover = false
    @State private var collectionStats: [String: Any]?

    @State private var showCodeGenSheet = false
    @State private var codeGenLanguage: CodeLanguage = .python

    @State private var isExportingDocuments = false
    @State private var isImportingDocuments = false
    @State private var exportFormat: ExportFormat = .jsonArray
    @State private var importFormat: ImportFormat = .jsonArray
    @State private var importExportError: String?

    @State private var hoveredRowIndex: Int?
    @State private var collapsedDocs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            filterBar
            docsArea
            paginationBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface0)
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
                    Task { await viewModel.deleteDocument(id: id) }
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

    // MARK: - Top toolbar (breadcrumb + pills + view mode + actions)

    private var toolbar: some View {
        HStack(spacing: 8) {
            breadcrumb

            if viewModel.activeTab.selectedCollection != nil {
                Text("collection")
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.surface3)
                    .foregroundStyle(Theme.textSecondary)
                    .clipShape(Capsule())

                if !viewModel.indexes.isEmpty {
                    Text("indexed · \(viewModel.indexes.count)")
                        .pillBadge(.success)
                }
            }

            Spacer()

            Segmented(
                items: ViewMode.allCases,
                label: { Text($0.rawValue) },
                selection: $viewMode
            )

            Button {
                Task {
                    collectionStats = await viewModel.getCollectionStats()
                    showStatsPopover = true
                }
            } label: {
                Image(systemName: "info.circle")
                    .toolbarIconButton()
            }
            .buttonStyle(.plain)
            .help("Collection stats")
            .popover(isPresented: $showStatsPopover) { statsPopover }

            Button {
                showCodeGenSheet = true
            } label: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .toolbarIconButton()
            }
            .buttonStyle(.plain)
            .help("Generate code")

            Menu {
                ForEach(ImportFormat.allCases, id: \.self) { format in
                    Button(format.rawValue) {
                        importFormat = format
                        isImportingDocuments = true
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.to.line")
                        .font(.system(size: 11))
                    Text("Import")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(Theme.textSoft)
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Menu {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Button(format.rawValue) {
                        exportFormat = format
                        isExportingDocuments = true
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 11))
                    Text("Export")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(Theme.textSoft)
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button {
                showInsertSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Insert")
                }
            }
            .buttonStyle(.accentCompact)
            .disabled(viewModel.activeTab.selectedCollection == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface1)
        .shadow(color: Theme.shadowAmbient.opacity(0.6), radius: 0.5, y: 0.5)
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
                    .lineLimit(1)
                if let coll = viewModel.activeTab.selectedCollection {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                    Text(coll)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
            } else {
                Text("Select a collection")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    // MARK: - Filter bar (recessed well with three mono fields)

    private var filterBar: some View {
        @Bindable var viewModel = viewModel
        return HStack(spacing: 6) {
            filterField(label: "filter",
                        placeholder: "{ tier: 'pro' }",
                        text: $viewModel.activeTab.filter,
                        flex: 2.4)
            filterField(label: "sort",
                        placeholder: "{ createdAt: -1 }",
                        text: $viewModel.activeTab.sort,
                        flex: 1.0)
            filterField(label: "project",
                        placeholder: "{ email: 1 }",
                        text: $viewModel.activeTab.projection,
                        flex: 1.4)

            Button {
                viewModel.activeTab.filter = ""
                viewModel.activeTab.sort = ""
                viewModel.activeTab.projection = ""
            } label: {
                Text("Reset")
                    .font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(Theme.textSoft)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await viewModel.refreshDocuments() }
            } label: {
                Text("Find")
            }
            .buttonStyle(.accentCompact)
            .disabled(viewModel.activeTab.selectedCollection == nil)
        }
        .padding(6)
        .background(Theme.surface3)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface1)
    }

    private func filterField(label: String, placeholder: String, text: Binding<String>, flex: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
                .padding(.leading, 10)
                .padding(.trailing, 6)
            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1, height: 18)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 32)
        .background(Color.clear)
        .frame(minWidth: 120 * flex, idealWidth: 200 * flex, maxWidth: .infinity)
        .layoutPriority(flex)
    }

    // MARK: - Docs area

    @ViewBuilder
    private var docsArea: some View {
        if let error = viewModel.error {
            errorBanner(error)
        } else if let error = importExportError {
            errorBanner(error)
        }

        if viewModel.isLoading && viewModel.documents.isEmpty {
            loadingView
        } else if viewModel.activeTab.selectedCollection == nil {
            noCollectionView
        } else if viewModel.documents.isEmpty {
            emptyStateView
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                // Pinned section headers make the table-mode column row sticky.
                LazyVStack(spacing: 10, pinnedViews: [.sectionHeaders]) {
                    documentList
                    if viewModel.isLoading {
                        ForEach(0..<2, id: \.self) { _ in
                            skeletonDocCard()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Theme.surface0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Translucent placeholder card shown beneath the live document list while
    /// pagination/refresh is in flight. Single muted dot-pattern, no values.
    private func skeletonDocCard() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.surface3)
                    .frame(width: 160, height: 16)
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.surface3)
                    .frame(width: 80, height: 14)
            }
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.surface3)
                        .frame(width: 140, height: 12)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.surface3)
                        .frame(maxWidth: 240, maxHeight: 12)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient.opacity(0.4), radius: 4, y: 1)
        .opacity(0.55)
    }

    @ViewBuilder
    private var documentList: some View {
        switch viewMode {
        case .tree:
            ForEach(Array(viewModel.documents.enumerated()), id: \.offset) { index, doc in
                treeDocumentCard(doc: doc, index: index)
            }
        case .table:
            tableView
        case .json:
            jsonModeBody
        }
    }

    // MARK: - JSON mode (single bulk-rendered block with line-number gutter)

    private var jsonModeBody: some View {
        let json = prettyPrintJSONArray(viewModel.documents)
        let lines = json.components(separatedBy: "\n")
        let gutterWidth: CGFloat = max(28, CGFloat(String(lines.count).count) * 9 + 12)

        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .trailing, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, _ in
                    Text("\(idx + 1)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.codeMuted)
                }
            }
            .frame(width: gutterWidth, alignment: .trailing)
            .padding(.vertical, 12)
            .padding(.trailing, 10)
            .background(Theme.codeBg)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    colorizedJSONLine(line)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.codeBg)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
        .contextMenu {
            Button("Copy all") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(json, forType: .string)
            }
        }
    }

    // MARK: - Tree document card

    private func treeDocumentCard(doc: [String: Any], index: Int) -> some View {
        let docId = extractDocumentId(doc)
        let isHovered = hoveredRowIndex == index
        let isOpen = !collapsedDocs.contains(docId)
        let statusPills = detectStatusPills(in: doc)
        let bytes = approximateSize(of: doc)
        let fieldCount = doc.keys.count

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    if isOpen { collapsedDocs.insert(docId) } else { collapsedDocs.remove(docId) }
                } label: {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 18, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: isOpen ? 8 : 0) {
                    HStack(spacing: 8) {
                        Text("_id : \(docId)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.surface3)
                            .foregroundStyle(Theme.textSoft)
                            .clipShape(Capsule())
                            .lineLimit(1)
                            .truncationMode(.middle)

                        ForEach(statusPills) { pill in
                            Text(pill.label).pillBadge(pill.kind)
                        }

                        Text("\(fieldCount) field\(fieldCount == 1 ? "" : "s") · \(formatBytes(bytes)) · \(viewModel.indexes.isEmpty ? "no index" : "indexed")")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.textMuted)

                        Spacer(minLength: 0)

                        rowActions(doc: doc, docId: docId)
                            .opacity(isHovered ? 1 : 0)
                    }

                    if isOpen {
                        kvTree(doc)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient.opacity(isHovered ? 1.0 : 0.7),
                radius: isHovered ? 10 : 6,
                y: isHovered ? 3 : 2)
        .onHover { hovering in
            hoveredRowIndex = hovering ? index : (hoveredRowIndex == index ? nil : hoveredRowIndex)
        }
        .contextMenu {
            Button("Edit") { editingDocument = doc; showEditSheet = true }
            Button("Copy JSON") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prettyPrintJSON(doc), forType: .string)
            }
            Button("Delete", role: .destructive) {
                deleteDocumentId = docId; showDeleteAlert = true
            }
        }
    }

    private func rowActions(doc: [String: Any], docId: String) -> some View {
        HStack(spacing: 2) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prettyPrintJSON(doc), forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .toolbarIconButton()
            }
            .buttonStyle(.plain)
            .help("Copy JSON")

            Button {
                editingDocument = doc
                showEditSheet = true
            } label: {
                Image(systemName: "pencil")
                    .toolbarIconButton()
            }
            .buttonStyle(.plain)
            .help("Edit")

            Button {
                deleteDocumentId = docId
                showDeleteAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.danger)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
    }

    // MARK: - KV tree

    private func kvTree(_ doc: [String: Any], indent: Int = 0) -> AnyView {
        let ordered = orderedDocKeys(Array(doc.keys))
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ordered, id: \.self) { key in
                    kvRow(key: key, value: doc[key] as Any, indent: indent)
                }
            }
        )
    }

    private func kvRow(key: String, value: Any, indent: Int) -> AnyView {
        AnyView(
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\"\(key)\"")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(red: 0.122, green: 0.302, blue: 0.549))
                    .frame(width: 200, alignment: .leading)

                kvValue(value, atIndent: indent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
    }

    private func kvValue(_ value: Any, atIndent indent: Int) -> AnyView {
        AnyView(_kvValueContent(value, atIndent: indent))
    }

    @ViewBuilder
    private func _kvValueContent(_ value: Any, atIndent indent: Int) -> some View {
        switch value {
        case let s as String:
            HStack(spacing: 6) {
                Text("\"\(s)\"")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.successDeep)
                    .lineLimit(2)
                    .truncationMode(.tail)
                typeTag("string")
            }
        case let n as NSNumber where !isBool(n):
            HStack(spacing: 6) {
                Text(formatNumber(n))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.warningDeep)
                typeTag(n.stringValue.contains(".") ? "double" : "int32")
            }
        case let b as Bool:
            HStack(spacing: 6) {
                Text(b ? "true" : "false")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.violetDeep)
                typeTag("bool")
            }
        case let dict as [String: Any]:
            if indent >= 1 {
                Text("{ \(dict.keys.count) field\(dict.keys.count == 1 ? "" : "s") }")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("{ \(dict.keys.count) field\(dict.keys.count == 1 ? "" : "s") }")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                    nestedBlock {
                        kvTree(dict, indent: indent + 1)
                    }
                }
            }
        case let arr as [Any]:
            if indent >= 1 {
                Text("[ \(arr.count) item\(arr.count == 1 ? "" : "s") ]")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("[ \(arr.count) item\(arr.count == 1 ? "" : "s") ]")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                    nestedBlock {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(arr.enumerated()), id: \.offset) { idx, item in
                                kvRow(key: "\(idx)", value: item, indent: indent + 1)
                            }
                        }
                    }
                }
            }
        case is NSNull:
            HStack(spacing: 6) {
                Text("null")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }
        default:
            let raw = stringValue(value)
            if raw.hasPrefix("20") && raw.count > 8, raw.contains("T") || raw.contains("-") {
                // ISO-like date string
                HStack(spacing: 0) {
                    Text("ISODate(").foregroundStyle(Theme.violetDeep)
                    Text("\"\(raw)\"").foregroundStyle(Theme.successDeep)
                    Text(")").foregroundStyle(Theme.violetDeep)
                }
                .font(.system(size: 12, design: .monospaced))
            } else {
                Text(raw)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSoft)
            }
        }
    }

    private func nestedBlock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1)
                .padding(.leading, 6)
                .padding(.vertical, 2)
            content()
                .padding(.leading, 12)
        }
    }

    private func typeTag(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(Theme.textMuted)
    }

    // MARK: - JSON document card (full prettyprinted code surface)

    private func jsonDocumentCard(doc: [String: Any], index: Int) -> some View {
        let docId = extractDocumentId(doc)
        let json = prettyPrintJSON(doc)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("_id : \(docId)")
                    .font(.system(size: 11.5, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.surface3)
                    .foregroundStyle(Theme.textSoft)
                    .clipShape(Capsule())

                Spacer()

                rowActions(doc: doc, docId: docId)
            }

            syntaxHighlightedJSON(json)
                .frame(maxWidth: .infinity, alignment: .leading)
                .codeSurface(padding: 12, cornerRadius: 8)
        }
        .padding(14)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
    }

    // MARK: - Table view

    @ViewBuilder
    private var tableView: some View {
        let allKeys = collectAllKeys()
        let displayKeys = orderedTableKeys(from: allKeys)

        Section {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(viewModel.documents.enumerated()), id: \.offset) { index, doc in
                    tableRow(doc: doc, index: index, displayKeys: displayKeys)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface1)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 8,
                    bottomTrailingRadius: 8,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
            .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
        } header: {
            HStack(spacing: 0) {
                Color.clear.frame(width: 28)
                ForEach(displayKeys, id: \.self) { key in
                    Text(key == "_id" ? "_ID" : key)
                        .sectionHeaderStyle()
                        .frame(minWidth: minWidth(for: key), alignment: .leading)
                        .padding(.horizontal, 10)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surface3)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 8,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 8,
                    style: .continuous
                )
            )
        }
    }

    private func tableRow(doc: [String: Any], index: Int, displayKeys: [String]) -> some View {
        let isHovered = hoveredRowIndex == index
        let docId = extractDocumentId(doc)

        return HStack(spacing: 0) {
            Color.clear.frame(width: 28)
            ForEach(displayKeys, id: \.self) { key in
                tableCell(key: key, value: doc[key])
                    .frame(minWidth: minWidth(for: key), alignment: .leading)
                    .padding(.horizontal, 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .background(
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(isHovered ? Theme.primaryTint : Color.clear)
                if isHovered {
                    Rectangle().fill(Theme.primary).frame(width: 3)
                }
            }
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredRowIndex = hovering ? index : (hoveredRowIndex == index ? nil : hoveredRowIndex)
        }
        .contextMenu {
            Button("Edit") { editingDocument = doc; showEditSheet = true }
            Button("Copy JSON") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prettyPrintJSON(doc), forType: .string)
            }
            Button("Delete", role: .destructive) {
                deleteDocumentId = docId; showDeleteAlert = true
            }
        }
    }

    @ViewBuilder
    private func tableCell(key: String, value: Any?) -> some View {
        if key == "_id" {
            Text(stringValue(value))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } else if key.lowercased() == "status" {
            statusPill(for: stringValue(value))
        } else if isDateLike(key: key, value: value) {
            Text(formatDateLike(stringValue(value)))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        } else {
            tableValueCell(value)
        }
    }

    @ViewBuilder
    private func tableValueCell(_ value: Any?) -> some View {
        switch value {
        case nil, is NSNull:
            Text("null")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
                .italic()
                .lineLimit(1)
        case let n as NSNumber where isBool(n):
            Text(n.boolValue ? "true" : "false").pillBadge(.violet)
        case let b as Bool:
            Text(b ? "true" : "false").pillBadge(.violet)
        case let n as NSNumber:
            Text(formatNumber(n))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.warningDeep)
                .lineLimit(1)
        case let s as String:
            Text(s)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.successDeep)
                .lineLimit(1)
                .truncationMode(.tail)
        case let dict as [String: Any]:
            Text("{ \(dict.keys.count) field\(dict.keys.count == 1 ? "" : "s") }")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
        case let arr as [Any]:
            Text("[ \(arr.count) item\(arr.count == 1 ? "" : "s") ]")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
        default:
            Text(stringValue(value))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
    }

    private func statusPill(for raw: String) -> some View {
        let normalized = raw.uppercased()
        let kind: BadgeKind
        switch normalized {
        case "ACTIVE", "TRUE", "ENABLED", "SUCCESS", "OK", "ONLINE":
            kind = .success
        case "PENDING", "WAITING", "PROCESSING":
            kind = .warning
        case "INACTIVE", "DISABLED", "ERROR", "FAILED", "FALSE", "OFFLINE":
            kind = .danger
        case "INFO", "DRAFT":
            kind = .info
        default:
            kind = .neutral
        }
        return Text(normalized.isEmpty ? "—" : normalized).pillBadge(kind)
    }

    private func minWidth(for key: String) -> CGFloat {
        switch key.lowercased() {
        case "_id":    return 140
        case "status": return 100
        case "email":  return 200
        case "name":   return 160
        default:
            let l = key.lowercased()
            if l.contains("date") || l.contains("at") || l.contains("time") { return 140 }
            return 140
        }
    }

    private func orderedTableKeys(from keys: [String]) -> [String] {
        let priority = ["_id", "name", "email", "createdAt", "created_at", "created", "updatedAt", "updated_at", "status"]
        var ordered: [String] = []
        var seen = Set<String>()
        for p in priority {
            if let match = keys.first(where: { $0.lowercased() == p.lowercased() }), !seen.contains(match) {
                ordered.append(match); seen.insert(match)
            }
        }
        for k in keys where !seen.contains(k) {
            ordered.append(k); seen.insert(k)
        }
        return ordered
    }

    private func isDateLike(key: String, value: Any?) -> Bool {
        let lower = key.lowercased()
        return lower.contains("date") || lower.contains("_at") || lower.contains("time") || lower == "created" || lower == "updated"
    }

    private func formatDateLike(_ s: String) -> String {
        if let tIdx = s.firstIndex(of: "T") { return String(s[s.startIndex..<tIdx]) }
        return s
    }

    // MARK: - Pagination

    private var paginationBar: some View {
        @Bindable var viewModel = viewModel
        let limit = max(viewModel.activeTab.limit, 1)
        let totalPages = viewModel.documentCount == 0 ? 1 : Int(ceil(Double(viewModel.documentCount) / Double(limit)))
        let currentPage = (viewModel.activeTab.skip / limit) + 1
        let start = viewModel.documentCount == 0 ? 0 : viewModel.activeTab.skip + 1
        let end = min(viewModel.activeTab.skip + viewModel.documents.count, viewModel.documentCount)

        return HStack(spacing: 12) {
            if viewModel.documentCount > 0 {
                HStack(spacing: 4) {
                    Text("Showing")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(start)–\(end)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                    Text("of")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Text(viewModel.documentCount.formatted())
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                    Text("matched")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                Text("No results")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }

            Spacer()

            Text("Page size")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textMuted)

            Segmented(
                items: [10, 25, 50, 100],
                label: { Text("\($0)") },
                selection: Binding(
                    get: { viewModel.activeTab.limit },
                    set: { newLimit in
                        viewModel.activeTab.limit = newLimit
                        viewModel.activeTab.skip = 0
                        Task { await viewModel.refreshDocuments() }
                    }
                )
            )

            HStack(spacing: 0) {
                Button {
                    viewModel.previousPage()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Text("Prev").font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .foregroundStyle(viewModel.activeTab.skip == 0 ? Theme.textMuted : Theme.textSoft)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.activeTab.skip == 0)

                Text("\(currentPage) / \(totalPages)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 8)

                Button {
                    viewModel.nextPage()
                } label: {
                    HStack(spacing: 3) {
                        Text("Next").font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .foregroundStyle(viewModel.activeTab.skip + viewModel.activeTab.limit >= viewModel.documentCount ? Theme.textMuted : Theme.textSoft)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.activeTab.skip + viewModel.activeTab.limit >= viewModel.documentCount)
            }
            .padding(2)
            .background(Theme.surface3)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface1)
    }

    // MARK: - State views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text("Loading documents…")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface0)
    }

    private var noCollectionView: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.primaryTint)
                    .frame(width: 56, height: 56)
                Image(systemName: "tray")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.primaryDeep)
            }
            Text("Select a collection")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Choose a database and collection from the sidebar to view documents.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Theme.surface0)
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.primaryTint)
                    .frame(width: 56, height: 56)
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.primaryDeep)
            }
            Text("No documents found")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Try adjusting your filter or insert a new document.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
            Button {
                showInsertSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                    Text("Insert Document")
                }
            }
            .buttonStyle(.accent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Theme.surface0)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.dangerDeep)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.dangerDeep)
                .lineLimit(2)
            Spacer()
            Button {
                viewModel.error = nil
                importExportError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.dangerDeep.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.dangerTint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Stats popover

    private var statsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Collection Stats")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

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
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            } else {
                Text("Loading…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(Theme.surface1)
    }

    // MARK: - Code gen sheet

    private var codeGenerationSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Generate Code")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Done") { showCodeGenSheet = false }
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .codeSurface(padding: 14, cornerRadius: 8)
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
        .background(Theme.surface0)
    }

    // MARK: - Syntax highlighted JSON (used by JSON view mode)

    private func syntaxHighlightedJSON(_ json: String) -> some View {
        let lines = json.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                colorizedJSONLine(line)
            }
        }
    }

    private func colorizedJSONLine(_ line: String) -> some View {
        var parts: [(String, Color)] = []
        var remaining = line[line.startIndex...]

        while !remaining.isEmpty {
            if let quoteStart = remaining.firstIndex(of: "\"") {
                if quoteStart > remaining.startIndex {
                    parts.append((String(remaining[remaining.startIndex..<quoteStart]), Theme.codeFg))
                }
                let afterQuote = remaining.index(after: quoteStart)
                if afterQuote < remaining.endIndex,
                   let closeQuote = remaining[afterQuote...].firstIndex(of: "\"") {
                    let content = String(remaining[quoteStart...closeQuote])
                    let afterClose = remaining.index(after: closeQuote)
                    let restAfterClose = remaining[afterClose...]
                    let trimmed = restAfterClose.drop(while: { $0 == " " })
                    if trimmed.first == ":" {
                        parts.append((content, Theme.codeKey))
                    } else {
                        parts.append((content, Theme.codeString))
                    }
                    remaining = remaining[afterClose...]
                } else {
                    parts.append((String(remaining), Theme.codeFg))
                    remaining = remaining[remaining.endIndex...]
                }
            } else {
                let text = String(remaining)
                parts.append(contentsOf: colorizeNonStringTokens(text))
                remaining = remaining[remaining.endIndex...]
            }
        }

        return HStack(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
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
            return [(text, Theme.codeFg)]
        }

        var lastEnd = 0
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: scanner.length))
        for match in matches {
            if match.range.location > lastEnd {
                let prefix = scanner.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                results.append((prefix, Theme.codeFg))
            }
            let matched = scanner.substring(with: match.range)
            if matched == "true" || matched == "false" {
                results.append((matched, Theme.codeBool))
            } else if matched == "null" {
                results.append((matched, Theme.codeMuted))
            } else {
                results.append((matched, Theme.codeNumber))
            }
            lastEnd = match.range.location + match.range.length
        }
        if lastEnd < scanner.length {
            let suffix = scanner.substring(from: lastEnd)
            results.append((suffix, Theme.codeFg))
        }
        return results
    }

    // MARK: - Helpers

    private func collectAllKeys() -> [String] {
        var set = Set<String>()
        for doc in viewModel.documents { set.formUnion(doc.keys) }
        var sorted = set.sorted()
        if let idx = sorted.firstIndex(of: "_id") {
            sorted.remove(at: idx); sorted.insert("_id", at: 0)
        }
        return sorted
    }

    private func orderedDocKeys(_ keys: [String]) -> [String] {
        let priority = ["_id", "email", "name", "tier", "status", "createdAt", "updatedAt", "lastLoginAt"]
        var ordered: [String] = []
        var seen = Set<String>()
        for p in priority {
            if let match = keys.first(where: { $0.lowercased() == p.lowercased() }), !seen.contains(match) {
                ordered.append(match); seen.insert(match)
            }
        }
        for k in keys where !seen.contains(k) {
            ordered.append(k); seen.insert(k)
        }
        return ordered
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

    // MARK: - Auto-detected status pills for tree card head row

    private struct DetectedPill: Identifiable {
        let id = UUID()
        let label: String
        let kind: BadgeKind
    }

    private func detectStatusPills(in doc: [String: Any]) -> [DetectedPill] {
        var out: [DetectedPill] = []
        if let tier = doc["tier"] as? String {
            out.append(DetectedPill(label: "tier · \(tier)", kind: .accent))
        }
        if let role = doc["role"] as? String, out.count < 3 {
            out.append(DetectedPill(label: role, kind: .violet))
        }
        if let status = doc["status"] as? String, out.count < 3 {
            let kind: BadgeKind
            switch status.lowercased() {
            case "active", "ok", "online", "success":      kind = .success
            case "pending", "waiting", "processing":       kind = .warning
            case "inactive", "disabled", "error", "failed":kind = .danger
            case "trialing", "draft":                      kind = .info
            default:                                       kind = .neutral
            }
            out.append(DetectedPill(label: status, kind: kind))
        }
        if let verified = doc["verified"] as? Bool, !verified, out.count < 3 {
            out.append(DetectedPill(label: "2FA pending", kind: .warning))
        }
        if out.count < 3, isFutureDate(doc["trialEndsAt"]) {
            out.append(DetectedPill(label: "trialing", kind: .info))
        }
        return out
    }

    /// Treat ISO-8601 strings and `Date` values uniformly. Returns true iff
    /// the value parses to a moment later than now (i.e. an active trial).
    private func isFutureDate(_ value: Any?) -> Bool {
        guard let value else { return false }
        let now = Date()
        if let date = value as? Date {
            return date > now
        }
        if let str = value as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: str), d > now { return true }
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: str), d > now { return true }
        }
        return false
    }

    private func approximateSize(of doc: [String: Any]) -> Int {
        guard let data = try? JSONSerialization.data(withJSONObject: doc, options: []) else { return 0 }
        return data.count
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }

    private func isBool(_ n: NSNumber) -> Bool {
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    private func formatNumber(_ n: NSNumber) -> String {
        let s = n.stringValue
        if let intVal = Int(s), abs(intVal) >= 1000 {
            return intVal.formatted()
        }
        return s
    }
}

// MARK: - Segmented control

struct Segmented<Item: Hashable & Identifiable, Label: View>: View {
    let items: [Item]
    let label: (Item) -> Label
    @Binding var selection: Item

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                Button {
                    selection = item
                } label: {
                    label(item)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .foregroundStyle(selection == item ? Theme.textPrimary : Theme.textSecondary)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(selection == item ? Theme.surface1 : Color.clear)
                                .shadow(color: selection == item ? Theme.shadowAmbient.opacity(0.6) : .clear,
                                        radius: 1, y: 0.5)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.surface3)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// Specialization for Int (used by page-size selector).
extension Int: @retroactive Identifiable {
    public var id: Int { self }
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

// MARK: - Free helpers (shared)

func prettyPrintJSON(_ dict: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
          let string = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return string
}

func prettyPrintJSONArray(_ docs: [[String: Any]]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: docs, options: [.prettyPrinted, .sortedKeys]),
          let string = String(data: data, encoding: .utf8) else {
        return "[]"
    }
    return string
}

func extractDocumentId(_ doc: [String: Any]) -> String {
    if let id = doc["_id"] { return stringValue(id) }
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
