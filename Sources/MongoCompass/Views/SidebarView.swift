import SwiftUI

struct SidebarView: View {
    @Environment(AppViewModel.self) private var viewModel

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
        VStack(spacing: 0) {
            navigationSection
            ThemedDivider()
            databaseTreeSection
            ThemedDivider()
            disconnectFooter
        }
        .frame(maxHeight: .infinity)
        .background(Theme.midnight)
        .alert("Create Database", isPresented: $showCreateDBAlert) {
            TextField("Database name", text: $newDatabaseName)
            Button("Cancel", role: .cancel) {
                newDatabaseName = ""
            }
            Button("Create") {
                let name = newDatabaseName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task {
                    await viewModel.createDatabase(name: name)
                }
                newDatabaseName = ""
            }
        } message: {
            Text("Enter a name for the new database.")
        }
        .alert("Create Collection", isPresented: $showCreateCollectionAlert) {
            TextField("Collection name", text: $newCollectionName)
            Button("Cancel", role: .cancel) {
                newCollectionName = ""
            }
            Button("Create") {
                let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task {
                    await viewModel.createCollection(name: name, inDatabase: createCollectionForDB)
                }
                newCollectionName = ""
            }
        } message: {
            Text("Enter a name for the new collection in \"\(createCollectionForDB)\".")
        }
        .alert("Drop Database", isPresented: $showDropDBAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Drop", role: .destructive) {
                Task {
                    await viewModel.dropDatabase(name: dropDatabaseName)
                }
            }
        } message: {
            Text("Are you sure you want to drop \"\(dropDatabaseName)\"? This action cannot be undone.")
        }
        .alert("Drop Collection", isPresented: $showDropCollAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Drop", role: .destructive) {
                Task {
                    await viewModel.dropCollection(name: dropCollectionName, inDatabase: dropCollectionDB)
                }
            }
        } message: {
            Text("Are you sure you want to drop \"\(dropCollectionName)\" from \"\(dropCollectionDB)\"? This action cannot be undone.")
        }
    }

    // MARK: - Navigation Section

    private var navigationSection: some View {
        VStack(spacing: 2) {
            ForEach(NavSection.allCases) { section in
                navButton(for: section)
            }
        }
        .padding(10)
    }

    private func navButton(for section: NavSection) -> some View {
        @Bindable var viewModel = viewModel
        let isActive = viewModel.activeTab.navSection == section

        return Button {
            viewModel.activeTab.navSection = section
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 13))
                    .frame(width: 20)
                Text(section.rawValue)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? Theme.green.opacity(0.15) : Color.clear)
            .foregroundStyle(isActive ? Theme.green : Theme.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Database Tree Section

    private var databaseTreeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Databases")
                    .sectionHeaderStyle()
                Spacer()
                Button {
                    Task {
                        await viewModel.loadDatabases()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Refresh databases")

                Button {
                    showCreateDBAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.green)
                }
                .buttonStyle(.plain)
                .help("Create database")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Error display
            if let error = viewModel.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.amber)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.crimson)
                        .lineLimit(3)
                    Spacer()
                    Button {
                        viewModel.error = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Theme.crimson.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }

            // Database list
            ScrollView(.vertical, showsIndicators: false) {
                if viewModel.databases.isEmpty && viewModel.error == nil {
                    Text("No databases found.\nCheck your connection URI\nhas proper credentials.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                        .frame(maxWidth: .infinity)
                }
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.databases, id: \.self) { database in
                        databaseRow(database)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Database Row

    private func databaseRow(_ database: String) -> some View {
        let isExpanded = viewModel.expandedDatabases.contains(database)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 12)

                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.amber)

                Text(database)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Button {
                    createCollectionForDB = database
                    showCreateCollectionAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.green.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Create collection in \(database)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                viewModel.activeTab.selectedDatabase == database && viewModel.activeTab.selectedCollection == nil
                    ? Theme.surface : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture {
                Task {
                    await viewModel.toggleDatabaseExpanded(database)
                }
            }
            .contextMenu {
                Button(role: .destructive) {
                    dropDatabaseName = database
                    showDropDBAlert = true
                } label: {
                    Label("Drop Database", systemImage: "trash")
                }
            }

            // Collections
            if isExpanded, let collections = viewModel.collections[database] {
                ForEach(collections, id: \.self) { collection in
                    collectionRow(collection, database: database)
                }
            }
        }
    }

    // MARK: - Collection Row

    private func collectionRow(_ collection: String, database: String) -> some View {
        let isSelected = viewModel.activeTab.selectedDatabase == database &&
            viewModel.activeTab.selectedCollection == collection

        return HStack(spacing: 6) {
            Color.clear.frame(width: 18) // indent

            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Theme.green : Theme.textSecondary)

            Text(collection)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? .white : Theme.textSecondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isSelected ? Theme.green.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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

    // MARK: - Disconnect Footer

    private var disconnectFooter: some View {
        Button {
            viewModel.disconnect()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "eject.fill")
                    .font(.system(size: 12))
                Text("Disconnect")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Theme.crimson)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
