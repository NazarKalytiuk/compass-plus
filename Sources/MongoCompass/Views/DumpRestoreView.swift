import SwiftUI
import AppKit

@MainActor
struct DumpRestoreView: View {
    @Environment(AppViewModel.self) private var viewModel

    // MARK: - Model

    enum OperationStatus: Equatable { case idle, running, complete, error }

    enum DumpScope: String, CaseIterable, Identifiable {
        case all = "All collections"
        case selected = "Selected…"
        case byRegex = "By regex"
        var id: String { rawValue }
    }

    enum RestoreStrategy: String, CaseIterable, Identifiable {
        case dropRestore = "Drop + restore"
        case merge = "Merge"
        case skipExisting = "Skip existing"
        var id: String { rawValue }
    }

    enum ActiveOp { case dump, restore }

    struct LogLine: Identifiable {
        let id = UUID()
        let timestamp: Date
        let kind: Kind
        let text: String
        enum Kind { case info, ok, warn, err, plain }
    }

    struct ExtraToggle: Identifiable {
        var id: String { label }
        let label: String
        let on: Bool
        let toggle: () -> Void
    }

    // MARK: - State (Dump)

    @State private var dumpDatabase = ""
    @State private var dumpCollection = ""
    @State private var dumpScope: DumpScope = .all
    @State private var dumpOutputPath = ""
    @State private var dumpGzip = true
    @State private var dumpParallel: Double = 4
    @State private var dumpOplog = true
    @State private var dumpExcludeIndexes = false
    @State private var dumpStatus: OperationStatus = .idle

    // MARK: - State (Restore)

    @State private var restoreInputPath = ""
    @State private var restoreTargetDatabase = ""
    @State private var restoreStrategy: RestoreStrategy = .dropRestore
    @State private var restoreGzip = true
    @State private var restoreParallel: Double = 6
    @State private var restoreOplogReplay = true
    @State private var restoreMaintainOrder = true
    @State private var restoreNoIndexRestore = false
    @State private var restoreStatus: OperationStatus = .idle

    // MARK: - State (Log)

    @State private var logLines: [LogLine] = []
    @State private var activeOp: ActiveOp? = nil
    @State private var startedAt: Date? = nil

    // MARK: - State (Presets)

    @State private var showSavePresetSheet = false
    @State private var presetName = ""
    @State private var presets: [DumpPreset] = []

    // MARK: - State (Estimated size)

    @State private var estSizeBytes: Int64?
    @State private var isEstimating = false

    private static let logTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface0)
        .sheet(isPresented: $showSavePresetSheet) { savePresetSheet }
        .onAppear {
            hydrate()
            presets = viewModel.storageService.loadDumpPresets()
            Task { await refreshEstimatedSize() }
        }
        .onChange(of: dumpDatabase) { _, _ in Task { await refreshEstimatedSize() } }
        .onChange(of: dumpCollection) { _, _ in Task { await refreshEstimatedSize() } }
        .onChange(of: dumpScope) { _, _ in Task { await refreshEstimatedSize() } }
    }

    private var savePresetSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save preset")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Preset name").sectionHeaderStyle()
                TextField("e.g. Production nightly", text: $presetName)
                    .textFieldStyle(.themedSans)
            }

            Text("Captures both Dump and Restore form state.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)

            HStack {
                Button("Cancel") { showSavePresetSheet = false }
                    .buttonStyle(.ghost)
                Spacer()
                Button("Save") {
                    let preset = currentPreset(name: presetName.trimmingCharacters(in: .whitespaces))
                    viewModel.storageService.saveDumpPreset(preset)
                    presets = viewModel.storageService.loadDumpPresets()
                    showSavePresetSheet = false
                }
                .buttonStyle(.accent)
                .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func currentPreset(name: String) -> DumpPreset {
        DumpPreset(
            name: name,
            dumpDatabase: dumpDatabase,
            dumpCollection: dumpCollection,
            dumpScope: dumpScope.rawValue,
            dumpOutputPath: dumpOutputPath,
            dumpGzip: dumpGzip,
            dumpParallel: Int(dumpParallel),
            dumpOplog: dumpOplog,
            dumpExcludeIndexes: dumpExcludeIndexes,
            restoreInputPath: restoreInputPath,
            restoreTargetDatabase: restoreTargetDatabase,
            restoreStrategy: restoreStrategy.rawValue,
            restoreGzip: restoreGzip,
            restoreParallel: Int(restoreParallel),
            restoreOplogReplay: restoreOplogReplay,
            restoreMaintainOrder: restoreMaintainOrder,
            restoreNoIndexRestore: restoreNoIndexRestore
        )
    }

    private func applyPreset(_ preset: DumpPreset) {
        dumpDatabase = preset.dumpDatabase
        dumpCollection = preset.dumpCollection
        if let scope = DumpScope(rawValue: preset.dumpScope) { dumpScope = scope }
        dumpOutputPath = preset.dumpOutputPath
        dumpGzip = preset.dumpGzip
        dumpParallel = Double(preset.dumpParallel)
        dumpOplog = preset.dumpOplog
        dumpExcludeIndexes = preset.dumpExcludeIndexes

        restoreInputPath = preset.restoreInputPath
        restoreTargetDatabase = preset.restoreTargetDatabase
        if let strat = RestoreStrategy(rawValue: preset.restoreStrategy) { restoreStrategy = strat }
        restoreGzip = preset.restoreGzip
        restoreParallel = Double(preset.restoreParallel)
        restoreOplogReplay = preset.restoreOplogReplay
        restoreMaintainOrder = preset.restoreMaintainOrder
        restoreNoIndexRestore = preset.restoreNoIndexRestore
    }

    private func deletePreset(_ preset: DumpPreset) {
        viewModel.storageService.removeDumpPreset(id: preset.id)
        presets = viewModel.storageService.loadDumpPresets()
    }

    private func hydrate() {
        if dumpDatabase.isEmpty, let db = viewModel.activeTab.selectedDatabase {
            dumpDatabase = db
        }
        if dumpCollection.isEmpty, let col = viewModel.activeTab.selectedCollection {
            dumpCollection = col
            if dumpScope == .all { dumpScope = .selected }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            breadcrumb
            Text(toolPillLabel)
                .pillBadge(viewModel.dumpRestoreService.isDumpAvailable ? .info : .warning)
            Spacer()
            loadPresetMenu
            toolbarGhostButton("View history") {}
            toolbarGhostButton("Schedule…") {}
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface1)
        .shadow(color: Theme.shadowAmbient.opacity(0.6), radius: 0.5, y: 0.5)
    }

    private var loadPresetMenu: some View {
        Menu {
            if presets.isEmpty {
                Text("No saved presets")
            } else {
                ForEach(presets) { preset in
                    Button(preset.name) { applyPreset(preset) }
                }
                Divider()
                Menu("Delete preset") {
                    ForEach(presets) { preset in
                        Button("Delete '\(preset.name)'") { deletePreset(preset) }
                    }
                }
            }
        } label: {
            Text("Presets")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textSoft)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var toolPillLabel: String {
        viewModel.dumpRestoreService.isDumpAvailable ? "mongodump" : "mongodump missing"
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isConnected ? Theme.success : Theme.textMuted)
                .frame(width: 7, height: 7)
                .padding(.trailing, 2)
            Text(connectionLabel)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            Text("dump / restore")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var connectionLabel: String {
        viewModel.connectionName.isEmpty ? "cluster" : viewModel.connectionName
    }

    private func toolbarGhostButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textSoft)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content layout

    private var content: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                dumpCard
                restoreCard
            }
            logCard
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    // MARK: - Dump card

    private var dumpCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            opHead(
                symbol: "arrow.down",
                gradient: Theme.brandGradient,
                title: "Dump",
                subtitle: "export a BSON snapshot to local disk"
            ) {
                dumpStatusPill
            }

            formRow(label: "Source") {
                dumpSourceDropdown
            }
            formRow(label: "Scope") {
                dumpScopeRow
            }
            formRow(label: "Output folder") {
                pathField(text: $dumpOutputPath, placeholder: "~/Backups/…", chooseFiles: false)
            }
            formRow(label: "Compression") {
                toggleRow(
                    value: $dumpGzip,
                    label: "gzip",
                    flag: "(--gzip)",
                    aside: dumpGzip ? "compressed output" : "uncompressed"
                )
            }
            formRow(label: "Parallel") {
                sliderRow(value: $dumpParallel, max: 8)
            }
            formRow(label: "Extras") {
                extrasRow(items: dumpExtrasItems)
            }

            opSummary([
                ("Est. size", dumpEstSizeLabel),
                ("Collections", dumpCollectionsCountLabel),
                ("ETA", "—")
            ])

            HStack(spacing: 8) {
                ctaGhostButton("Dry run") { dryRunDump() }
                ctaGhostButton("Save preset…") { presetName = ""; showSavePresetSheet = true }
                Spacer()
                Button { runDump() } label: {
                    Text("Start dump")
                }
                .buttonStyle(.accent)
                .disabled(isDumpDisabled)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var dumpStatusPill: some View {
        if !viewModel.dumpRestoreService.isDumpAvailable {
            Text("tool missing").pillBadge(.warning)
        } else if !viewModel.isConnected {
            Text("offline").pillBadge(.danger)
        } else if dumpStatus == .running {
            Text("running").pillBadge(.warning)
        } else {
            Text("connected").pillBadge(.success)
        }
    }

    private var dumpScopeRow: some View {
        HStack(spacing: 6) {
            ForEach(DumpScope.allCases) { scope in
                chkPill(label: scope.rawValue, isOn: dumpScope == scope, mono: false) {
                    dumpScope = scope
                }
            }
        }
    }

    private var dumpSourceDropdown: some View {
        let sourceText = dumpSourceLabel
        let placeholder = dumpDatabase.isEmpty
        return Menu {
            ForEach(viewModel.databases, id: \.self) { d in
                Menu(d) {
                    Button("All collections") {
                        dumpDatabase = d
                        dumpCollection = ""
                        if dumpScope == .selected { dumpScope = .all }
                    }
                    if let cs = viewModel.collections[d], !cs.isEmpty {
                        Divider()
                        ForEach(cs, id: \.self) { c in
                            Button(c) {
                                dumpDatabase = d
                                dumpCollection = c
                                dumpScope = .selected
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.isConnected ? Theme.success : Theme.textMuted)
                    .frame(width: 7, height: 7)
                Text(sourceText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(placeholder ? Theme.textMuted : Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surface3)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var dumpSourceLabel: String {
        if dumpDatabase.isEmpty {
            return viewModel.databases.isEmpty ? "no databases" : "select database…"
        }
        let prefix = connectionLabel
        let suffix = (dumpScope == .selected && !dumpCollection.isEmpty)
            ? "\(dumpDatabase).\(dumpCollection)"
            : dumpDatabase
        return "\(prefix) · \(suffix)"
    }

    private var dumpCollectionsCountLabel: String {
        if dumpScope == .selected, !dumpCollection.isEmpty { return "1" }
        if !dumpDatabase.isEmpty, let cs = viewModel.collections[dumpDatabase] {
            return String(cs.count)
        }
        return "—"
    }

    private var dumpEstSizeLabel: String {
        if isEstimating { return "estimating…" }
        guard let bytes = estSizeBytes else {
            return dumpGzip ? "smaller (gzip)" : "raw bson"
        }
        let effective: Int64 = dumpGzip ? Int64(Double(bytes) * 0.25) : bytes
        return formatSize(effective) + (dumpGzip ? " (gzip ~)" : "")
    }

    private func formatSize(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024)
    }

    /// Refresh `estSizeBytes` from `collStats` whenever the user changes
    /// database/collection/scope. For "All collections" we sum the stats
    /// across every collection in the database.
    private func refreshEstimatedSize() async {
        guard !dumpDatabase.isEmpty else {
            estSizeBytes = nil
            return
        }
        isEstimating = true
        defer { isEstimating = false }

        do {
            if dumpScope == .selected, !dumpCollection.isEmpty {
                let stats = try await viewModel.mongoService.getCollStats(
                    database: dumpDatabase, collection: dumpCollection
                )
                estSizeBytes = readSize(from: stats)
            } else {
                let colls = viewModel.collections[dumpDatabase] ?? []
                var total: Int64 = 0
                for c in colls {
                    if let stats = try? await viewModel.mongoService.getCollStats(database: dumpDatabase, collection: c),
                       let s = readSize(from: stats) {
                        total += s
                    }
                }
                estSizeBytes = total > 0 ? total : nil
            }
        } catch {
            estSizeBytes = nil
        }
    }

    private func readSize(from stats: [String: Any]) -> Int64? {
        if let s = stats["size"] as? Int { return Int64(s) }
        if let s = stats["size"] as? Int64 { return s }
        if let s = stats["size"] as? Double { return Int64(s) }
        return nil
    }

    private var dumpExtrasItems: [ExtraToggle] {
        [
            ExtraToggle(label: "--oplog", on: dumpOplog) { dumpOplog.toggle() },
            ExtraToggle(label: "--numParallelCollections=\(Int(dumpParallel))", on: true) {},
            ExtraToggle(label: "--excludeIndexes", on: dumpExcludeIndexes) { dumpExcludeIndexes.toggle() }
        ]
    }

    private var isDumpDisabled: Bool {
        dumpDatabase.isEmpty
            || dumpOutputPath.isEmpty
            || activeOp != nil
            || !viewModel.dumpRestoreService.isDumpAvailable
            || !viewModel.isConnected
    }

    // MARK: - Restore card

    private var restoreCard: some View {
        let restoreGradient = LinearGradient(
            colors: [Theme.info, Color(red: 0.357, green: 0.553, blue: 0.937)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        return VStack(alignment: .leading, spacing: 12) {
            opHead(
                symbol: "arrow.up",
                gradient: restoreGradient,
                title: "Restore",
                subtitle: "load a BSON snapshot into a target cluster"
            ) {
                restoreStatusPill
            }

            formRow(label: "Snapshot") {
                pathField(text: $restoreInputPath, placeholder: "/path/to/dump", chooseFiles: true)
            }
            formRow(label: "Target") {
                restoreTargetField
            }
            formRow(label: "Strategy") {
                restoreStrategyRow
            }
            formRow(label: "Decompress") {
                toggleRow(
                    value: $restoreGzip,
                    label: "gzip",
                    flag: "(--gzip)",
                    aside: "auto-detected"
                )
            }
            formRow(label: "Parallel") {
                sliderRow(value: $restoreParallel, max: 8)
            }
            formRow(label: "Extras") {
                extrasRow(items: restoreExtrasItems)
            }

            opSummary([
                ("Source size", "—"),
                ("Collections", "—"),
                ("ETA", "—")
            ])

            HStack(spacing: 8) {
                ctaGhostButton("Dry run") { dryRunRestore() }
                ctaGhostButton("Save preset…") { presetName = ""; showSavePresetSheet = true }
                Spacer()
                Button { runRestore() } label: {
                    Text("Start restore")
                }
                .buttonStyle(.accent)
                .disabled(isRestoreDisabled)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var restoreStatusPill: some View {
        if !viewModel.dumpRestoreService.isRestoreAvailable {
            Text("tool missing").pillBadge(.warning)
        } else if !viewModel.isConnected {
            Text("offline").pillBadge(.danger)
        } else if restoreStatus == .running {
            Text("restoring").pillBadge(.warning)
        } else {
            Text("target = \(connectionLabel)").pillBadge(.warning)
        }
    }

    private var restoreStrategyRow: some View {
        HStack(spacing: 6) {
            ForEach(RestoreStrategy.allCases) { s in
                chkPill(label: s.rawValue, isOn: restoreStrategy == s, mono: false) {
                    restoreStrategy = s
                }
            }
        }
    }

    private var restoreTargetField: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.isConnected ? Theme.warning : Theme.textMuted)
                .frame(width: 7, height: 7)
            TextField("optional target database override", text: $restoreTargetDatabase)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surface3)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var restoreExtrasItems: [ExtraToggle] {
        [
            ExtraToggle(label: "--oplogReplay", on: restoreOplogReplay) { restoreOplogReplay.toggle() },
            ExtraToggle(label: "--maintainInsertionOrder", on: restoreMaintainOrder) { restoreMaintainOrder.toggle() },
            ExtraToggle(label: "--noIndexRestore", on: restoreNoIndexRestore) { restoreNoIndexRestore.toggle() }
        ]
    }

    private var isRestoreDisabled: Bool {
        restoreInputPath.isEmpty
            || activeOp != nil
            || !viewModel.dumpRestoreService.isRestoreAvailable
            || !viewModel.isConnected
    }

    // MARK: - Log card

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            logHeader
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)
            logStream
                .padding(.horizontal, 14)
        }
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
        .frame(minHeight: 240, maxHeight: .infinity, alignment: .top)
    }

    private var logHeader: some View {
        HStack(spacing: 10) {
            Text("Live output")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            logHeaderStatusPill
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(metaLabel)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            toolbarGhostButton("Copy log") { copyLog() }
            toolbarGhostButton("Clear") { logLines.removeAll() }
        }
    }

    @ViewBuilder
    private var logHeaderStatusPill: some View {
        if activeOp == .dump {
            Text("dumping…").pillBadge(.warning)
        } else if activeOp == .restore {
            Text("restoring…").pillBadge(.warning)
        } else if dumpStatus == .complete || restoreStatus == .complete {
            Text("complete").pillBadge(.success)
        } else if dumpStatus == .error || restoreStatus == .error {
            Text("error").pillBadge(.danger)
        } else {
            Text("idle").pillBadge(.neutral)
        }
    }

    private var metaLabel: String {
        guard let start = startedAt else { return "no run yet" }
        let elapsed = max(0, Int(Date().timeIntervalSince(start)))
        let tool: String
        switch activeOp {
        case .dump: tool = "mongodump"
        case .restore: tool = "mongorestore"
        case .none: tool = "mongo"
        }
        if activeOp != nil {
            return "\(tool) · running \(elapsed)s"
        }
        return "\(tool) · finished · \(logLines.count) lines"
    }

    private var logStream: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if logLines.isEmpty {
                        Text("Awaiting output…")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.codeMuted)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(logLines) { line in
                            logLineView(line)
                                .id(line.id)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.codeBg)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 6,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 6,
                    style: .continuous
                )
            )
            .onChange(of: logLines.count) { _, _ in
                if let last = logLines.last {
                    withAnimation(.linear(duration: 0.08)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if activeOp != nil, !logLines.isEmpty {
                    scrollPin
                        .padding(.trailing, 14)
                        .padding(.bottom, 14)
                }
            }
        }
    }

    private func logLineView(_ line: LogLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Self.logTimeFormatter.string(from: line.timestamp))
                .foregroundStyle(Theme.codeMuted)
            if line.kind != .plain {
                Text(tagLabel(line.kind))
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .tracking(0.95)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(tagColor(line.kind))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Text(line.text)
                .foregroundStyle(Theme.codeFg)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .lineLimit(nil)
    }

    private var scrollPin: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down")
                .font(.system(size: 9, weight: .bold))
            Text("latest")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.primary)
        .clipShape(Capsule())
        .shadow(color: Theme.primary.opacity(0.4), radius: 12, y: 4)
    }

    private func tagLabel(_ kind: LogLine.Kind) -> String {
        switch kind {
        case .info: return "INFO"
        case .ok:   return "OK"
        case .warn: return "WARN"
        case .err:  return "ERR"
        case .plain: return ""
        }
    }

    private func tagColor(_ kind: LogLine.Kind) -> Color {
        switch kind {
        case .info: return Theme.info
        case .ok:   return Theme.successDeep
        case .warn: return Theme.warningDeep
        case .err:  return Theme.dangerDeep
        case .plain: return Theme.codeMuted
        }
    }

    // MARK: - Reusable building blocks

    private func opHead<Pill: View>(
        symbol: String,
        gradient: LinearGradient,
        title: String,
        subtitle: String,
        @ViewBuilder pill: () -> Pill
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(gradient)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
            Spacer()
            pill()
        }
    }

    private func formRow<Trailing: View>(
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textMuted)
                .frame(width: 100, alignment: .leading)
            trailing()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chkPill(
        label: String,
        isOn: Bool,
        mono: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.primary)
                }
                Text(label)
                    .font(.system(
                        size: 11.5,
                        weight: isOn ? .semibold : .regular,
                        design: mono ? .monospaced : .default
                    ))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(isOn ? Theme.primaryDeep : Theme.textSoft)
            .background(isOn ? Theme.primaryTint : Theme.surface3)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func extrasRow(items: [ExtraToggle]) -> some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                chkPill(label: item.label, isOn: item.on, mono: true, action: item.toggle)
            }
        }
    }

    private func pathField(
        text: Binding<String>,
        placeholder: String,
        chooseFiles: Bool
    ) -> some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .padding(.leading, 10)
            Button {
                chooseFolder(chooseFiles: chooseFiles) { path in
                    text.wrappedValue = path
                }
            } label: {
                Text("Browse…")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .shadow(color: Theme.shadowAmbient.opacity(0.6), radius: 1, y: 0.5)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
        .padding(.vertical, 4)
        .background(Theme.surface3)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func toggleRow(
        value: Binding<Bool>,
        label: String,
        flag: String,
        aside: String
    ) -> some View {
        HStack(spacing: 10) {
            pillToggle(isOn: value)
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSoft)
                Text(flag)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Text(aside)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)
        }
    }

    private func pillToggle(isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                Capsule()
                    .fill(isOn.wrappedValue
                          ? Theme.primary
                          : Color(red: 0.784, green: 0.761, blue: 0.718))
                    .frame(width: 30, height: 17)
                Circle()
                    .fill(.white)
                    .frame(width: 13, height: 13)
                    .padding(.horizontal, 2)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func sliderRow(value: Binding<Double>, max maxVal: Double) -> some View {
        HStack(spacing: 12) {
            Slider(value: value, in: 1...maxVal, step: 1)
                .tint(Theme.primary)
                .controlSize(.small)
            Text("\(Int(value.wrappedValue)) / \(Int(maxVal))")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func opSummary(_ items: [(String, String)]) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0)
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.84)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.textMuted)
                    Text(item.1)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textSoft)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface3)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func ctaGhostButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSoft)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.surface3)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func runDump() {
        guard !dumpDatabase.isEmpty, !dumpOutputPath.isEmpty else { return }

        logLines.removeAll()
        dumpStatus = .running
        restoreStatus = .idle
        activeOp = .dump
        startedAt = Date()

        let uri = viewModel.connectionURI.isEmpty
            ? "mongodb://localhost:27017"
            : viewModel.connectionURI
        let coll = (dumpScope == .selected && !dumpCollection.isEmpty) ? dumpCollection : nil

        let stream = viewModel.dumpRestoreService.dump(
            uri: uri,
            database: dumpDatabase,
            collection: coll,
            outputPath: dumpOutputPath,
            gzip: dumpGzip,
            oplog: dumpOplog,
            numParallel: Int(dumpParallel),
            excludeIndexes: dumpExcludeIndexes
        )

        Task {
            for await raw in stream {
                await MainActor.run { appendLog(raw) }
            }
            await MainActor.run { finishLog(for: .dump) }
        }
    }

    private func runRestore() {
        guard !restoreInputPath.isEmpty else { return }

        logLines.removeAll()
        restoreStatus = .running
        dumpStatus = .idle
        activeOp = .restore
        startedAt = Date()

        let uri = viewModel.connectionURI.isEmpty
            ? "mongodb://localhost:27017"
            : viewModel.connectionURI
        let db = restoreTargetDatabase.isEmpty ? nil : restoreTargetDatabase

        // Strategy → flag mapping (see RestoreStrategy enum).
        let drop = restoreStrategy == .dropRestore
        let noObjcheck = restoreStrategy == .merge
        let stopOnError = restoreStrategy == .skipExisting

        let stream = viewModel.dumpRestoreService.restore(
            uri: uri,
            inputPath: restoreInputPath,
            database: db,
            drop: drop,
            oplogReplay: restoreOplogReplay,
            numParallel: Int(restoreParallel),
            noIndexRestore: restoreNoIndexRestore,
            maintainInsertionOrder: restoreMaintainOrder,
            gzip: restoreGzip,
            stopOnError: stopOnError,
            noObjcheck: noObjcheck
        )

        Task {
            for await raw in stream {
                await MainActor.run { appendLog(raw) }
            }
            await MainActor.run { finishLog(for: .restore) }
        }
    }

    private func appendLog(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        logLines.append(LogLine(timestamp: Date(), kind: classify(trimmed), text: trimmed))
    }

    // MARK: - Dry run

    /// Render the command line that `Start dump` would launch, without
    /// actually spawning mongodump. Lands in the live-output panel as a
    /// single info-tagged line so users can copy it for CI / scripts.
    private func dryRunDump() {
        guard !dumpDatabase.isEmpty, !dumpOutputPath.isEmpty else { return }
        let uri = viewModel.connectionURI.isEmpty
            ? "mongodb://localhost:27017"
            : viewModel.connectionURI

        var args: [String] = ["mongodump", "--uri", quote(uri), "--db", dumpDatabase, "--out", quote(dumpOutputPath)]
        if dumpScope == .selected, !dumpCollection.isEmpty {
            args.append(contentsOf: ["--collection", dumpCollection])
        }
        if dumpGzip { args.append("--gzip") }
        if dumpOplog, dumpScope != .selected { args.append("--oplog") }
        if dumpExcludeIndexes { args.append("--excludeIndexes") }
        args.append("--numParallelCollections=\(Int(dumpParallel))")
        logLines.append(LogLine(timestamp: Date(), kind: .info, text: args.joined(separator: " ")))
    }

    /// Dry-run mirror of runRestore.
    private func dryRunRestore() {
        guard !restoreInputPath.isEmpty else { return }
        let uri = viewModel.connectionURI.isEmpty
            ? "mongodb://localhost:27017"
            : viewModel.connectionURI

        var args: [String] = ["mongorestore", "--uri", quote(uri)]
        if !restoreTargetDatabase.isEmpty {
            args.append(contentsOf: ["--db", restoreTargetDatabase])
        }
        switch restoreStrategy {
        case .dropRestore: args.append("--drop")
        case .merge:       args.append("--noObjcheck")
        case .skipExisting: args.append("--stopOnError")
        }
        if restoreOplogReplay { args.append("--oplogReplay") }
        if restoreNoIndexRestore { args.append("--noIndexRestore") }
        if restoreMaintainOrder { args.append("--maintainInsertionOrder") }
        if restoreGzip { args.append("--gzip") }
        args.append("--numParallelCollections=\(Int(restoreParallel))")
        args.append(quote(restoreInputPath))
        logLines.append(LogLine(timestamp: Date(), kind: .info, text: args.joined(separator: " ")))
    }

    private func quote(_ s: String) -> String {
        s.contains(" ") ? "\"\(s)\"" : s
    }

    private func classify(_ raw: String) -> LogLine.Kind {
        let lower = raw.lowercased()
        if lower.contains("error launching") || lower.contains("failed") {
            return .err
        }
        if lower.contains("exit code") {
            return lower.contains("exit code 0") ? .ok : .err
        }
        if lower.contains("error") { return .err }
        if lower.contains("warn") { return .warn }
        if lower.contains("successfully")
            || lower.contains("done dumping")
            || lower.contains("done restoring")
            || lower.contains("finished") {
            return .ok
        }
        return .info
    }

    private func finishLog(for op: ActiveOp) {
        let hasError = logLines.contains { $0.kind == .err }
        let status: OperationStatus = hasError ? .error : .complete
        switch op {
        case .dump:    dumpStatus = status
        case .restore: restoreStatus = status
        }
        activeOp = nil
    }

    private func copyLog() {
        let text = logLines
            .map { "\(Self.logTimeFormatter.string(from: $0.timestamp))  \($0.text)" }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func chooseFolder(chooseFiles: Bool, completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = chooseFiles
        panel.allowsMultipleSelection = false
        panel.message = chooseFiles ? "Select a snapshot folder or archive" : "Select an output folder"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            completion(url.path)
        }
    }
}
