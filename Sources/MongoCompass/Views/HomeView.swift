import SwiftUI

@MainActor
struct HomeView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            VStack(spacing: 0) {
                toolbarArea
                ThemedDivider()
                tabBar
                ThemedDivider()
                tabContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.midnight)
        }
        .navigationSplitViewStyle(.balanced)
        .background(Theme.midnight)
        .keyboardShortcut(.init("t"), modifiers: .command)
        .onAppear {
            // Keyboard shortcuts are handled via menu commands in MongoCompassApp
        }
    }

    // MARK: - Toolbar Area

    private var toolbarArea: some View {
        HStack(spacing: 12) {
            // Breadcrumb
            breadcrumb

            Spacer()

            // Document count
            if let collection = viewModel.activeTab.selectedCollection {
                Text("\(viewModel.documentCount) documents")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .opacity(collection.isEmpty ? 0 : 1)
            }

            // Connection indicator
            HStack(spacing: 6) {
                StatusDot(color: Theme.green, size: 7)
                Text(viewModel.connectionName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.surface)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface.opacity(0.5))
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            if let db = viewModel.activeTab.selectedDatabase {
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Text(db)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)

                if let coll = viewModel.activeTab.selectedCollection {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Text(coll)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.green)
                }
            } else {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.green)
                Text("Select a database")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(viewModel.tabs.enumerated()), id: \.element.id) { index, tab in
                    tabBarItem(tab: tab, index: index)
                }

                Button {
                    viewModel.addTab()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.green)
                        .frame(width: 28, height: 28)
                        .background(Theme.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Theme.midnight)
    }

    private func tabBarItem(tab: TabState, index: Int) -> some View {
        let isActive = index == viewModel.activeTabIndex
        return HStack(spacing: 6) {
            Image(systemName: tab.navSection.icon)
                .font(.system(size: 11))

            Text(tab.selectedCollection ?? tab.selectedDatabase ?? "New Tab")
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)

            Button {
                viewModel.closeTab(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isActive ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Theme.surface : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Theme.green.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .foregroundStyle(isActive ? Theme.green : .secondary)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.switchTab(to: index)
        }
        .onHover { hovering in
            // The close button is shown via opacity; we can enhance this
            // by toggling state, but for simplicity the close button appears on active tab
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.activeTab.navSection {
        case .explorer:
            DocumentListView()
        case .queryLog:
            QueryLogView()
        case .aggregation:
            AggregationView()
        case .investigate:
            InvestigateView()
        case .metrics:
            MetricsView()
        case .dumpRestore:
            DumpRestoreView()
        case .schema:
            SchemaView()
        case .shell:
            ShellView()
        }
    }
}

// All section views are defined in their own files in the Views/ directory
