import SwiftUI

@MainActor
struct SidebarView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var searchQuery: String = ""
    @FocusState private var searchFocused: Bool
    @State private var showCreateDBAlert = false
    @State private var newDatabaseName = ""
    @State private var showCreateCollectionAlert = false
    @State private var newCollectionName = ""
    @State private var createCollectionForDB = ""
    @State private var showDropDBAlert = false
    @State private var dropDatabaseName = ""
    @State private var showDropCollAlert = false
    @State private var dropCollectionName = ""
    @State private var dropCollectionDB = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            brandRow
            connectionSwitcher
            searchField
            databasesSection
                .frame(maxHeight: .infinity, alignment: .top)
            workspaceNavSection
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(Theme.surface2)
        .alert("Create Database", isPresented: $showCreateDBAlert) {
            TextField("Database name", text: $newDatabaseName)
            Button("Cancel", role: .cancel) { newDatabaseName = "" }
            Button("Create") {
                let name = newDatabaseName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task { await viewModel.createDatabase(name: name) }
                newDatabaseName = ""
            }
        } message: {
            Text("Enter a name for the new database.")
        }
        .alert("Create Collection", isPresented: $showCreateCollectionAlert) {
            TextField("Collection name", text: $newCollectionName)
            Button("Cancel", role: .cancel) { newCollectionName = "" }
            Button("Create") {
                let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task { await viewModel.createCollection(name: name, inDatabase: createCollectionForDB) }
                newCollectionName = ""
            }
        } message: {
            Text("Enter a name for the new collection in \"\(createCollectionForDB)\".")
        }
        .alert("Drop Database", isPresented: $showDropDBAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Drop", role: .destructive) {
                Task { await viewModel.dropDatabase(name: dropDatabaseName) }
            }
        } message: {
            Text("Are you sure you want to drop \"\(dropDatabaseName)\"? This action cannot be undone.")
        }
        .alert("Drop Collection", isPresented: $showDropCollAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Drop", role: .destructive) {
                Task { await viewModel.dropCollection(name: dropCollectionName, inDatabase: dropCollectionDB) }
            }
        } message: {
            Text("Are you sure you want to drop \"\(dropCollectionName)\" from \"\(dropCollectionDB)\"? This action cannot be undone.")
        }
    }

    // MARK: - Brand row

    private var brandRow: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.brandGradient)
                    .frame(width: 22, height: 22)
                    .shadow(color: Theme.primaryDeep.opacity(0.35), radius: 1, y: 1)
                Triangle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 10, height: 10)
            }
            HStack(spacing: 0) {
                Text("Compass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("+")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.primary)
            }
            .tracking(-0.1)

            Spacer(minLength: 0)

            StatusDot(color: Theme.success, size: 8)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    // MARK: - Connection switcher

    private var connectionSwitcher: some View {
        Menu {
            Section(viewModel.connectionName.isEmpty ? "Not connected" : viewModel.connectionName) {
                Button("Disconnect", role: .destructive) {
                    viewModel.disconnect()
                }
            }
        } label: {
            HStack(spacing: 8) {
                StatusDot(color: viewModel.isConnected ? Theme.success : Theme.textMuted, size: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.connectionName.isEmpty ? "Not connected" : viewModel.connectionName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(viewModel.connectionURI.isEmpty ? "—" : viewModel.connectionURI)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: Theme.shadowAmbient.opacity(0.6), radius: 2, y: 1)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textMuted)

            TextField("Search databases…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .focused($searchFocused)

            Text("⌘K")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surface3)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .background(
            // Hidden button claims the ⌘K shortcut at the global menu level.
            Button("") { searchFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }

    // MARK: - Databases section

    private var databasesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Databases")
                    .sectionHeaderStyle()
                Spacer()
                Button {
                    Task { await viewModel.loadDatabases() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Refresh databases")

                Button {
                    showCreateDBAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Create database")
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 2)

            if let error = viewModel.error {
                errorBanner(error)
            }

            ScrollView(.vertical, showsIndicators: false) {
                if filteredDatabases.isEmpty && viewModel.error == nil {
                    Text("No databases found.\nCheck connection URI credentials.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                        .frame(maxWidth: .infinity)
                }
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(filteredDatabases, id: \.self) { database in
                        databaseRow(database)
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private var filteredDatabases: [String] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return viewModel.databases }
        return viewModel.databases.filter { db in
            db.lowercased().contains(q) ||
            (viewModel.collections[db]?.contains { $0.lowercased().contains(q) } ?? false)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.warningDeep)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.warningDeep)
                .lineLimit(3)
            Spacer()
            Button {
                viewModel.error = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.warningDeep.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Theme.warningTint)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Database row

    private func databaseRow(_ database: String) -> some View {
        let isExpanded = viewModel.expandedDatabases.contains(database)
        let isSelected = viewModel.activeTab.selectedDatabase == database
            && viewModel.activeTab.selectedCollection == nil

        return VStack(alignment: .leading, spacing: 1) {
            sidebarRow(
                isActive: isSelected,
                paddingLeading: 8,
                content: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(isSelected ? Theme.primaryDeep : Theme.textMuted)
                            .frame(width: 10)
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? Theme.primaryDeep : Theme.textSecondary)
                            .frame(width: 14)
                        Text(database)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(isSelected ? Theme.primaryDeep : Theme.textSoft)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        addCollectionButton(for: database)
                    }
                }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                Task { await viewModel.toggleDatabaseExpanded(database) }
            }
            .contextMenu {
                Button {
                    createCollectionForDB = database
                    showCreateCollectionAlert = true
                } label: {
                    Label("Create Collection…", systemImage: "plus")
                }
                Button(role: .destructive) {
                    dropDatabaseName = database
                    showDropDBAlert = true
                } label: {
                    Label("Drop Database", systemImage: "trash")
                }
            }

            if isExpanded, let collections = viewModel.collections[database] {
                ForEach(filteredCollections(in: database, all: collections), id: \.self) { collection in
                    collectionRow(collection, database: database)
                }
            }
        }
    }

    private func filteredCollections(in database: String, all: [String]) -> [String] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        if database.lowercased().contains(q) { return all }
        return all.filter { $0.lowercased().contains(q) }
    }

    private func addCollectionButton(for database: String) -> some View {
        Button {
            createCollectionForDB = database
            showCreateCollectionAlert = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.primary.opacity(0.85))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Create collection in \(database)")
    }

    // MARK: - Collection row

    private func collectionRow(_ collection: String, database: String) -> some View {
        let isSelected = viewModel.activeTab.selectedDatabase == database &&
            viewModel.activeTab.selectedCollection == collection

        return sidebarRow(
            isActive: isSelected,
            paddingLeading: 30,
            content: {
                HStack(spacing: 6) {
                    Image(systemName: "tray.full")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? Theme.primaryDeep : Theme.textSecondary)
                        .frame(width: 14)
                    Text(collection)
                        .font(.system(size: 12, design: .monospaced))
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Theme.primaryDeep : Theme.textSoft)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                await viewModel.selectDatabase(database)
                await viewModel.selectCollection(collection)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                dropCollectionName = collection
                dropCollectionDB = database
                showDropCollAlert = true
            } label: {
                Label("Drop Collection", systemImage: "trash")
            }
        }
    }

    // MARK: - Workspace nav

    private var workspaceNavSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Workspace")
                .sectionHeaderStyle()
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            ForEach(NavSection.allCases) { section in
                navButton(for: section)
            }
        }
    }

    private func navButton(for section: NavSection) -> some View {
        @Bindable var viewModel = viewModel
        let isActive = viewModel.activeTab.navSection == section
        let trailing = navTrailingBadge(for: section)

        return sidebarRow(
            isActive: isActive,
            paddingLeading: 8,
            content: {
                HStack(spacing: 8) {
                    Image(systemName: section.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(isActive ? Theme.primaryDeep : Theme.textSecondary)
                        .frame(width: 16)
                    Text(section.rawValue)
                        .font(.system(size: 12.5, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Theme.primaryDeep : Theme.textSoft)
                    Spacer(minLength: 0)
                    trailing
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.activeTab.navSection = section
        }
    }

    @ViewBuilder
    private func navTrailingBadge(for section: NavSection) -> some View {
        switch section {
        case .investigate:
            let critical = viewModel.investigateBadgeCount
            if critical > 0 {
                Text("\(critical)").pillBadge(.danger)
            }
        case .queryLog:
            let count = viewModel.queryLog.count
            if count > 0 {
                Text(formatCompact(count))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Theme.surface1)
                    .clipShape(Capsule())
                    .shadow(color: Theme.shadowAmbient, radius: 1, y: 0.5)
            }
        case .schema:
            let count = viewModel.schemaFields.count
            if count > 0 {
                Text(formatCompact(count))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Theme.surface1)
                    .clipShape(Capsule())
                    .shadow(color: Theme.shadowAmbient, radius: 1, y: 0.5)
            }
        default:
            EmptyView()
        }
    }

    private func formatCompact(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:     return String(format: "%.1fk", Double(n) / 1_000)
        default:           return "\(n)"
        }
    }

    // MARK: - Shared row chrome (handles active state + 3pt accent strip)

    private func sidebarRow<Content: View>(
        isActive: Bool,
        paddingLeading: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.leading, paddingLeading)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Theme.surfaceActive : Color.clear)
                    if isActive {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.primary)
                            .frame(width: 3)
                            .padding(.vertical, 6)
                            .offset(x: -2)
                    }
                }
            )
    }
}

// MARK: - Brand mark triangle

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
