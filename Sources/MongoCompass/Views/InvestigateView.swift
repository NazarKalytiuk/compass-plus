import SwiftUI

struct InvestigateView: View {
    @Environment(AppViewModel.self) private var viewModel

    enum Tab: String, CaseIterable {
        case slowQueries = "Slow Queries"
        case indexes = "Indexes"
        case validation = "Validation"
    }

    @State private var selectedTab: Tab = .slowQueries
    @State private var profilingLevelPicker: Int = 0
    @State private var slowMsInput = "100"
    @State private var expandedSlowQueryIds: Set<UUID> = []

    // Index creation
    @State private var indexKeysJSON = "{\"field\": 1}"
    @State private var indexUnique = false
    @State private var indexSparse = false

    // Drop index
    @State private var dropIndexName: String?
    @State private var showDropIndexAlert = false

    // Explain
    @State private var explainResult: [String: Any]?
    @State private var showExplainSheet = false
    @State private var isExplaining = false

    // Validation
    @State private var validationRules: [String: Any]?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)

                Spacer()

                if let db = viewModel.activeTab.selectedDatabase,
                   let col = viewModel.activeTab.selectedCollection {
                    Text("\(db).\(col)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                } else if let db = viewModel.activeTab.selectedDatabase {
                    Text(db)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(14)
            .background(Theme.surface.opacity(0.4))

            ThemedDivider()

            switch selectedTab {
            case .slowQueries:
                slowQueriesTab
            case .indexes:
                indexesTab
            case .validation:
                validationTab
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.midnight)
        .onAppear {
            profilingLevelPicker = viewModel.profilingLevel
            slowMsInput = "\(viewModel.slowMs)"
        }
        .alert("Drop Index", isPresented: $showDropIndexAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Drop", role: .destructive) {
                if let name = dropIndexName {
                    Task { await viewModel.dropIndex(name: name) }
                }
            }
        } message: {
            Text("Are you sure you want to drop the index '\(dropIndexName ?? "")'? This action cannot be undone.")
        }
        .sheet(isPresented: $showExplainSheet) {
            explainSheet
        }
    }

    // MARK: - Slow Queries Tab

    private var slowQueriesTab: some View {
        VStack(spacing: 0) {
            // Profiling controls
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profiling Level")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Picker("", selection: $profilingLevelPicker) {
                        Text("0 - Off").tag(0)
                        Text("1 - Slow").tag(1)
                        Text("2 - All").tag(2)
                    }
                    .frame(width: 120)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Slow Query Threshold (ms)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("100", text: $slowMsInput)
                        .textFieldStyle(.themed)
                        .frame(width: 100)
                }

                Button {
                    let ms = Int(slowMsInput) ?? 100
                    Task {
                        await viewModel.setProfilingLevel(profilingLevelPicker, slowMs: ms)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Apply")
                    }
                }
                .buttonStyle(.accentCompact)

                Spacer()

                // Current profiling level display
                HStack(spacing: 6) {
                    Text("Current Level:")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(viewModel.profilingLevel)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(profilingLevelColor(viewModel.profilingLevel))
                }

                Button {
                    Task { await viewModel.fetchSlowQueries() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                        Text("Fetch Slow Queries")
                    }
                }
                .buttonStyle(.accentCompact)
            }
            .padding(14)
            .background(Theme.surface.opacity(0.3))

            ThemedDivider()

            // Slow queries list
            if viewModel.slowQueries.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "tortoise")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.textSecondary)
                    Text("No slow queries")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Enable profiling and fetch slow queries to see them here.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.slowQueries) { entry in
                            slowQueryRow(entry)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private func slowQueryRow(_ entry: SlowQueryEntry) -> some View {
        let isExpanded = expandedSlowQueryIds.contains(entry.id)

        return VStack(alignment: .leading, spacing: 8) {
            // Main row
            HStack(spacing: 12) {
                // Operation badge
                Text(entry.operation)
                    .pillBadge(color: Theme.skyBlue)

                // Namespace
                Text(entry.namespace)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                // Execution time
                Text("\(entry.executionTimeMs) ms")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(executionTimeColor(entry.executionTimeMs))

                // Keys examined
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Keys: \(entry.keysExamined)")
                        .font(.system(size: 10, design: .monospaced))
                    Text("Docs: \(entry.docsExamined)")
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundStyle(Theme.textSecondary)

                // Plan summary
                Text(entry.planSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.amber)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .trailing)

                // Expand/collapse
                Button {
                    if isExpanded {
                        expandedSlowQueryIds.remove(entry.id)
                    } else {
                        expandedSlowQueryIds.insert(entry.id)
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
            }

            // Expanded command JSON
            if isExpanded {
                ThemedDivider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Command")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(entry.command)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                    .padding(8)
                    .background(Theme.midnight)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                }
            }
        }
        .cardStyle(padding: 10, cornerRadius: 8)
    }

    // MARK: - Indexes Tab

    private var indexesTab: some View {
        VStack(spacing: 0) {
            if viewModel.activeTab.selectedCollection == nil {
                VStack(spacing: 16) {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.textSecondary)
                    Text("Select a collection")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Choose a collection from the sidebar to view and manage indexes.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Fetch indexes button & existing indexes
                        existingIndexesSection

                        ThemedDivider()

                        // Create index section
                        createIndexSection

                        ThemedDivider()

                        // Explain query section
                        explainQuerySection
                    }
                    .padding(14)
                }
            }
        }
    }

    private var existingIndexesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("EXISTING INDEXES")
                    .sectionHeaderStyle()

                Spacer()

                Button {
                    Task { await viewModel.fetchIndexes() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Fetch Indexes")
                    }
                }
                .buttonStyle(.accentCompact)
            }

            if viewModel.indexes.isEmpty {
                Text("No indexes loaded. Click Fetch Indexes to load them.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    // Table header
                    HStack(spacing: 0) {
                        Text("Name")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Key")
                            .frame(width: 200, alignment: .leading)
                        Text("Flags")
                            .frame(width: 150, alignment: .leading)
                        Text("Action")
                            .frame(width: 80, alignment: .center)
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Theme.surface)

                    ThemedDivider()

                    ForEach(Array(viewModel.indexes.enumerated()), id: \.offset) { _, index in
                        let name = index["name"] as? String ?? "unknown"
                        let keyDict = index["key"] as? [String: Any] ?? [:]
                        let isUnique = index["unique"] as? Bool ?? false
                        let isSparse = index["sparse"] as? Bool ?? false
                        let keyJSON = formatKeyPattern(keyDict)

                        HStack(spacing: 0) {
                            Text(name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(.white)
                                .font(.system(size: 12, design: .monospaced))

                            Text(keyJSON)
                                .frame(width: 200, alignment: .leading)
                                .foregroundStyle(Theme.textSecondary)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)

                            HStack(spacing: 4) {
                                if isUnique {
                                    Text("Unique")
                                        .pillBadge(color: Theme.amber)
                                }
                                if isSparse {
                                    Text("Sparse")
                                        .pillBadge(color: Theme.skyBlue)
                                }
                            }
                            .frame(width: 150, alignment: .leading)

                            if name != "_id_" {
                                Button {
                                    dropIndexName = name
                                    showDropIndexAlert = true
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(Theme.crimson)
                                }
                                .buttonStyle(.plain)
                                .frame(width: 80)
                            } else {
                                Color.clear
                                    .frame(width: 80)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                    }
                }
                .cardStyle(padding: 0, cornerRadius: 8)
            }
        }
    }

    private var createIndexSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CREATE INDEX")
                .sectionHeaderStyle()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Index Keys (JSON)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("{\"field\": 1}", text: $indexKeysJSON)
                        .textFieldStyle(.themed)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Options")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 12) {
                        Toggle("Unique", isOn: $indexUnique)
                            .toggleStyle(.checkbox)
                        Toggle("Sparse", isOn: $indexSparse)
                            .toggleStyle(.checkbox)
                    }
                    .padding(.vertical, 4)
                }

                Button {
                    createIndexFromInput()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Create")
                    }
                }
                .buttonStyle(.accent)
            }
        }
        .cardStyle()
    }

    private var explainQuerySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EXPLAIN QUERY")
                .sectionHeaderStyle()

            HStack {
                Text("Uses the current tab's filter: ")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text(viewModel.activeTab.filter.isEmpty ? "{}" : viewModel.activeTab.filter)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Button {
                    isExplaining = true
                    Task {
                        let result = await viewModel.explainCurrentQuery()
                        explainResult = result
                        isExplaining = false
                        if result != nil {
                            showExplainSheet = true
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isExplaining {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("Explain")
                    }
                }
                .buttonStyle(.accentCompact)
                .disabled(isExplaining)
            }
        }
        .cardStyle()
    }

    // MARK: - Validation Tab

    private var validationTab: some View {
        VStack(spacing: 0) {
            if viewModel.activeTab.selectedCollection == nil {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.textSecondary)
                    Text("Select a collection")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Choose a collection from the sidebar to view validation rules.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    HStack {
                        Text("SCHEMA VALIDATION")
                            .sectionHeaderStyle()
                        Spacer()

                        Button {
                            Task {
                                let stats = await viewModel.getCollectionStats()
                                if let options = stats?["options"] as? [String: Any],
                                   let validator = options["validator"] as? [String: Any] {
                                    validationRules = validator
                                } else {
                                    validationRules = nil
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Load Rules")
                            }
                        }
                        .buttonStyle(.accentCompact)
                    }

                    if let rules = validationRules {
                        let json = prettyPrintJSON(rules)
                        ScrollView {
                            Text(json)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Theme.midnight)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Theme.border, lineWidth: 1)
                                )
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 36))
                                .foregroundStyle(Theme.textSecondary)
                            Text("No validation rules found")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.textSecondary)
                            Text("Click Load Rules to check for schema validation on this collection.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: - Explain Sheet

    private var explainSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Query Explain Plan")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Done") {
                    showExplainSheet = false
                }
                .buttonStyle(.accent)
            }

            if let result = explainResult {
                ScrollView {
                    Text(prettyPrintJSON(result))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.midnight)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                Text("No explain results available")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }

            Button {
                if let result = explainResult {
                    let json = prettyPrintJSON(result)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(json, forType: .string)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy to Clipboard")
                }
            }
            .buttonStyle(.ghost)
        }
        .padding(20)
        .frame(width: 700, height: 500)
        .background(Theme.surface)
    }

    // MARK: - Helpers

    private func executionTimeColor(_ ms: Int) -> Color {
        if ms < 50 { return Theme.green }
        if ms < 200 { return Theme.amber }
        return Theme.crimson
    }

    private func profilingLevelColor(_ level: Int) -> Color {
        switch level {
        case 0: return Theme.textSecondary
        case 1: return Theme.amber
        case 2: return Theme.crimson
        default: return Theme.textSecondary
        }
    }

    private func formatKeyPattern(_ dict: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    private func createIndexFromInput() {
        guard let data = indexKeysJSON.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        var fields: [String: Int] = [:]
        for (key, value) in parsed {
            if let intVal = value as? Int {
                fields[key] = intVal
            } else if let numVal = value as? NSNumber {
                fields[key] = numVal.intValue
            }
        }

        guard !fields.isEmpty else { return }

        Task {
            await viewModel.createIndex(fields: fields, unique: indexUnique, sparse: indexSparse)
        }
    }
}
