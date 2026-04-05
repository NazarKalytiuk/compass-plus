import SwiftUI

struct QueryLogView: View {
    @Environment(AppViewModel.self) private var viewModel

    enum Tab: String, CaseIterable {
        case history = "History"
        case saved = "Saved Queries"
    }

    @State private var selectedTab: Tab = .history
    @State private var filterOperation: QueryLogEntry.OperationType? = nil
    @State private var searchText = ""
    @State private var deleteQueryId: UUID?
    @State private var showDeleteAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // Segmented picker header
            HStack {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                Spacer()

                if selectedTab == .history {
                    Button {
                        viewModel.clearQueryLog()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Clear History")
                        }
                    }
                    .buttonStyle(.ghost)
                }
            }
            .padding(14)
            .background(Theme.surface.opacity(0.4))

            ThemedDivider()

            switch selectedTab {
            case .history:
                historyTab
            case .saved:
                savedQueriesTab
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.midnight)
        .alert("Delete Saved Query", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let id = deleteQueryId {
                    viewModel.deleteQuery(id: id)
                }
            }
        } message: {
            Text("Are you sure you want to delete this saved query? This action cannot be undone.")
        }
    }

    // MARK: - History Tab

    private var historyTab: some View {
        VStack(spacing: 0) {
            // Filter controls
            HStack(spacing: 12) {
                // Operation type picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Operation")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Picker("", selection: $filterOperation) {
                        Text("All").tag(QueryLogEntry.OperationType?.none)
                        ForEach(QueryLogEntry.OperationType.allCases, id: \.self) { op in
                            Text(op.displayName).tag(QueryLogEntry.OperationType?.some(op))
                        }
                    }
                    .frame(width: 120)
                }

                // Search field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Search")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("Collection or query text...", text: $searchText)
                        .textFieldStyle(.themed)
                }

                Spacer()
            }
            .padding(14)
            .background(Theme.surface.opacity(0.3))

            ThemedDivider()

            // Query log list
            if filteredLog.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.textSecondary)
                    Text("No query history")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Queries will appear here as you interact with the database.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredLog) { entry in
                            queryLogRow(entry)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private var filteredLog: [QueryLogEntry] {
        viewModel.queryLog.filter { entry in
            if let op = filterOperation, entry.operationType != op {
                return false
            }
            if !searchText.isEmpty {
                let lowerSearch = searchText.lowercased()
                let matchesCollection = entry.collection.lowercased().contains(lowerSearch)
                let matchesDatabase = entry.database.lowercased().contains(lowerSearch)
                let matchesQuery = entry.query.lowercased().contains(lowerSearch)
                if !matchesCollection && !matchesDatabase && !matchesQuery {
                    return false
                }
            }
            return true
        }
    }

    private func queryLogRow(_ entry: QueryLogEntry) -> some View {
        HStack(spacing: 12) {
            // Timestamp
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.timestamp, style: .time)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Text(entry.timestamp, style: .date)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
            }
            .frame(width: 80, alignment: .leading)

            // Operation type badge
            Text(entry.operationType.displayName)
                .pillBadge(color: operationColor(entry.operationType))
                .frame(width: 80)

            // Database.collection
            Text("\(entry.database).\(entry.collection)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)

            // Query text (truncated, monospaced)
            Text(entry.query)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Execution time
            Text("\(entry.executionTimeMs) ms")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(executionTimeColor(entry.executionTimeMs))
                .frame(width: 70, alignment: .trailing)

            // Docs returned
            HStack(spacing: 3) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                Text("\(entry.docsReturned)")
                    .font(.system(size: 11, design: .monospaced))
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 50, alignment: .trailing)

            // Star (favorite) button
            Button {
                viewModel.toggleQueryFavorite(entry)
            } label: {
                Image(systemName: entry.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(entry.isFavorite ? Theme.amber : Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help(entry.isFavorite ? "Remove from favorites" : "Add to favorites")

            // Run Again button (only for find operations)
            if entry.operationType == .find {
                Button {
                    Task {
                        await viewModel.replayQuery(entry)
                    }
                } label: {
                    Image(systemName: "play.fill")
                }
                .toolbarIconButton()
                .buttonStyle(.plain)
                .help("Run Again")
            }

            // Copy query button
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.query, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .toolbarIconButton()
            .buttonStyle(.plain)
            .help("Copy Query")
        }
        .cardStyle(padding: 10, cornerRadius: 8)
    }

    // MARK: - Saved Queries Tab

    private var savedQueriesTab: some View {
        Group {
            if viewModel.savedQueries.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.textSecondary)
                    Text("No saved queries")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Save frequently used queries from the Explorer view for quick access.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.savedQueries) { query in
                            savedQueryCard(query)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private func savedQueryCard(_ query: SavedQuery) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text(query.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                Text("\(query.database).\(query.collection)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            ThemedDivider()

            // Filter
            if !query.filter.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Filter")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(query.filter)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
            }

            // Sort
            if !query.sort.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sort")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(query.sort)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }

            // Projection
            if !query.projection.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Projection")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(query.projection)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }

            // Tags
            if !query.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(query.tags, id: \.self) { tag in
                        Text(tag)
                            .pillBadge(color: tagColor(for: tag))
                    }
                }
            }

            ThemedDivider()

            // Actions
            HStack {
                Spacer()

                Button {
                    Task {
                        await viewModel.loadQuery(query)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("Load")
                    }
                }
                .buttonStyle(.accentCompact)

                Button {
                    deleteQueryId = query.id
                    showDeleteAlert = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                }
                .buttonStyle(AccentButtonStyle(color: Theme.crimson, isCompact: true))
            }
        }
        .cardStyle(padding: 14, cornerRadius: 10)
    }

    // MARK: - Helpers

    private func operationColor(_ op: QueryLogEntry.OperationType) -> Color {
        switch op {
        case .find: return Theme.skyBlue
        case .insert: return Theme.green
        case .update: return Theme.amber
        case .delete: return Theme.crimson
        case .aggregate: return Color.purple
        }
    }

    private func executionTimeColor(_ ms: Int) -> Color {
        if ms < 50 { return Theme.green }
        if ms < 200 { return Theme.amber }
        return Theme.crimson
    }

    private func tagColor(for tag: String) -> Color {
        let colors: [Color] = [Theme.green, Theme.skyBlue, Theme.amber, Color.purple, Color.pink, Color.orange]
        let index = abs(tag.hashValue) % colors.count
        return colors[index]
    }
}
