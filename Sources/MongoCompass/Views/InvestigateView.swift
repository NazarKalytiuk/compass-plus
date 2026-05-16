import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct InvestigateView: View {
    @Environment(AppViewModel.self) private var viewModel

    enum RefreshInterval: String, CaseIterable, Identifiable {
        case s1 = "1s"
        case s2 = "2s"
        case s10 = "10s"
        case off = "Off"
        var id: String { rawValue }
        var seconds: TimeInterval? {
            switch self {
            case .s1: return 1; case .s2: return 2; case .s10: return 10; case .off: return nil
            }
        }
    }

    @State private var refreshInterval: RefreshInterval = .s2
    @State private var lastRefreshAt: Date = .now
    @State private var refreshTask: Task<Void, Never>?

    // Slow-queries threshold prompt
    @State private var thresholdInput: String = ""
    @State private var showThresholdPopover = false

    // Index creation
    @State private var indexKeysJSON = "{\"field\": 1}"
    @State private var indexUnique = false
    @State private var indexSparse = false
    @State private var showCreateIndexSheet = false

    // Drop index
    @State private var dropIndexName: String?
    @State private var showDropIndexAlert = false

    // Explain
    @State private var explainResult: [String: Any]?
    @State private var showExplainSheet = false
    @State private var isExplaining = false

    // Current-ops filter popover
    @State private var showOpsFilterPopover = false
    @State private var opsFilterNamespace: String = ""
    @State private var opsFilterOpType: String = "all"
    @State private var opsFilterMinDurationMs: String = ""

    // Slow-queries "Lower threshold…" popover persisted across launches.
    @State private var showLowerThresholdPopover = false
    @AppStorage("investigate.slowQueries.thresholdMs") private var persistedSlowMs: Int = 100

    // Report export
    @State private var isExportingReport = false
    @State private var reportDocument: InvestigateReportDocument = .empty

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 14) {
                    currentOpsSection
                    slowQueriesSection
                    indexRecommendationsSection
                    if viewModel.activeTab.selectedCollection != nil {
                        existingIndexesSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
            .background(Theme.surface0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface0)
        .fileExporter(
            isPresented: $isExportingReport,
            document: reportDocument,
            contentType: .json,
            defaultFilename: "investigate-report-\(Self.exportFilenameFormatter.string(from: Date())).json"
        ) { _ in /* swallow */ }
        .onAppear {
            thresholdInput = "\(viewModel.slowMs)"
            Task { await refreshAll() }
            restartPolling()
        }
        .onDisappear { refreshTask?.cancel() }
        .onChange(of: refreshInterval) { _, _ in restartPolling() }
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
        .sheet(isPresented: $showExplainSheet) { explainSheet }
        .sheet(isPresented: $showCreateIndexSheet) { createIndexSheet }
    }

    // MARK: - Top toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            breadcrumb
            heartbeat
            Spacer()

            Text("Refresh")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textMuted)

            Segmented(
                items: RefreshInterval.allCases,
                label: { Text($0.rawValue) },
                selection: $refreshInterval
            )

            Button {
                exportReport()
            } label: {
                Text("Export report")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
            Text(viewModel.connectionName.isEmpty ? "cluster" : viewModel.connectionName)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            Text("investigate")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var heartbeat: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(lastRefreshAt))
            HStack(spacing: 4) {
                Circle()
                    .fill(Theme.success)
                    .frame(width: 7, height: 7)
                    .opacity(0.65 + 0.35 * (sin(elapsed * 2) + 1) / 2)
                Text("live · \(formatElapsed(elapsed)) ago")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Section: Current operations

    private var currentOpsSection: some View {
        let ops = filteredOps(viewModel.currentOps)
        let totalOps = viewModel.currentOps.count
        let slowCount = ops.filter { $0.executionTimeMs >= 1000 }.count

        return investCard {
            sectionHead(
                title: "Current operations",
                sub: ops.count == totalOps
                    ? "\(ops.count) active · \(slowCount) with duration > 1s"
                    : "\(ops.count) of \(totalOps) match filter · \(slowCount) > 1s",
                trailing: {
                    AnyView(
                        HStack(spacing: 6) {
                            if slowCount > 0 {
                                Text("\(slowCount) above SLA").pillBadge(.warning)
                            } else if !ops.isEmpty {
                                Text("healthy").pillBadge(.success)
                            }
                            opsFilterButton
                        }
                    )
                }
            )

            if ops.isEmpty {
                emptyRow(message: "No live operations.")
            } else {
                tableHeader([
                    ("Op",        .leading,  90),
                    ("Namespace", .leading,  nil),
                    ("Client",    .leading,  180),
                    ("Locks",     .trailing, 80),
                    ("Duration",  .trailing, 110),
                    ("",          .trailing, 90),
                ])

                ForEach(Array(ops.enumerated()), id: \.element.id) { _, op in
                    currentOpRow(op)
                }
            }
        }
    }

    private var opsFilterButton: some View {
        let filterActive = !opsFilterNamespace.isEmpty
            || opsFilterOpType != "all"
            || !opsFilterMinDurationMs.isEmpty

        return Button {
            showOpsFilterPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 11))
                Text(filterActive ? "Filter · on" : "Filter…")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(filterActive ? Theme.primaryDeep : Theme.textSoft)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(filterActive ? Theme.primaryTint : Theme.surface3)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showOpsFilterPopover, arrowEdge: .top) {
            opsFilterPopover
        }
    }

    private var opsFilterPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filter current ops")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Namespace contains").sectionHeaderStyle()
                TextField("e.g. users or orders.items", text: $opsFilterNamespace)
                    .textFieldStyle(.themedSans)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Op type").sectionHeaderStyle()
                Picker("", selection: $opsFilterOpType) {
                    Text("All").tag("all")
                    Text("query").tag("query")
                    Text("insert").tag("insert")
                    Text("update").tag("update")
                    Text("remove").tag("remove")
                    Text("command").tag("command")
                    Text("getmore").tag("getmore")
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Min duration (ms)").sectionHeaderStyle()
                TextField("0", text: $opsFilterMinDurationMs)
                    .textFieldStyle(.themedSans)
            }
            HStack {
                Button("Reset") {
                    opsFilterNamespace = ""
                    opsFilterOpType = "all"
                    opsFilterMinDurationMs = ""
                }
                .buttonStyle(.ghost)
                Spacer()
                Button("Close") { showOpsFilterPopover = false }
                    .buttonStyle(.accent)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func filteredOps(_ ops: [CurrentOp]) -> [CurrentOp] {
        let needle = opsFilterNamespace.trimmingCharacters(in: .whitespaces).lowercased()
        let minMs = Int(opsFilterMinDurationMs) ?? 0
        return ops.filter { op in
            if !needle.isEmpty, !op.namespace.lowercased().contains(needle) { return false }
            if opsFilterOpType != "all", op.op.lowercased() != opsFilterOpType { return false }
            if minMs > 0, op.executionTimeMs < minMs { return false }
            return true
        }
    }

    private func currentOpRow(_ op: CurrentOp) -> some View {
        let severity = opSeverity(op.executionTimeMs)
        let canKill = op.executionTimeMs >= 500
        return tableRow(tint: severity.rowTint) {
            HStack(spacing: 0) {
                HStack {
                    Text(op.op).pillBadge(severity.opBadge)
                    Spacer(minLength: 0)
                }
                .frame(width: 90, alignment: .leading)

                Text(op.namespace)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(op.client)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 180, alignment: .leading)

                Text("R \(op.readLocks) / W \(op.writeLocks)")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle((op.readLocks + op.writeLocks) > 0 ? Theme.textSoft : Theme.textMuted)
                    .frame(width: 80, alignment: .trailing)

                Text(formatDuration(op.executionTimeMs))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(severity.durationColor)
                    .frame(width: 110, alignment: .trailing)

                HStack {
                    Spacer()
                    Button {
                        Task { await viewModel.killOp(opId: op.id) }
                    } label: {
                        Text("Kill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(canKill ? Theme.danger : Theme.danger.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canKill)
                }
                .frame(width: 90, alignment: .trailing)
            }
        }
    }

    private struct OpSeverity {
        let opBadge: BadgeKind
        let rowTint: Color?
        let durationColor: Color
    }

    private func opSeverity(_ ms: Int) -> OpSeverity {
        if ms >= 5000 {
            return OpSeverity(opBadge: .danger,  rowTint: Theme.danger.opacity(0.06),  durationColor: Theme.danger)
        } else if ms >= 1000 {
            return OpSeverity(opBadge: .warning, rowTint: Theme.warning.opacity(0.06), durationColor: Theme.warning)
        } else if ms >= 200 {
            return OpSeverity(opBadge: .info,    rowTint: nil, durationColor: Theme.info)
        } else {
            return OpSeverity(opBadge: .neutral, rowTint: nil, durationColor: Theme.successDeep)
        }
    }

    // MARK: - Section: Slow queries

    private var slowQueriesSection: some View {
        let queries = viewModel.slowQueries
        let affected = Set(queries.map { $0.namespace }).count

        return investCard {
            sectionHead(
                title: "Slow queries",
                sub: "threshold \(viewModel.slowMs)ms · \(queries.count) entries",
                trailing: {
                    AnyView(
                        HStack(spacing: 6) {
                            if affected > 0 {
                                Text("\(affected) endpoint\(affected == 1 ? "" : "s") affected").pillBadge(.danger)
                            }
                            lowerThresholdButton
                            thresholdMenu
                        }
                    )
                }
            )

            if queries.isEmpty {
                emptyRow(message: "No slow queries recorded. Enable profiling and refresh.")
                HStack {
                    Spacer()
                    Button {
                        Task { await viewModel.fetchSlowQueries() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass").font(.system(size: 11))
                            Text("Fetch slow queries")
                        }
                    }
                    .buttonStyle(.accentCompact)
                    .padding(.bottom, 12)
                    Spacer()
                }
            } else {
                tableHeader([
                    ("Pattern",    .leading,  nil),
                    ("Collection", .leading,  180),
                    ("Mean ms",    .trailing, 80),
                    ("P99 ms",     .trailing, 80),
                    ("Count",      .trailing, 60),
                    ("Last seen",  .leading,  100),
                    ("Scanned",    .trailing, 80),
                    ("Plan",       .leading,  120),
                    ("",           .trailing, 80),
                ])

                ForEach(queries) { entry in
                    slowQueryRow(entry)
                }
            }
        }
    }

    private var lowerThresholdButton: some View {
        Button {
            showLowerThresholdPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down").font(.system(size: 10, weight: .semibold))
                Text("Lower threshold…")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.textSoft)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.surface3)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showLowerThresholdPopover, arrowEdge: .top) {
            lowerThresholdPopover
        }
    }

    private var lowerThresholdPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lower slow-query threshold")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Stepper("Threshold: \(persistedSlowMs) ms",
                    value: $persistedSlowMs,
                    in: 10...10_000,
                    step: 10)
                .padding(.vertical, 4)

            Text("Persisted across launches. Applies on the next profiling level change.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Apply now") {
                    Task {
                        await viewModel.setProfilingLevel(viewModel.profilingLevel, slowMs: persistedSlowMs)
                    }
                    showLowerThresholdPopover = false
                }
                .buttonStyle(.accent)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private var thresholdMenu: some View {
        Menu {
            Section("Slow threshold (ms)") {
                Button("50ms")  { applyThreshold(50) }
                Button("100ms") { applyThreshold(100) }
                Button("250ms") { applyThreshold(250) }
                Button("500ms") { applyThreshold(500) }
                Button("1000ms") { applyThreshold(1000) }
            }
            Divider()
            Section("Profiling level") {
                Button("Off")  { Task { await viewModel.setProfilingLevel(0, slowMs: viewModel.slowMs) } }
                Button("Slow only") { Task { await viewModel.setProfilingLevel(1, slowMs: viewModel.slowMs) } }
                Button("All ops")   { Task { await viewModel.setProfilingLevel(2, slowMs: viewModel.slowMs) } }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 11))
                Text("Settings")
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Theme.textSoft)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func applyThreshold(_ ms: Int) {
        Task { await viewModel.setProfilingLevel(viewModel.profilingLevel, slowMs: ms) }
    }

    private func slowQueryRow(_ entry: SlowQueryEntry) -> some View {
        let p99 = entry.p99Ms
        let (durColor, rowTint): (Color, Color?) = {
            if p99 >= 1000 { return (Theme.danger,  Theme.danger.opacity(0.06)) }
            if p99 >= 250  { return (Theme.warning, Theme.warning.opacity(0.06)) }
            return (Theme.successDeep, nil)
        }()
        let scanRatio = entry.keysExamined > 0
            ? Double(entry.docsExamined) / Double(entry.keysExamined)
            : Double(entry.docsExamined)
        let isCollscan = entry.planSummary.uppercased().contains("COLLSCAN") || entry.planSummary.isEmpty

        return tableRow(tint: rowTint) {
            HStack(spacing: 0) {
                Text(queryPreview(entry.command))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.textSoft)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.namespace)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .frame(width: 180, alignment: .leading)

                Text(entry.meanMs.formatted())
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 80, alignment: .trailing)

                Text(p99.formatted())
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(durColor)
                    .frame(width: 80, alignment: .trailing)

                Text(entry.count.formatted())
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 60, alignment: .trailing)

                Text(Self.relativeLastSeenFormatter.localizedString(for: entry.lastSeen, relativeTo: Date()))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .frame(width: 100, alignment: .leading)

                HStack(spacing: 4) {
                    Spacer()
                    Text(entry.docsExamined.formatted())
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(scanRatio >= 10 ? Theme.danger
                                         : (scanRatio >= 2 ? Theme.warning : Theme.textSecondary))
                }
                .frame(width: 80, alignment: .trailing)

                HStack {
                    Text(entry.planSummary.isEmpty ? "COLLSCAN" : entry.planSummary.uppercased())
                        .pillBadge(isCollscan ? .danger : .success)
                    Spacer(minLength: 0)
                }
                .frame(width: 120, alignment: .leading)

                HStack {
                    Spacer()
                    Button {
                        Task {
                            isExplaining = true
                            let result = await viewModel.explainCurrentQuery()
                            explainResult = result
                            isExplaining = false
                            if result != nil { showExplainSheet = true }
                        }
                    } label: {
                        Text("Explain")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textSoft)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Theme.surface3)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 80, alignment: .trailing)
            }
        }
    }

    private static let relativeLastSeenFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    // MARK: - Section: Index recommendations

    private var indexRecommendationsSection: some View {
        let recs = viewModel.indexRecommendations
        let totalSavings = recs.reduce(0) { $0 + $1.totalExecTimeMs }

        return investCard {
            sectionHead(
                title: "Index recommendations",
                sub: recs.isEmpty
                    ? "Run an analysis to surface compound-index suggestions."
                    : "\(recs.count) suggestion\(recs.count == 1 ? "" : "s") based on recent query patterns",
                trailing: {
                    HStack(spacing: 6) {
                        if !recs.isEmpty {
                            AnyView(Text("est. −\(formatDuration(totalSavings)) total").pillBadge(.success))
                        } else {
                            AnyView(EmptyView())
                        }
                        AnyView(
                            Button {
                                Task { await viewModel.computeIndexRecommendations() }
                            } label: {
                                HStack(spacing: 4) {
                                    if viewModel.isComputingRecommendations {
                                        ProgressView().controlSize(.mini).scaleEffect(0.65)
                                    } else {
                                        Image(systemName: "wand.and.stars").font(.system(size: 11))
                                    }
                                    Text(viewModel.isComputingRecommendations ? "Analysing…" : "Analyse")
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSoft)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isComputingRecommendations)
                        )
                    }
                }
            )

            if recs.isEmpty {
                emptyRow(message: viewModel.slowQueries.isEmpty
                    ? "No analysis yet. Fetch slow queries above, then Analyse to compute recommendations."
                    : "No actionable suggestions — queries are already well-indexed.")
            } else {
                recommendationsGrid(recs)
            }
        }
    }

    private func recommendationsGrid(_ recs: [IndexRecommendation]) -> some View {
        // Pair items two-per-row in a manual 2-col grid to allow per-item shadows.
        let columns: [GridItem] = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(recs) { rec in
                recommendationCard(rec)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func recommendationCard(_ rec: IndexRecommendation) -> some View {
        let impactKind: BadgeKind = {
            switch rec.impact {
            case .high:   return .danger
            case .medium: return .warning
            case .low:    return .neutral
            }
        }()
        let impactLabel: String = {
            switch rec.impact {
            case .high:   return "high impact"
            case .medium: return "medium impact"
            case .low:    return "low impact"
            }
        }()
        let savingsMs = rec.totalExecTimeMs
        // 0..2000ms range → 0..1 width
        let widthRatio = max(0.08, min(1.0, Double(savingsMs) / 2000.0))

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(impactLabel).pillBadge(impactKind)
                Text(rec.namespace)
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("\(rec.supportingQueries) queries")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }

            Text(rec.indexJSON)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Theme.textSoft)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface1)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: Theme.shadowAmbient, radius: 1, y: 0.5)

            HStack(spacing: 10) {
                Text("Predicted impact").sectionHeaderStyle()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.surface3)
                            .frame(height: 8)
                        Capsule()
                            .fill(Theme.brandGradient)
                            .frame(width: max(2, geo.size.width * widthRatio), height: 8)
                    }
                }
                .frame(height: 8)
                Text("−\(formatDuration(savingsMs))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.successDeep)
                    .frame(width: 60, alignment: .trailing)
            }

            Text(rec.rationale)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Spacer()
                Button {
                    viewModel.dismissRecommendation(rec)
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSoft)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    Task { await viewModel.createRecommendedIndex(rec) }
                } label: {
                    Text("Create index")
                }
                .buttonStyle(.accentCompact)
            }
        }
        .padding(14)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Section: Existing indexes (collection-scoped)

    private var existingIndexesSection: some View {
        investCard {
            sectionHead(
                title: "Existing indexes",
                sub: viewModel.activeTab.selectedCollection ?? "—",
                trailing: {
                    HStack(spacing: 6) {
                        AnyView(
                            Button {
                                Task { await viewModel.fetchIndexes() }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                                    Text("Refresh")
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSoft)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        )
                        AnyView(
                            Button {
                                showCreateIndexSheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                                    Text("Create")
                                }
                            }
                            .buttonStyle(.accentCompact)
                        )
                    }
                }
            )

            if viewModel.indexes.isEmpty {
                emptyRow(message: "No indexes loaded for this collection. Press Refresh to fetch.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.indexes.enumerated()), id: \.offset) { i, index in
                        existingIndexRow(index, isLast: i == viewModel.indexes.count - 1)
                    }
                }
            }
        }
    }

    private func existingIndexRow(_ index: [String: Any], isLast: Bool) -> some View {
        let name = index["name"] as? String ?? "unknown"
        let keyDict = index["key"] as? [String: Any] ?? [:]
        let isUnique = index["unique"] as? Bool ?? false
        let isSparse = index["sparse"] as? Bool ?? false
        let isPrimary = name == "_id_"
        let keyJSON = formatKeyPattern(keyDict)

        return HStack(spacing: 10) {
            Text(keyJSON)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSoft)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.surface1)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .shadow(color: Theme.shadowAmbient, radius: 1, y: 0.5)

            Text(name)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)

            if isPrimary { Text("primary").pillBadge(.neutral) }
            if isUnique  { Text("unique").pillBadge(.warning) }
            if isSparse  { Text("sparse").pillBadge(.info) }

            Spacer()

            if !isPrimary {
                Button {
                    dropIndexName = name
                    showDropIndexAlert = true
                } label: {
                    Text("Drop")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Theme.danger)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
        }
    }

    // MARK: - Card / table chrome

    @ViewBuilder
    private func investCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
    }

    @ViewBuilder
    private func sectionHead<Trailing: View>(title: String, sub: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(sub)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func tableHeader(_ cols: [(String, HorizontalAlignment, CGFloat?)]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cols.enumerated()), id: \.offset) { _, c in
                let (label, align, width) = c
                Text(label)
                    .sectionHeaderStyle()
                    .frame(maxWidth: width.map { _ in nil } ?? .infinity,
                           alignment: align == .trailing ? .trailing : .leading)
                    .frame(width: width, alignment: align == .trailing ? .trailing : .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.surface2)
    }

    @ViewBuilder
    private func tableRow<Content: View>(tint: Color?, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(tint ?? Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
    }

    private func emptyRow(message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
    }

    // MARK: - Sheets

    private var explainSheet: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Query Explain plan")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Detailed execution path for the active filter")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button("Done") { showExplainSheet = false }
                    .buttonStyle(.accent)
            }

            if let result = explainResult {
                ScrollView {
                    Text(prettyPrintJSON(result))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.codeFg)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(Theme.codeBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("No explain results.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Spacer()
                Button {
                    if let result = explainResult {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(prettyPrintJSON(result), forType: .string)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                }
                .buttonStyle(.ghost)
            }
        }
        .padding(20)
        .frame(width: 720, height: 520)
        .background(Theme.surface0)
    }

    private var createIndexSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Create index")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Cancel") { showCreateIndexSheet = false }
                    .buttonStyle(.ghost)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Index keys (JSON)").sectionHeaderStyle()
                TextField("{\"field\": 1}", text: $indexKeysJSON)
                    .textFieldStyle(.themed)
            }

            HStack(spacing: 18) {
                Toggle("Unique", isOn: $indexUnique).toggleStyle(.checkbox)
                Toggle("Sparse", isOn: $indexSparse).toggleStyle(.checkbox)
                Spacer()
            }

            HStack {
                Spacer()
                Button {
                    createIndexFromInput()
                    showCreateIndexSheet = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Create index")
                    }
                }
                .buttonStyle(.accent)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Theme.surface0)
    }

    // MARK: - Polling & helpers

    private func restartPolling() {
        refreshTask?.cancel()
        guard let seconds = refreshInterval.seconds else { return }
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if Task.isCancelled { break }
                await refreshAll()
            }
        }
    }

    private func refreshAll() async {
        await viewModel.refreshMetrics()
        await viewModel.fetchSlowQueries()
        if viewModel.activeTab.selectedCollection != nil {
            await viewModel.fetchIndexes()
        }
        lastRefreshAt = .now
    }

    private func createIndexFromInput() {
        guard let data = indexKeysJSON.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        var fields: [String: Int] = [:]
        for (key, value) in parsed {
            if let intVal = value as? Int { fields[key] = intVal }
            else if let numVal = value as? NSNumber { fields[key] = numVal.intValue }
        }
        guard !fields.isEmpty else { return }
        Task {
            await viewModel.createIndex(fields: fields, unique: indexUnique, sparse: indexSparse)
        }
    }

    private func exportReport() {
        reportDocument = InvestigateReportDocument.snapshot(from: viewModel)
        isExportingReport = true
    }

    private func queryPreview(_ command: String) -> String {
        let trimmed = command
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 90 { return trimmed }
        return String(trimmed.prefix(88)) + "…"
    }

    private func formatKeyPattern(_ dict: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    private func formatDuration(_ ms: Int) -> String {
        if ms >= 1000 { return String(format: "%.2fs", Double(ms) / 1000) }
        return "\(ms)ms"
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m)m \(s)s"
    }

    private static let exportFilenameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}

// MARK: - Investigate report (JSON snapshot)

/// Wraps current ops, slow queries, and index recommendations into a JSON
/// document suitable for `fileExporter`. Empty by default so the view's
/// initial state has something to bind to.
struct InvestigateReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    static let empty = InvestigateReportDocument(data: Data("{}".utf8))

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    @MainActor
    static func snapshot(from viewModel: AppViewModel) -> InvestigateReportDocument {
        let payload: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "connection": viewModel.connectionName,
            "currentOps": viewModel.currentOps.map { op -> [String: Any] in
                return [
                    "id": op.id,
                    "op": op.op,
                    "namespace": op.namespace,
                    "client": op.client,
                    "executionTimeMs": op.executionTimeMs,
                    "readLocks": op.readLocks,
                    "writeLocks": op.writeLocks,
                    "description": op.description
                ]
            },
            "slowQueries": viewModel.slowQueries.map { q -> [String: Any] in
                return [
                    "operation": q.operation,
                    "namespace": q.namespace,
                    "command": q.command,
                    "planSummary": q.planSummary,
                    "executionTimeMs": q.executionTimeMs,
                    "meanMs": q.meanMs,
                    "p99Ms": q.p99Ms,
                    "count": q.count,
                    "lastSeen": ISO8601DateFormatter().string(from: q.lastSeen),
                    "keysExamined": q.keysExamined,
                    "docsExamined": q.docsExamined
                ]
            },
            "indexRecommendations": viewModel.indexRecommendations.map { r -> [String: Any] in
                return [
                    "namespace": r.namespace,
                    "indexJSON": r.indexJSON,
                    "impact": r.impact.rawValue,
                    "rationale": r.rationale
                ]
            }
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]))
            ?? Data("{}".utf8)
        return InvestigateReportDocument(data: data)
    }
}
