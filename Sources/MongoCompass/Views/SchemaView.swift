import SwiftUI

@MainActor
struct SchemaView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var sampleSize: Int = 100

    /// 0 is a sentinel for "all documents" (no `$sample` stage).
    private let sampleSizeOptions = [25, 50, 100, 250, 500, 0]

    private func sampleSizeLabel(_ size: Int) -> String {
        size == 0 ? "All" : "\(size)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Schema Analysis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                if let db = viewModel.activeTab.selectedDatabase,
                   let col = viewModel.activeTab.selectedCollection {
                    Text("\(db).\(col)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(14)
            .background(Theme.surface.opacity(0.4))

            ThemedDivider()

            if viewModel.activeTab.selectedCollection == nil {
                noCollectionView
            } else {
                // Controls bar
                controlsBar

                ThemedDivider()

                // Results
                if viewModel.isAnalyzingSchema {
                    loadingView
                } else if viewModel.schemaFields.isEmpty {
                    emptyStateView
                } else {
                    schemaResultsView
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.midnight)
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sample Size")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Picker("", selection: $sampleSize) {
                    ForEach(sampleSizeOptions, id: \.self) { size in
                        Text(sampleSizeLabel(size)).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }

            Spacer()

            if sampleSize == 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text("full scan")
                        .font(.system(size: 10, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
                .foregroundStyle(Theme.amber)
                .help("Analyzes every document in the collection. May be slow for large collections.")
            }

            if !viewModel.activeTab.filter.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 10))
                    Text("filter applied")
                        .font(.system(size: 10, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
                .foregroundStyle(Theme.skyBlue)
                .help("Sampling from documents matching the active tab's filter:\n\(viewModel.activeTab.filter)")
            }

            Button {
                Task {
                    await viewModel.analyzeSchema(sampleSize: sampleSize)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                    Text("Analyze")
                }
            }
            .buttonStyle(.accent)
            .disabled(viewModel.isAnalyzingSchema)
        }
        .padding(14)
        .background(Theme.surface.opacity(0.3))
    }

    // MARK: - Schema Results View (Tree)

    private var schemaResultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    Text("Field")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Frequency")
                        .frame(width: 180, alignment: .leading)
                    Text("Types")
                        .frame(width: 300, alignment: .leading)
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(Theme.surface)

                ThemedDivider()

                LazyVStack(spacing: 0) {
                    ForEach(viewModel.schemaFields) { field in
                        SchemaFieldRow(field: field, depth: 0)
                    }
                }
            }
            .padding(.bottom, 14)
        }
    }

    // MARK: - State Views

    private var noCollectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
            Text("Select a collection")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text("Choose a database and collection from the sidebar to analyze its schema.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Analyzing schema...")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
            Text("No schema analysis yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text("Select a sample size and click Analyze to discover the schema of this collection.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Schema Field Row (Recursive)

@MainActor
struct SchemaFieldRow: View {
    let field: SchemaField
    let depth: Int

    @State private var isExpanded = false

    private var hasChildren: Bool {
        guard let nested = field.nestedFields else { return false }
        return !nested.isEmpty
    }

    private var hasStats: Bool {
        field.stats?.hasAnyStat ?? false
    }

    private var isExpandable: Bool {
        hasChildren || hasStats
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Field name with indentation, disclosure triangle, mixed-type warning
                HStack(spacing: 4) {
                    // Indentation
                    ForEach(0..<depth, id: \.self) { _ in
                        Color.clear.frame(width: 20)
                    }

                    // Disclosure triangle
                    if isExpandable {
                        Button {
                            isExpanded.toggle()
                        } label: {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 16)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 16)
                    }

                    Text(field.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)

                    if field.hasMixedTypes {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.amber)
                            .help("Mixed types observed — data quality issue")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Frequency bar
                HStack(spacing: 8) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.border)
                                .frame(height: 10)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.green)
                                .frame(width: max(geometry.size.width * field.frequency, 2), height: 10)
                        }
                    }
                    .frame(width: 100, height: 10)

                    Text(String(format: "%.0f%%", field.frequency * 100))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
                .frame(width: 180, alignment: .leading)

                // Type badges (capped with +N more when overflowing)
                typeBadges
                    .frame(width: 300, alignment: .leading)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .background(depth % 2 == 0 ? Color.clear : Theme.surface.opacity(0.15))
            .contentShape(Rectangle())
            .onTapGesture {
                if isExpandable { isExpanded.toggle() }
            }

            // Stats panel (shown when expanded)
            if isExpanded, let stats = field.stats, stats.hasAnyStat {
                SchemaStatsPanel(stats: stats, depth: depth)
            }

            // Nested fields (recursive)
            if isExpanded, let nestedFields = field.nestedFields {
                ForEach(nestedFields) { child in
                    SchemaFieldRow(field: child, depth: depth + 1)
                }
            }
        }
    }

    // MARK: - Type Badges

    private static let maxVisibleTypes = 3

    @ViewBuilder
    private var typeBadges: some View {
        let visible = field.types.prefix(Self.maxVisibleTypes)
        let hidden = max(0, field.types.count - Self.maxVisibleTypes)

        HStack(spacing: 4) {
            ForEach(visible) { typeInfo in
                Text(typeLabel(for: typeInfo))
                    .lineLimit(1)
                    .pillBadge(color: SchemaFieldRow.typeColor(for: typeInfo.typeName))
                    .help(typeTooltip(for: typeInfo))
            }
            if hidden > 0 {
                Text("+\(hidden)")
                    .pillBadge(color: Theme.textSecondary)
                    .help(field.types.dropFirst(Self.maxVisibleTypes)
                        .map { "\($0.typeName) (\($0.count))" }
                        .joined(separator: ", "))
            }
        }
    }

    /// Label for a type pill. For `array`, embed the element types inline,
    /// e.g. `array<string> (5)` or `array<string,int64> (5)`.
    private func typeLabel(for typeInfo: SchemaTypeInfo) -> String {
        if typeInfo.typeName == "array", let elements = typeInfo.elementTypes, !elements.isEmpty {
            let names = elements.prefix(2).map { $0.typeName }.joined(separator: ",")
            let more = elements.count > 2 ? "…" : ""
            return "array<\(names)\(more)> (\(typeInfo.count))"
        }
        return "\(typeInfo.typeName) (\(typeInfo.count))"
    }

    private func typeTooltip(for typeInfo: SchemaTypeInfo) -> String {
        if typeInfo.typeName == "array", let elements = typeInfo.elementTypes, !elements.isEmpty {
            let breakdown = elements.map { "\($0.typeName): \($0.count)" }.joined(separator: ", ")
            return "array elements — \(breakdown)"
        }
        return "\(typeInfo.typeName): \(typeInfo.count) occurrence\(typeInfo.count == 1 ? "" : "s")"
    }

    static func typeColor(for typeName: String) -> Color {
        switch typeName.lowercased() {
        case "string": return Theme.skyBlue
        case "int", "int32", "int64", "double", "decimal", "decimal128", "number": return Theme.amber
        case "bool", "boolean": return Theme.crimson
        case "object", "document": return Theme.green
        case "array": return Color.purple
        case "objectid": return Color.orange
        case "date", "timestamp": return Color.pink
        case "null": return Theme.textSecondary
        default: return Theme.textSecondary
        }
    }
}

// MARK: - Stats Panel

@MainActor
struct SchemaStatsPanel: View {
    let stats: SchemaFieldStats
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let min = stats.numericMin, let max = stats.numericMax {
                HStack(spacing: 16) {
                    statItem("min", formatNumber(min))
                    statItem("max", formatNumber(max))
                    if let avg = stats.numericAvg {
                        statItem("avg", formatNumber(avg))
                    }
                }
            }

            if let minLen = stats.stringMinLength, let maxLen = stats.stringMaxLength {
                HStack(spacing: 16) {
                    statItem("min length", "\(minLen)")
                    statItem("max length", "\(maxLen)")
                }
            }

            if let distinct = stats.distinctCount {
                statItem("distinct", "\(distinct)")
            }

            if !stats.topValues.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("top values")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    ForEach(stats.topValues) { top in
                        HStack(spacing: 8) {
                            Text(top.value)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("\(top.count)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.midnight.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.leading, CGFloat(depth) * 20 + 30)
        .padding(.trailing, 14)
        .padding(.bottom, 6)
    }

    private func statItem(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white)
        }
    }

    private func formatNumber(_ n: Double) -> String {
        if n == n.rounded() && abs(n) < 1e15 {
            return String(Int64(n))
        }
        return String(format: "%.4g", n)
    }
}
