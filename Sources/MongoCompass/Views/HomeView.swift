import SwiftUI

@MainActor
struct HomeView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 280)
        } detail: {
            VStack(spacing: 0) {
                tabBar
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                statusBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface0)
        }
        .navigationSplitViewStyle(.balanced)
        .background(Theme.canvas)
    }

    // MARK: - Tab Bar (per design — surface-2 gutter, surface-1 active tab)

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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New tab")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
        }
        .background(Theme.surface2)
    }

    private func tabBarItem(tab: TabState, index: Int) -> some View {
        let isActive = index == viewModel.activeTabIndex
        let dotColor: Color = viewModel.isConnected ? Theme.success : Theme.textMuted
        let label: String = {
            if let coll = tab.selectedCollection, let db = tab.selectedDatabase {
                return "\(db).\(coll)"
            }
            if let db = tab.selectedDatabase {
                return db
            }
            return "New tab"
        }()

        return HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)

            Text(label)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if viewModel.tabs.count > 1 {
                Button {
                    viewModel.closeTab(at: index)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 14, height: 14)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isActive ? Theme.surface3.opacity(0) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isActive ? 1 : 0.55)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 220)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 8
            )
            .fill(isActive ? Theme.surface1 : Theme.surface0)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.switchTab(to: index)
        }
    }

    // MARK: - Status bar (bottom)

    private var statusBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isConnected ? Theme.success : Theme.textMuted)
                    .frame(width: 7, height: 7)
                Text(viewModel.isConnected
                     ? (viewModel.connectionName.isEmpty ? "connected" : viewModel.connectionName)
                     : "disconnected")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            if let version = viewModel.serverMetrics?.version, !version.isEmpty {
                Text("•")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted.opacity(0.6))
                Text("MongoDB v\(version)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if viewModel.activeTab.selectedCollection != nil, viewModel.documentCount > 0 {
                Text("\(viewModel.documentCount.formatted()) documents")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(Theme.surface2)
    }

    // MARK: - Tab content (per-screen views render their own top toolbar)

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.activeTab.navSection {
        case .explorer:     DocumentListView()
        case .queryLog:     QueryLogView()
        case .aggregation:  AggregationView()
        case .investigate:  InvestigateView()
        case .metrics:      MetricsView()
        case .dumpRestore:  DumpRestoreView()
        case .schema:       SchemaView()
        case .shell:        ShellView()
        }
    }
}
