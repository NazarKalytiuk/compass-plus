import SwiftUI

struct MetricsView: View {
    @Environment(AppViewModel.self) private var viewModel

    enum Tab: String, CaseIterable {
        case system = "System Metrics"
        case operations = "Operations Monitor"
    }

    @State private var selectedTab: Tab = .system
    @State private var namespaceFilter = ""
    @State private var opTypeFilter = ""
    @State private var minExecTime = ""
    @State private var showKillConfirmation = false
    @State private var killOpId: Int?

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
                .frame(maxWidth: 350)

                Spacer()

                // Auto-refresh indicator
                HStack(spacing: 6) {
                    StatusDot(color: viewModel.isConnected ? Theme.green : Theme.crimson, size: 6)
                    Text("Auto-refresh: 5s")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }

                Button {
                    Task {
                        await viewModel.refreshMetrics()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                }
                .buttonStyle(.accentCompact)
            }
            .padding(14)
            .background(Theme.surface.opacity(0.4))

            ThemedDivider()

            switch selectedTab {
            case .system:
                systemMetricsTab
            case .operations:
                operationsMonitorTab
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.midnight)
        .onAppear {
            viewModel.startMetricsPolling()
            Task { await viewModel.refreshMetrics() }
        }
        .onDisappear {
            viewModel.stopMetricsPolling()
        }
        .alert("Kill Operation", isPresented: $showKillConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Kill", role: .destructive) {
                if let opId = killOpId {
                    Task { await viewModel.killOp(opId: opId) }
                }
            }
        } message: {
            Text("Are you sure you want to kill this operation? This cannot be undone.")
        }
    }

    // MARK: - System Metrics Tab

    private var systemMetricsTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Server info header
                serverInfoHeader

                // Metrics grid
                metricsGrid

                // Sparkline charts
                sparklineSection

                // Per-database stats
                databaseStatsTable
            }
            .padding(14)
        }
    }

    private var serverInfoHeader: some View {
        HStack(spacing: 24) {
            if let metrics = viewModel.serverMetrics {
                infoItem(label: "Version", value: metrics.version)
                infoItem(label: "Host", value: metrics.host)
                infoItem(label: "Uptime", value: formatUptime(metrics.uptime))
            } else {
                Text("No server metrics available")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .cardStyle(padding: 14, cornerRadius: 10)
    }

    private func infoItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var metricsGrid: some View {
        let metrics = viewModel.serverMetrics

        return LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            // Connections card
            VStack(alignment: .leading, spacing: 10) {
                Text("CONNECTIONS")
                    .sectionHeaderStyle()

                if let m = metrics {
                    HStack(spacing: 16) {
                        metricNumber(label: "Current", value: "\(m.connectionsActive)")
                        metricNumber(label: "Available", value: "\(m.connectionsAvailable)")
                        metricNumber(label: "Created", value: "\(m.connectionsTotalCreated)")
                    }

                    // Visual bar
                    let total = max(m.connectionsActive + m.connectionsAvailable, 1)
                    let fraction = Double(m.connectionsActive) / Double(total)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.border)
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.green)
                                .frame(width: geometry.size.width * fraction, height: 8)
                        }
                    }
                    .frame(height: 8)
                } else {
                    Text("--")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .cardStyle()

            // Memory card
            VStack(alignment: .leading, spacing: 10) {
                Text("MEMORY")
                    .sectionHeaderStyle()

                if let m = metrics {
                    HStack(spacing: 16) {
                        metricNumber(label: "Resident", value: "\(m.memoryResident) MB")
                        metricNumber(label: "Virtual", value: "\(m.memoryVirtual) MB")
                    }
                } else {
                    Text("--")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .cardStyle()

            // Network card
            VStack(alignment: .leading, spacing: 10) {
                Text("NETWORK")
                    .sectionHeaderStyle()

                if let m = metrics {
                    HStack(spacing: 16) {
                        metricNumber(label: "Bytes In", value: formatBytes(m.networkBytesIn))
                        metricNumber(label: "Bytes Out", value: formatBytes(m.networkBytesOut))
                    }
                } else {
                    Text("--")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .cardStyle()

            // Opcounters card (spans full width below)
            VStack(alignment: .leading, spacing: 10) {
                Text("OPCOUNTERS")
                    .sectionHeaderStyle()

                if let m = metrics {
                    HStack(spacing: 16) {
                        ForEach(["insert", "query", "update", "delete", "command"], id: \.self) { key in
                            metricNumber(label: key.capitalized, value: "\(m.opcounters[key] ?? 0)")
                        }
                    }
                } else {
                    Text("--")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .cardStyle()
        }
    }

    private func metricNumber(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Sparkline Section

    private var sparklineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PERFORMANCE HISTORY")
                .sectionHeaderStyle()

            HStack(spacing: 16) {
                // Operations/sec sparkline
                VStack(alignment: .leading, spacing: 6) {
                    Text("Operations/sec")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    SparklineChart(
                        data: viewModel.metricsHistory.map { $0.opsPerSec },
                        lineColor: Theme.green
                    )
                    .frame(height: 80)
                }
                .cardStyle(padding: 10, cornerRadius: 8)

                // Memory usage sparkline
                VStack(alignment: .leading, spacing: 6) {
                    Text("Memory (MB)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    SparklineChart(
                        data: viewModel.metricsHistory.map { $0.memoryMB },
                        lineColor: Theme.skyBlue
                    )
                    .frame(height: 80)
                }
                .cardStyle(padding: 10, cornerRadius: 8)
            }
        }
        .cardStyle()
    }

    // MARK: - Database Stats Table

    private var databaseStatsTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DATABASE STATS")
                .sectionHeaderStyle()

            if let metrics = viewModel.serverMetrics, !metrics.dbStats.isEmpty {
                VStack(spacing: 0) {
                    // Header
                    HStack(spacing: 0) {
                        Text("Database")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Data Size")
                            .frame(width: 120, alignment: .trailing)
                        Text("Storage Size")
                            .frame(width: 120, alignment: .trailing)
                        Text("Collections")
                            .frame(width: 100, alignment: .trailing)
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)

                    ThemedDivider()

                    ForEach(metrics.dbStats) { db in
                        HStack(spacing: 0) {
                            Text(db.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(.white)
                            Text(formatBytes(db.dataSize))
                                .frame(width: 120, alignment: .trailing)
                                .foregroundStyle(Theme.textSecondary)
                            Text(formatBytes(db.storageSize))
                                .frame(width: 120, alignment: .trailing)
                                .foregroundStyle(Theme.textSecondary)
                            Text("\(db.collections)")
                                .frame(width: 100, alignment: .trailing)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                    }
                }
            } else {
                Text("No database stats available")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .cardStyle()
    }

    // MARK: - Operations Monitor Tab

    private var operationsMonitorTab: some View {
        VStack(spacing: 0) {
            // Filters row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Namespace")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("e.g. mydb.users", text: $namespaceFilter)
                        .textFieldStyle(.themed)
                        .frame(maxWidth: 200)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Operation Type")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("e.g. query", text: $opTypeFilter)
                        .textFieldStyle(.themed)
                        .frame(maxWidth: 120)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Min Exec Time (ms)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("0", text: $minExecTime)
                        .textFieldStyle(.themed)
                        .frame(maxWidth: 100)
                }

                Spacer()
            }
            .padding(14)
            .background(Theme.surface.opacity(0.3))

            ThemedDivider()

            // Operations table
            if filteredOps.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bolt.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.textSecondary)
                    Text("No active operations")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Active operations will appear here when the server is busy.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Table header
                        HStack(spacing: 0) {
                            Text("OpID")
                                .frame(width: 80, alignment: .leading)
                            Text("Type")
                                .frame(width: 80, alignment: .leading)
                            Text("Op")
                                .frame(width: 80, alignment: .leading)
                            Text("Namespace")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Client")
                                .frame(width: 150, alignment: .leading)
                            Text("Time (ms)")
                                .frame(width: 90, alignment: .trailing)
                            Text("Action")
                                .frame(width: 60, alignment: .center)
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Theme.surface)

                        ThemedDivider()

                        ForEach(filteredOps) { op in
                            HStack(spacing: 0) {
                                Text("\(op.id)")
                                    .frame(width: 80, alignment: .leading)
                                    .foregroundStyle(.white)
                                Text(op.type)
                                    .frame(width: 80, alignment: .leading)
                                    .foregroundStyle(Theme.textSecondary)
                                Text(op.op)
                                    .frame(width: 80, alignment: .leading)
                                    .foregroundStyle(Theme.skyBlue)
                                Text(op.namespace)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(op.client)
                                    .frame(width: 150, alignment: .leading)
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                                Text("\(op.executionTimeMs)")
                                    .frame(width: 90, alignment: .trailing)
                                    .foregroundStyle(executionTimeColor(op.executionTimeMs))
                                    .fontWeight(.semibold)

                                Button {
                                    killOpId = op.id
                                    showKillConfirmation = true
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Theme.crimson)
                                }
                                .buttonStyle(.plain)
                                .frame(width: 60)
                                .help("Kill operation")
                            }
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
    }

    private var filteredOps: [CurrentOp] {
        viewModel.currentOps.filter { op in
            if !namespaceFilter.isEmpty {
                guard op.namespace.lowercased().contains(namespaceFilter.lowercased()) else { return false }
            }
            if !opTypeFilter.isEmpty {
                guard op.op.lowercased().contains(opTypeFilter.lowercased()) else { return false }
            }
            if let minMs = Int(minExecTime), minMs > 0 {
                guard op.executionTimeMs >= minMs else { return false }
            }
            return true
        }
    }

    // MARK: - Helpers

    private func formatUptime(_ seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        }
        let kb = Double(bytes) / 1024
        if kb >= 1.0 {
            return String(format: "%.1f KB", kb)
        }
        return "\(bytes) B"
    }

    private func formatBytes(_ bytes: Int) -> String {
        formatBytes(Int64(bytes))
    }

    private func executionTimeColor(_ ms: Int) -> Color {
        if ms < 50 { return Theme.green }
        if ms < 200 { return Theme.amber }
        return Theme.crimson
    }
}

// MARK: - Sparkline Chart (Canvas-based)

struct SparklineChart: View {
    let data: [Double]
    var lineColor: Color = Theme.green

    var body: some View {
        GeometryReader { geometry in
            if data.count < 2 {
                // Not enough data
                HStack {
                    Spacer()
                    Text("Collecting data...")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .frame(height: geometry.size.height)
            } else {
                Canvas { context, size in
                    let width = size.width
                    let height = size.height
                    let minVal = data.min() ?? 0
                    let maxVal = data.max() ?? 1
                    let range = max(maxVal - minVal, 0.001)
                    let stepX = width / CGFloat(data.count - 1)

                    // Build the polyline path
                    var linePath = Path()
                    for (index, value) in data.enumerated() {
                        let x = CGFloat(index) * stepX
                        let normalizedY = (value - minVal) / range
                        let y = height - (normalizedY * height * 0.85) - (height * 0.05)

                        if index == 0 {
                            linePath.move(to: CGPoint(x: x, y: y))
                        } else {
                            linePath.addLine(to: CGPoint(x: x, y: y))
                        }
                    }

                    // Build the fill path (gradient below the line)
                    var fillPath = linePath
                    fillPath.addLine(to: CGPoint(x: CGFloat(data.count - 1) * stepX, y: height))
                    fillPath.addLine(to: CGPoint(x: 0, y: height))
                    fillPath.closeSubpath()

                    // Draw gradient fill
                    let gradient = Gradient(colors: [
                        lineColor.opacity(0.3),
                        lineColor.opacity(0.0)
                    ])
                    context.fill(
                        fillPath,
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: width / 2, y: 0),
                            endPoint: CGPoint(x: width / 2, y: height)
                        )
                    )

                    // Draw the line
                    context.stroke(
                        linePath,
                        with: .color(lineColor),
                        lineWidth: 2
                    )

                    // Draw the latest value dot
                    if let lastValue = data.last {
                        let lastX = CGFloat(data.count - 1) * stepX
                        let normalizedY = (lastValue - minVal) / range
                        let lastY = height - (normalizedY * height * 0.85) - (height * 0.05)
                        let dotRect = CGRect(
                            x: lastX - 3,
                            y: lastY - 3,
                            width: 6,
                            height: 6
                        )
                        context.fill(
                            Path(ellipseIn: dotRect),
                            with: .color(lineColor)
                        )
                    }
                }

                // Show current value overlay
                if let lastValue = data.last {
                    VStack {
                        HStack {
                            Spacer()
                            Text(String(format: "%.1f", lastValue))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(lineColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.surface.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Spacer()
                    }
                }
            }
        }
    }
}
