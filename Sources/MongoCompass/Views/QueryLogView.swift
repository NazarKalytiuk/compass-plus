import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
struct QueryLogView: View {
    @Environment(AppViewModel.self) private var viewModel

    // MARK: - Filter state

    @State private var searchText = ""
    @State private var selectedOperations: Set<QueryLogEntry.OperationType> =
        Set(QueryLogEntry.OperationType.allCases)
    @State private var selectedCollections: Set<String> = []
    @State private var collectionsHydrated = false
    @State private var showSuccess = true
    @State private var showErrors = true
    @State private var showSlowOnly = false
    @State private var clientFilter = ""
    @State private var quickRange: QuickRange = .all
    @State private var customRangeStart: Date = Date().addingTimeInterval(-3600)
    @State private var customRangeEnd: Date = Date()

    // MARK: - UI state

    @State private var expandedEntryId: UUID? = nil
    @State private var detailTab: DetailTab = .query
    @State private var showClearAlert = false
    @State private var showExporter = false
    @State private var exportPayload: QueryLogExportDocument? = nil

    enum QuickRange: String, CaseIterable, Identifiable {
        case fiveMin = "5m"
        case oneHr   = "1h"
        case fourHr  = "4h"
        case today
        case all
        case custom
        var id: String { rawValue }
        var seconds: TimeInterval? {
            switch self {
            case .fiveMin: return 5 * 60
            case .oneHr:   return 3600
            case .fourHr:  return 4 * 3600
            case .today:   return 86400
            case .all, .custom: return nil
            }
        }
        var label: String {
            switch self {
            case .fiveMin: return "5m"
            case .oneHr:   return "1h"
            case .fourHr:  return "4h"
            case .today:   return "today"
            case .all:     return "all"
            case .custom:  return "custom"
            }
        }
    }

    enum DetailTab: String, CaseIterable, Identifiable {
        case query   = "Query"
        case explain = "Explain"
        case trace   = "Trace"
        case headers = "Client headers"
        var id: String { rawValue }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface0)
        .onAppear { hydrateCollectionsIfNeeded() }
        .alert("Clear query log?", isPresented: $showClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                viewModel.clearQueryLog()
            }
        } message: {
            Text("This removes all locally recorded query entries. This action cannot be undone.")
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportPayload,
            contentType: .json,
            defaultFilename: "query-log-\(Self.exportTimestamp()).json"
        ) { _ in }
    }

    private func hydrateCollectionsIfNeeded() {
        if !collectionsHydrated {
            selectedCollections = Set(viewModel.queryLog.map { "\($0.database).\($0.collection)" })
            collectionsHydrated = true
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            breadcrumb
            searchField
                .frame(width: 320)
            Spacer()
            Text(metaLabel)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
            ghostBtn("Export") { exportLog() }
                .disabled(viewModel.queryLog.isEmpty)
            ghostBtn("Clear log…") { showClearAlert = true }
                .disabled(viewModel.queryLog.isEmpty)
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
            Text(connectionLabel)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            Text("query log")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var connectionLabel: String {
        viewModel.connectionName.isEmpty ? "cluster" : viewModel.connectionName
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)
            TextField("Filter by query, op, regex…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surface3)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var metaLabel: String {
        let total = viewModel.queryLog.count
        let approxBytes = total * 320
        return "\(total.formatted()) entries · \(formatBytes(approxBytes))"
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / 1024.0 / 1024.0)
        }
        if bytes >= 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        }
        return "\(bytes) B"
    }

    private func ghostBtn(_ title: String, action: @escaping () -> Void) -> some View {
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

    // MARK: - Content (filters | list)

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            filtersPanel
                .frame(width: 280)
            logList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    // MARK: - Filters panel

    private var filtersPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                timeRangeBlock
                collectionsBlock
                operationsBlock
                resultBlock
                clientBlock
                actionsBlock
            }
        }
        .padding(14)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
        .frame(maxHeight: .infinity)
    }

    private func blockHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textMuted)
    }

    private var timeRangeBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            blockHeader("Time range")
            if quickRange == .custom {
                VStack(spacing: 6) {
                    DatePicker("From", selection: $customRangeStart, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    DatePicker("To", selection: $customRangeEnd, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 6) {
                    Text(rangeLabel(.start))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.textSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Theme.surface3)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(rangeLabel(.end))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.textSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Theme.surface3)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            WrapHStack(spacing: 4, lineSpacing: 4) {
                ForEach(QuickRange.allCases) { qr in
                    Button {
                        quickRange = qr
                    } label: {
                        Text(qr.label)
                            .pillBadge(quickRange == qr ? .accent : .neutral)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
    }

    private enum RangeSide { case start, end }
    private func rangeLabel(_ side: RangeSide) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let now = Date()
        if let secs = quickRange.seconds {
            let from = now.addingTimeInterval(-secs)
            return side == .start ? formatter.string(from: from) : formatter.string(from: now)
        }
        if let first = viewModel.queryLog.last?.timestamp,
           let last = viewModel.queryLog.first?.timestamp {
            return side == .start ? formatter.string(from: first) : formatter.string(from: last)
        }
        return formatter.string(from: now)
    }

    private var collectionsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            blockHeader("Collections")
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(collectionCounts, id: \.name) { item in
                        collectionPickRow(item)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    private struct CollectionCount: Hashable {
        let name: String
        let count: Int
    }

    private var collectionCounts: [CollectionCount] {
        var counts: [String: Int] = [:]
        for entry in viewModel.queryLog {
            let key = "\(entry.database).\(entry.collection)"
            counts[key, default: 0] += 1
        }
        return counts
            .map { CollectionCount(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private func collectionPickRow(_ item: CollectionCount) -> some View {
        let isOn = selectedCollections.contains(item.name)
        return HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(isOn ? Theme.primary : Theme.surface3)
                    .frame(width: 14, height: 14)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            Text(item.name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(item.count.formatted())")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isOn ? Theme.surfaceActive.opacity(0.4) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture {
            if isOn { selectedCollections.remove(item.name) }
            else    { selectedCollections.insert(item.name) }
        }
    }

    private var operationsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            blockHeader("Operations")
            WrapHStack(spacing: 4, lineSpacing: 4) {
                opChip("query",     kind: .info,    backing: .find)
                opChip("insert",    kind: .success, backing: .insert)
                opChip("update",    kind: .warning, backing: .update)
                opChip("delete",    kind: .danger,  backing: .delete)
                opChip("aggregate", kind: .violet,  backing: .aggregate)
                offChip("command")
                offChip("getMore")
                offChip("count")
            }
        }
    }

    private func opChip(
        _ label: String,
        kind: BadgeKind,
        backing op: QueryLogEntry.OperationType
    ) -> some View {
        let isOn = selectedOperations.contains(op)
        return Button {
            if isOn { selectedOperations.remove(op) }
            else    { selectedOperations.insert(op) }
        } label: {
            Text(label)
                .pillBadge(isOn ? kind : .neutral)
                .opacity(isOn ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }

    private func offChip(_ label: String) -> some View {
        Text(label)
            .pillBadge(.neutral)
            .opacity(0.4)
    }

    private var resultBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            blockHeader("Result")
            toggleLine(label: "Success", color: Theme.success, isOn: $showSuccess)
            toggleLine(label: "Errors",  color: Theme.danger,  isOn: $showErrors)
            toggleLine(label: "Slow (> 100ms)", color: Theme.warning, isOn: $showSlowOnly)
        }
    }

    private func toggleLine(label: String, color: Color, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 13, height: 13)
                .overlay(Circle().fill(color).frame(width: 7, height: 7))
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSoft)
            Spacer()
            pillToggle(isOn: isOn)
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

    private var clientBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            blockHeader("Client")
            TextField("api-gw-* | checkout-*", text: $clientFilter)
                .textFieldStyle(.themed)
        }
    }

    private var actionsBlock: some View {
        VStack(spacing: 6) {
            Button {
                // Filters are reactive — this button is for symmetry / explicit feedback.
            } label: {
                Text("Apply · \(activeFilterCount) filters")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.accent)

            Button {
                resetFilters()
            } label: {
                Text("Reset")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 1)
            }
            .buttonStyle(.ghost)
        }
        .padding(.top, 4)
    }

    private var activeFilterCount: Int {
        var n = 0
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty { n += 1 }
        if quickRange != .all { n += 1 }
        if !clientFilter.trimmingCharacters(in: .whitespaces).isEmpty { n += 1 }
        if selectedOperations != Set(QueryLogEntry.OperationType.allCases) { n += 1 }
        let allColls = Set(collectionCounts.map(\.name))
        if !allColls.isEmpty, selectedCollections != allColls { n += 1 }
        if !showSuccess { n += 1 }
        if !showErrors  { n += 1 }
        if showSlowOnly { n += 1 }
        return n
    }

    private func resetFilters() {
        searchText = ""
        selectedOperations = Set(QueryLogEntry.OperationType.allCases)
        selectedCollections = Set(collectionCounts.map(\.name))
        showSuccess = true
        showErrors = true
        showSlowOnly = false
        clientFilter = ""
        quickRange = .all
    }

    // MARK: - Log list

    private var logList: some View {
        Group {
            if filteredLog.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredLog) { entry in
                            logCard(entry)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.primaryTint)
                    .frame(width: 48, height: 48)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.primaryDeep)
            }
            Text(viewModel.queryLog.isEmpty ? "No queries recorded yet" : "No matches for active filters")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(viewModel.queryLog.isEmpty
                 ? "Queries you run in the Explorer or Aggregations view will appear here."
                 : "Loosen the filters in the left panel or reset them.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Log card

    private func logCard(_ entry: QueryLogEntry) -> some View {
        let isOpen = expandedEntryId == entry.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    if isOpen {
                        expandedEntryId = nil
                    } else {
                        expandedEntryId = entry.id
                        detailTab = .query
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(opLabel(entry.operationType))
                    .pillBadge(opBadgeKind(entry.operationType))
                    .frame(width: 80, alignment: .leading)

                nsLabel(entry)
                    .frame(maxWidth: .infinity, alignment: .leading)

                msPill(entry.executionTimeMs)
                statusPill(entry)

                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 80, alignment: .trailing)
            }

            summaryLine(entry)
                .padding(.leading, 28)

            if isOpen {
                detailPanel(entry)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
        .contextMenu {
            Button("Copy query") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.query, forType: .string)
            }
            Button(entry.isFavorite ? "Unfavorite" : "Add to favorites") {
                viewModel.toggleQueryFavorite(entry)
            }
            if entry.operationType == .find {
                Divider()
                Button("Run again") {
                    Task { await viewModel.replayQuery(entry) }
                }
            }
        }
    }

    private func opLabel(_ op: QueryLogEntry.OperationType) -> String {
        switch op {
        case .find:      return "query"
        case .insert:    return "insert"
        case .update:    return "update"
        case .delete:    return "delete"
        case .aggregate: return "aggregate"
        }
    }

    private func opBadgeKind(_ op: QueryLogEntry.OperationType) -> BadgeKind {
        switch op {
        case .find:      return .info
        case .insert:    return .success
        case .update:    return .warning
        case .delete:    return .danger
        case .aggregate: return .violet
        }
    }

    private func nsLabel(_ entry: QueryLogEntry) -> some View {
        HStack(spacing: 0) {
            Text(entry.database + ".")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
            Text(entry.collection)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func msPill(_ ms: Int) -> some View {
        let (bg, fg) = msColors(ms)
        let text = ms >= 1000
            ? String(format: "%.1f s", Double(ms) / 1000.0)
            : "\(ms) ms"
        return Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(bg)
            .clipShape(Capsule())
    }

    private func msColors(_ ms: Int) -> (Color, Color) {
        if ms >= 1000 { return (Theme.dangerTint, Theme.dangerDeep) }
        if ms >= 100  { return (Theme.warningTint, Theme.warningDeep) }
        return (Theme.successTint, Theme.successDeep)
    }

    @ViewBuilder
    private func statusPill(_ entry: QueryLogEntry) -> some View {
        switch resultBadge(entry) {
        case .errored:
            Text("errored").pillBadge(.danger)
        case .slow:
            Text("slow").pillBadge(.warning)
        case .returned(let n):
            Text("\(n.formatted()) returned").pillBadge(.success)
        case .multi:
            Text("multi").pillBadge(.neutral)
        case .single:
            Text("single").pillBadge(.neutral)
        case .removed(let n):
            Text("\(n.formatted()) removed").pillBadge(.danger)
        case .updated(let n):
            Text("\(n.formatted()) updated").pillBadge(.warning)
        }
    }

    private enum ResultBadge {
        case errored, slow, returned(Int), multi, single, removed(Int), updated(Int)
    }

    private func resultBadge(_ entry: QueryLogEntry) -> ResultBadge {
        if entry.errorMessage != nil {
            return .errored
        }
        if entry.executionTimeMs >= 1000 && entry.docsReturned == 0 && entry.operationType == .aggregate {
            return .errored
        }
        if entry.executionTimeMs >= 1000 {
            return .slow
        }
        switch entry.operationType {
        case .find, .aggregate:
            return .returned(entry.docsReturned)
        case .insert:
            return entry.docsReturned > 1 ? .multi : .single
        case .update:
            return .updated(entry.docsReturned)
        case .delete:
            return .removed(entry.docsReturned)
        }
    }

    private func summaryLine(_ entry: QueryLogEntry) -> some View {
        let preview = entry.query
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let truncated = preview.count > 140 ? String(preview.prefix(140)) + "…" : preview

        var metaParts: [String] = []
        if let examined = entry.docsExamined {
            metaParts.append("examined \(examined.formatted()) / returned \(entry.docsReturned.formatted())")
        }
        if let plan = entry.plan, !plan.isEmpty {
            metaParts.append("plan: \(plan)")
        }
        let metaLine = metaParts.joined(separator: " · ")

        return VStack(alignment: .leading, spacing: 2) {
            Text(truncated)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
                .truncationMode(.tail)
            if !metaLine.isEmpty {
                Text(metaLine)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Detail panel (codeBg)

    private func detailPanel(_ entry: QueryLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(DetailTab.allCases) { tab in
                    Button {
                        detailTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: detailTab == tab ? .semibold : .regular))
                            .foregroundStyle(detailTab == tab ? .white : .white.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(detailTab == tab ? Color.white.opacity(0.08) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.query, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy query")
                if entry.operationType == .find {
                    Button {
                        Task { await viewModel.replayQuery(entry) }
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Run again")
                }
            }
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
            }

            detailBody(entry)
        }
        .padding(12)
        .background(Theme.codeBg)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func detailBody(_ entry: QueryLogEntry) -> some View {
        switch detailTab {
        case .query:
            VStack(alignment: .leading, spacing: 6) {
                if let err = entry.errorMessage {
                    Text("Error: \(err)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.dangerDeep)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(formattedQuery(entry))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.codeFg)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .explain:
            if let plan = entry.plan, !plan.isEmpty {
                explainBlock(plan: plan, entry: entry)
            } else {
                placeholder("Explain plan is not captured for historical entries.")
            }
        case .trace:
            placeholder("Trace data is not available for this entry.")
        case .headers:
            if let client = entry.client, !client.isEmpty {
                Text("client: \(client)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.codeFg)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                placeholder("Client headers are not recorded.")
            }
        }
    }

    private func explainBlock(plan: String, entry: QueryLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("stage: \(plan)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.codeFg)
            if let examined = entry.docsExamined {
                Text("docsExamined: \(examined.formatted())  ·  docsReturned: \(entry.docsReturned.formatted())")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.codeMuted)
            }
            Text("executionTimeMs: \(entry.executionTimeMs.formatted())")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.codeMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(Theme.codeMuted)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedQuery(_ entry: QueryLogEntry) -> String {
        let header = "db.\(entry.collection).\(callFor(entry.operationType))("
        let body = entry.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty {
            return header + ")"
        }
        return header + "\n  " + body.replacingOccurrences(of: "\n", with: "\n  ") + "\n)"
    }

    private func callFor(_ op: QueryLogEntry.OperationType) -> String {
        switch op {
        case .find:      return "find"
        case .insert:    return "insertOne"
        case .update:    return "updateMany"
        case .delete:    return "deleteMany"
        case .aggregate: return "aggregate"
        }
    }

    // MARK: - Filtering

    private var filteredLog: [QueryLogEntry] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cutoff = quickRange.seconds.map { Date().addingTimeInterval(-$0) }
        let allColls = Set(collectionCounts.map(\.name))
        let collsActive = collectionsHydrated && !selectedCollections.isEmpty &&
            selectedCollections != allColls

        return viewModel.queryLog.filter { entry in
            if !selectedOperations.contains(entry.operationType) { return false }

            if collsActive {
                let key = "\(entry.database).\(entry.collection)"
                if !selectedCollections.contains(key) { return false }
            }

            if let cutoff, entry.timestamp < cutoff { return false }
            if quickRange == .custom {
                if entry.timestamp < customRangeStart { return false }
                if entry.timestamp > customRangeEnd { return false }
            }

            if !trimmedSearch.isEmpty {
                if !matchesAdvancedSearch(entry: entry, query: trimmedSearch) { return false }
            }

            // Result flags
            let isError = entry.executionTimeMs >= 1000 &&
                entry.docsReturned == 0 &&
                entry.operationType == .aggregate
            if isError && !showErrors { return false }
            if !isError && !showSuccess { return false }
            if showSlowOnly && entry.executionTimeMs <= 100 { return false }

            return true
        }
    }

    // MARK: - Advanced search parser

    /// Evaluate a search query against an entry. Supports:
    /// - `field:value`  →  matches when the entry's field contains value
    ///   (recognized fields: op, coll, db, plan, client)
    /// - `slow >= 1000ms` / `slow > Nms` / `slow < Nms` / `slow <= Nms`
    /// - `OR` between groups (default is AND within a group)
    /// - bare text → substring match against db.collection + query
    /// Falls back to a single substring match if parsing fails.
    private func matchesAdvancedSearch(entry: QueryLogEntry, query: String) -> Bool {
        let groups = splitByOR(query)
        guard !groups.isEmpty else { return true }
        return groups.contains { tokens in
            tokens.allSatisfy { matchToken(entry: entry, token: $0) }
        }
    }

    private func splitByOR(_ query: String) -> [[String]] {
        let parts = query.split(separator: " ").map(String.init)
        var groups: [[String]] = [[]]
        var i = 0
        while i < parts.count {
            let t = parts[i]
            if t.uppercased() == "OR" {
                groups.append([])
            } else if t.uppercased() == "AND" {
                // no-op — AND is the default within a group
            } else if t.lowercased() == "slow", i + 2 < parts.count,
                      ["<", ">", "<=", ">="].contains(parts[i + 1]) {
                let comparator = parts[i + 1]
                let amount = parts[i + 2]
                groups[groups.count - 1].append("slow\(comparator)\(amount)")
                i += 2
            } else {
                groups[groups.count - 1].append(t)
            }
            i += 1
        }
        return groups.filter { !$0.isEmpty }
    }

    private func matchToken(entry: QueryLogEntry, token: String) -> Bool {
        // Slow comparator pattern (e.g. "slow>=1000ms")
        if token.lowercased().hasPrefix("slow") {
            return evaluateSlowComparator(entry: entry, token: token)
        }
        if let colon = token.firstIndex(of: ":") {
            let key = String(token[..<colon]).lowercased()
            let value = String(token[token.index(after: colon)...]).lowercased()
            return evaluateField(entry: entry, key: key, value: value)
        }
        // Bare substring
        let hay = "\(entry.database).\(entry.collection) \(entry.query)".lowercased()
        return hay.contains(token.lowercased())
    }

    private func evaluateSlowComparator(entry: QueryLogEntry, token: String) -> Bool {
        let rest = token.dropFirst("slow".count)
        let comparators = ["<=", ">=", "<", ">"]
        var comparator = ""
        var amountStr = ""
        for c in comparators where rest.hasPrefix(c) {
            comparator = c
            amountStr = String(rest.dropFirst(c.count))
            break
        }
        guard !comparator.isEmpty else { return false }
        let trimmed = amountStr.lowercased().replacingOccurrences(of: "ms", with: "")
        guard let amount = Int(trimmed) else { return false }

        let ms = entry.executionTimeMs
        switch comparator {
        case "<":  return ms < amount
        case "<=": return ms <= amount
        case ">":  return ms > amount
        case ">=": return ms >= amount
        default:   return false
        }
    }

    private func evaluateField(entry: QueryLogEntry, key: String, value: String) -> Bool {
        switch key {
        case "op":
            return entry.operationType.rawValue.lowercased().contains(value)
        case "coll":
            return entry.collection.lowercased().contains(value)
        case "db":
            return entry.database.lowercased().contains(value)
        case "plan":
            return (entry.plan ?? "").lowercased().contains(value)
        case "client":
            return (entry.client ?? "").lowercased().contains(value)
        default:
            // Unknown field — treat as substring
            return "\(entry.database).\(entry.collection) \(entry.query)"
                .lowercased().contains("\(key):\(value)")
        }
    }

    // MARK: - Export

    private func exportLog() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(filteredLog) else { return }
        exportPayload = QueryLogExportDocument(data: data)
        showExporter = true
    }

    private static func exportTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}

// MARK: - Export document

struct QueryLogExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
