import SwiftUI
import Charts
import AppKit

@MainActor
struct MetricsView: View {
    @Environment(AppViewModel.self) private var viewModel

    enum Window: String, CaseIterable, Identifiable {
        case m5 = "5m"
        case m15 = "15m"
        case h1 = "1h"
        case h24 = "24h"
        var id: String { rawValue }
    }

    @State private var window: Window = .m5
    @State private var isPaused: Bool = false

    // Series colors (per design)
    private static let opsColor = Color(red: 0.949, green: 0.404, blue: 0.235) // #F2673C primary
    private static let connColor = Color(red: 0.435, green: 0.718, blue: 0.878) // #6FB7E0
    private static let memColor = Color(red: 0.427, green: 0.157, blue: 0.851) // #6D28D9
    private static let netInColor = Color(red: 0.082, green: 0.502, blue: 0.239) // #15803D
    private static let netOutColor = Color(red: 0.706, green: 0.325, blue: 0.035) // #B45309
    private static let cacheColor = Color(red: 0.725, green: 0.541, blue: 0.910) // #B98AE8
    private static let dangerColor = Color(red: 0.863, green: 0.149, blue: 0.149) // #DC2626

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 14) {
                    kpiRow
                    chartsGrid
                    serverInfoCard
                    databaseStatsCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
            .background(Theme.surface0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface0)
        .onAppear {
            if !isPaused { viewModel.startMetricsPolling() }
            Task { await viewModel.refreshMetrics() }
        }
        .onDisappear {
            viewModel.stopMetricsPolling()
        }
    }

    // MARK: - Top toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            breadcrumb
            healthPill

            Spacer()

            Text("Window")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textMuted)

            Segmented(
                items: Window.allCases,
                label: { Text($0.rawValue) },
                selection: $window
            )

            Button {
                exportSnapshot()
            } label: {
                Text("Export PNG")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                togglePause()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 10))
                    Text(isPaused ? "Resume stream" : "Pause stream")
                }
            }
            .buttonStyle(.accentCompact)
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
            Text("metrics")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var healthPill: some View {
        Group {
            if !viewModel.isConnected {
                Text("disconnected").pillBadge(.danger)
            } else if let m = viewModel.serverMetrics, m.connectionsActive > 0 {
                Text("all replicas healthy").pillBadge(.success)
            } else if isPaused {
                Text("paused").pillBadge(.warning)
            } else {
                Text("collecting…").pillBadge(.info)
            }
        }
    }

    private func togglePause() {
        isPaused.toggle()
        if isPaused { viewModel.stopMetricsPolling() }
        else        { viewModel.startMetricsPolling() }
    }

    // MARK: - KPI row

    private var kpiRow: some View {
        let snaps = viewModel.metricsHistory
        let opsSeries = snaps.map { $0.opsPerSec }
        let memSeries = snaps.map { $0.memoryMB }
        let netSeries = snaps.map { $0.networkInPerSec + $0.networkOutPerSec }
        let cacheSeries = snaps.compactMap { $0.cacheHitRatio }.map { $0 * 100 }
        let replSeries = snaps.compactMap { $0.replLagMs }
        let connActive = viewModel.serverMetrics?.connectionsActive ?? 0
        let connAvail = viewModel.serverMetrics?.connectionsAvailable ?? 0
        let connTotal = connActive + connAvail
        let currentLag = viewModel.serverMetrics?.replLagMs

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
            spacing: 10
        ) {
            kpiCard(
                label: "Ops · sec",
                value: opsSeries.last.map { String(format: "%.0f", $0) } ?? "—",
                unit: "/s",
                delta: deltaPercentLabel(opsSeries),
                deltaPositive: deltaSign(opsSeries) >= 0,
                series: opsSeries,
                color: Self.opsColor
            )
            kpiConnectionsCard(active: connActive, total: connTotal)
            kpiCard(
                label: "Resident mem",
                value: memSeries.last.map { formatMemory($0) } ?? "—",
                unit: "",
                delta: deltaPercentLabel(memSeries),
                deltaPositive: deltaSign(memSeries) <= 0, // less memory is "good"
                series: memSeries,
                color: Self.memColor
            )
            kpiCard(
                label: "Net I/O",
                value: netSeries.last.map { formatBytesPerSec($0) } ?? "—",
                unit: "",
                delta: deltaAbsLabel(netSeries.map { $0 / (1024 * 1024) }, unit: "MB/s"),
                deltaPositive: deltaSign(netSeries) >= 0,
                series: netSeries,
                color: Self.netInColor
            )
            kpiCard(
                label: "Cache hit",
                value: cacheSeries.last.map { String(format: "%.1f%%", $0) } ?? "—",
                unit: "",
                delta: deltaAbsLabel(cacheSeries, unit: "pp"),
                deltaPositive: deltaSign(cacheSeries) >= 0,
                series: cacheSeries,
                color: Self.cacheColor
            )
            kpiCard(
                label: "Repl lag",
                value: currentLag.map { formatReplLag($0) } ?? "—",
                unit: "",
                delta: deltaAbsLabel(replSeries, unit: "ms"),
                deltaPositive: deltaSign(replSeries) <= 0, // less lag is "good"
                series: replSeries,
                color: Self.dangerColor
            )
        }
    }

    private func formatReplLag(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms) ms" }
        let seconds = Double(ms) / 1000.0
        if seconds < 60 { return String(format: "%.1f s", seconds) }
        return String(format: "%.1f m", seconds / 60)
    }

    private func kpiCard(
        label: String,
        value: String,
        unit: String,
        delta: String?,
        deltaPositive: Bool,
        series: [Double],
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textMuted)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .lineLimit(1)

            HStack(spacing: 4) {
                if let delta {
                    Text(delta)
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(deltaPositive ? Theme.successDeep : Theme.warningDeep)
                }
                Text(deltaSuffix())
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }

            sparkline(series: series, color: color)
                .frame(height: 36)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
    }

    private func kpiConnectionsCard(active: Int, total: Int) -> some View {
        let utilisation: Double = total > 0 ? Double(active) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 6) {
            Text("Connections")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textMuted)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(active)")
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.textPrimary)
                Text(" / \(total)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }

            Text("\(Int(round(utilisation * 100)))% pool used")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.surface3)
                        .frame(height: 8)
                    Capsule()
                        .fill(Self.connColor)
                        .frame(width: max(2, geo.size.width * utilisation), height: 8)
                }
            }
            .frame(height: 8)
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
    }

    // MARK: - Charts grid

    private var chartsGrid: some View {
        let snaps = viewModel.metricsHistory

        return VStack(spacing: 12) {
            // Operations — full width
            chartCard(
                title: "Operations",
                sub: "5-second resolution · \(window.rawValue) window",
                legend: [("Ops · sec", Self.opsColor)]
            ) {
                multiAreaChart(
                    series: [(snaps.map { $0.opsPerSec }, Self.opsColor)],
                    height: 180
                )
                xAxisLabels(snaps: snaps)
            }

            HStack(spacing: 12) {
                chartCard(
                    title: "Memory",
                    sub: "resident vs. WT cache (MB)",
                    legend: [
                        ("Resident", Self.memColor),
                        ("WT cache", Self.cacheColor)
                    ]
                ) {
                    multiAreaChart(
                        series: [
                            (snaps.map { $0.memoryMB }, Self.memColor),
                            (snaps.compactMap { $0.wtCacheMB }, Self.cacheColor)
                        ],
                        height: 160
                    )
                    xAxisLabels(snaps: snaps, count: 3)
                }
                .frame(maxWidth: .infinity)

                chartCard(
                    title: "Network",
                    sub: "throughput (MB/s)",
                    legend: [
                        ("In",  Self.netInColor),
                        ("Out", Self.netOutColor),
                    ]
                ) {
                    multiAreaChart(
                        series: [
                            (snaps.map { $0.networkInPerSec / (1024 * 1024) }, Self.netInColor),
                            (snaps.map { $0.networkOutPerSec / (1024 * 1024) }, Self.netOutColor),
                        ],
                        height: 160
                    )
                    xAxisLabels(snaps: snaps, count: 3)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func chartCard<Content: View>(
        title: String,
        sub: String,
        legend: [(String, Color)],
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(sub)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                HStack(spacing: 12) {
                    ForEach(legend, id: \.0) { item in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(item.1)
                                .frame(width: 8, height: 8)
                            Text(item.0)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
    }

    private func multiAreaChart(series: [([Double], Color)], height: CGFloat) -> some View {
        let allValues = series.flatMap { $0.0 }
        let minY = allValues.min() ?? 0
        let maxY = (allValues.max() ?? 1)
        let yRange = (minY * 0.95)...(maxY * 1.05 + 0.001)

        return Chart {
            ForEach(Array(series.enumerated()), id: \.offset) { sIdx, pair in
                let (values, color) = pair
                if values.count >= 2 {
                    ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                        AreaMark(
                            x: .value("t", i),
                            y: .value("v", v),
                            series: .value("series", sIdx),
                            stacking: .unstacked
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [color.opacity(0.28), color.opacity(0)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    }
                    ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                        LineMark(
                            x: .value("t", i),
                            y: .value("v", v),
                            series: .value("series", sIdx)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel()
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .chartYScale(domain: yRange)
        .frame(height: height)
    }

    private func sparkline(series: [Double], color: Color) -> some View {
        Group {
            if series.count >= 2 {
                Chart {
                    ForEach(Array(series.enumerated()), id: \.offset) { i, v in
                        AreaMark(
                            x: .value("t", i),
                            y: .value("v", v)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [color.opacity(0.35), color.opacity(0)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    }
                    ForEach(Array(series.enumerated()), id: \.offset) { i, v in
                        LineMark(
                            x: .value("t", i),
                            y: .value("v", v)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.6))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartPlotStyle { $0.background(Color.clear) }
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.surface3)
            }
        }
    }

    private func xAxisLabels(snaps: [MetricsSnapshot], count: Int = 6) -> some View {
        let labels: [String] = {
            guard !snaps.isEmpty else { return [] }
            let step = max(1, snaps.count / max(1, count - 1))
            var out: [String] = []
            var i = 0
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm:ss"
            while i < snaps.count {
                out.append(fmt.string(from: snaps[i].timestamp))
                i += step
            }
            if out.count >= 1 { out[out.count - 1] = "now" }
            return out
        }()

        return HStack {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                if labels.last != label { Spacer() }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Server info

    private var serverInfoCard: some View {
        let m = viewModel.serverMetrics
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Server")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let m, !m.version.isEmpty {
                    Text("MongoDB v\(m.version)").pillBadge(.info)
                }
            }
            HStack(spacing: 28) {
                if let m {
                    infoItem(label: "Host", value: m.host.isEmpty ? "—" : m.host)
                    infoItem(label: "Uptime", value: formatUptime(m.uptime))
                    infoItem(label: "Connections created", value: "\(m.connectionsTotalCreated)")
                    let totalOps = m.opcounters.values.reduce(0, +)
                    infoItem(label: "Total ops", value: totalOps.formatted())
                } else {
                    Text("No server metrics available yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
    }

    private func infoItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).sectionHeaderStyle()
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - Database stats

    private var databaseStatsCard: some View {
        let stats = viewModel.serverMetrics?.dbStats ?? []
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Database stats")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if !stats.isEmpty {
                    Text("\(stats.count) database\(stats.count == 1 ? "" : "s")").pillBadge(.neutral)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            if stats.isEmpty {
                Text("No database stats available.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
            } else {
                HStack(spacing: 0) {
                    Text("Database").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Data size").frame(width: 120, alignment: .trailing)
                    Text("Storage").frame(width: 120, alignment: .trailing)
                    Text("Collections").frame(width: 100, alignment: .trailing)
                }
                .sectionHeaderStyle()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.surface2)

                ForEach(Array(stats.enumerated()), id: \.element.id) { i, db in
                    HStack(spacing: 0) {
                        Text(db.name)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(formatBytes(db.dataSize))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 120, alignment: .trailing)
                        Text(formatBytes(db.storageSize))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 120, alignment: .trailing)
                        Text("\(db.collections)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 100, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        if i != stats.count - 1 {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
    }

    // MARK: - Delta helpers

    private func deltaSign(_ series: [Double]) -> Double {
        guard let first = series.first, let last = series.last, !first.isZero else { return 0 }
        return last - first
    }

    private func deltaPercentLabel(_ series: [Double]) -> String? {
        guard series.count >= 2,
              let first = series.first, let last = series.last,
              !first.isZero else { return nil }
        let pct = (last - first) / first * 100
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", pct))%"
    }

    private func deltaAbsLabel(_ series: [Double], unit: String) -> String? {
        guard series.count >= 2,
              let first = series.first, let last = series.last else { return nil }
        let d = last - first
        let sign = d >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", d)) \(unit)"
    }

    private func deltaSuffix() -> String {
        let count = viewModel.metricsHistory.count
        if count == 0 { return "no samples" }
        let elapsedS = count * 5 // 5-second polling cadence
        if elapsedS >= 300 { return "vs 5m ago" }
        if elapsedS >= 60  { return "vs \(elapsedS / 60)m ago" }
        return "vs \(elapsedS)s ago"
    }

    // MARK: - Formatting

    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1024 { return String(format: "%.2f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }

    private func formatBytesPerSec(_ bytes: Double) -> String {
        let mb = bytes / (1024 * 1024)
        if mb >= 1 { return String(format: "%.2f MB/s", mb) }
        let kb = bytes / 1024
        if kb >= 1 { return String(format: "%.1f KB/s", kb) }
        return String(format: "%.0f B/s", bytes)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1.0 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1.0 { return String(format: "%.1f MB", mb) }
        let kb = Double(bytes) / 1024
        if kb >= 1.0 { return String(format: "%.1f KB", kb) }
        return "\(bytes) B"
    }

    private func formatUptime(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    // MARK: - Export

    private func exportSnapshot() {
        // Render the charts grid as a PNG at 2x for retina-quality export.
        let renderable = chartsGrid
            .frame(width: 1100)
            .padding(16)
            .background(Theme.surface0)
            .environment(viewModel)

        let renderer = ImageRenderer(content: renderable)
        renderer.scale = 2.0

        guard let cgImage = renderer.cgImage else { return }

        let nsImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: CGFloat(cgImage.width) / 2.0,
                         height: CGFloat(cgImage.height) / 2.0)
        )
        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "metrics-\(Self.exportFilenameFormatter.string(from: Date())).png"
        panel.message = "Save metrics snapshot"

        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
        }
    }

    private static let exportFilenameFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        return df
    }()
}
