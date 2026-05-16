import SwiftUI

@MainActor
struct SchemaView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var sampleSize: Int = 1_000
    @State private var selectedFieldId: SchemaField.ID?

    /// 0 = "All" (full collection scan).
    private let sampleSizeOptions: [Int] = [1_000, 10_000, 100_000, 0]

    private func sampleSizeLabel(_ size: Int) -> String {
        switch size {
        case 0: return "All"
        case 1_000: return "1K"
        case 10_000: return "10K"
        case 100_000: return "100K"
        default: return "\(size)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if viewModel.activeTab.selectedCollection == nil {
                noCollectionView
            } else if viewModel.isAnalyzingSchema {
                analyzingView
            } else if viewModel.schemaFields.isEmpty {
                emptyStateView
            } else {
                statRow
                schemaBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface0)
    }

    // MARK: - Top toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            breadcrumb

            if !viewModel.schemaFields.isEmpty {
                Text("sampled · uniform").pillBadge(.info)
            }

            if !viewModel.activeTab.filter.isEmpty {
                Text("filter applied").pillBadge(.accent)
            }

            Spacer()

            Text("Sample size")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textMuted)

            Segmented(
                items: sampleSizeOptions,
                label: { Text(sampleSizeLabel($0)) },
                selection: $sampleSize
            )

            Button {
                exportSchema()
            } label: {
                Text("Export schema")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.schemaFields.isEmpty)

            if viewModel.isAnalyzingSchema {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                    Text("Sampling…")
                }
                .pillBadge(.warning)
            }

            Button {
                Task { await viewModel.analyzeSchema(sampleSize: sampleSize) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 10))
                    Text(viewModel.schemaFields.isEmpty ? "Analyze" : "Re-sample")
                }
            }
            .buttonStyle(.accentCompact)
            .disabled(viewModel.isAnalyzingSchema || viewModel.activeTab.selectedCollection == nil)
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
            if let db = viewModel.activeTab.selectedDatabase {
                Text(db)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            if let coll = viewModel.activeTab.selectedCollection {
                Text(coll)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            Text("schema")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        }
    }

    // MARK: - Stat row (4 cards)

    private var statRow: some View {
        let flat = flattenFields(viewModel.schemaFields)
        let sampled = viewModel.schemaFields.first?.totalDocuments ?? 0
        let totalFields = flat.count
        let depth = maxDepth(viewModel.schemaFields)
        let sparse = flat.filter { $0.0.frequency < 0.95 }.count
        let sparsePct = totalFields == 0 ? 0 : Double(sparse) / Double(totalFields) * 100

        return HStack(spacing: 12) {
            statCard(
                label: "Sampled docs",
                value: sampled > 0 ? sampled.formatted() : "—",
                meta: sampleSize == 0
                    ? "full-collection scan"
                    : "from \(sampleSizeLabel(sampleSize)) sample"
            )
            statCard(
                label: "Fields detected",
                value: "\(totalFields)",
                meta: fieldsDetectedMeta()
            )
            statCard(
                label: "Max depth",
                value: "\(depth)",
                meta: depth > 1 ? "deepest: \(deepestPath() ?? "—")" : "flat structure"
            )
            statCard(
                label: "Sparse fields",
                value: totalFields > 0 ? String(format: "%.1f%%", sparsePct) : "—",
                meta: sparse == 0 ? "all fields ≥ 95% presence" : sparseFieldsPreview()
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func statCard(label: String, value: String, meta: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).sectionHeaderStyle()
            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .tracking(-0.4)
            Text(meta)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
    }

    // MARK: - Schema body (fields list + distribution panel)

    private var schemaBody: some View {
        HStack(alignment: .top, spacing: 14) {
            fieldsPanel
                .frame(maxWidth: .infinity)
            distributionPanel
                .frame(width: 380)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Fields panel

    private var fieldsPanel: some View {
        VStack(spacing: 0) {
            fieldsHeader
            legend
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    let flat = flattenFields(viewModel.schemaFields)
                    ForEach(Array(flat.enumerated()), id: \.offset) { i, pair in
                        fieldRow(field: pair.0, depth: pair.1, isLast: i == flat.count - 1)
                    }
                }
            }
        }
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
    }

    private var fieldsHeader: some View {
        HStack(spacing: 12) {
            Text("Field")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Type distribution")
                .frame(width: 220, alignment: .leading)
            Text("Present")
                .frame(width: 78, alignment: .trailing)
            Text("Sample value")
                .frame(width: 220, alignment: .leading)
        }
        .sectionHeaderStyle()
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface2)
    }

    private var legend: some View {
        let items: [(String, Color)] = [
            ("string",   typeColor("string")),
            ("int32",    typeColor("int")),
            ("double",   typeColor("double")),
            ("bool",     typeColor("bool")),
            ("date",     typeColor("date")),
            ("objectId", typeColor("objectid")),
            ("array",    typeColor("array")),
            ("object",   typeColor("object")),
            ("null",     typeColor("null")),
        ]
        return HStack(spacing: 14) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(item.1)
                        .frame(width: 10, height: 10)
                    Text(item.0)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.surface2)
    }

    private func fieldRow(field: SchemaField, depth: Int, isLast: Bool) -> some View {
        let isActive = selectedFieldId == field.id
        return HStack(spacing: 12) {
            // Field name (with depth indent + tree prefix)
            HStack(spacing: 6) {
                if depth > 0 {
                    Color.clear.frame(width: CGFloat(depth) * 18)
                    Text("└─")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                }
                if field.name == "_id" {
                    Image(systemName: "key.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.warning)
                        .help("Primary key")
                }
                Text(field.name)
                    .font(.system(size: 12.5, weight: isActive ? .bold : .regular, design: .monospaced))
                    .foregroundStyle(isActive ? Theme.primaryDeep : Theme.textPrimary)
                    .lineLimit(1)
                if field.hasMixedTypes {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.warning)
                        .help("Mixed types observed")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            typeDistributionBar(types: field.types)
                .frame(width: 220, height: 14)

            Text(String(format: "%.0f%%", field.frequency * 100))
                .pillBadge(presenceBadge(field.frequency))
                .frame(width: 78, alignment: .trailing)

            sampleValueView(field: field)
                .frame(width: 220, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            ZStack {
                if isActive {
                    Theme.surfaceActive
                }
            }
        )
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedFieldId = field.id
        }
    }

    private func typeDistributionBar(types: [SchemaTypeInfo]) -> some View {
        let total = max(1, types.reduce(0) { $0 + $1.count })
        return GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(types) { t in
                    let width = geo.size.width * CGFloat(t.count) / CGFloat(total)
                    Rectangle()
                        .fill(typeColor(t.typeName))
                        .frame(width: max(0, width))
                        .help("\(t.typeName): \(t.count) (\(Int(round(Double(t.count) / Double(total) * 100)))%)")
                }
            }
            .frame(height: 14)
            .background(Theme.surface3)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    @ViewBuilder
    private func sampleValueView(field: SchemaField) -> some View {
        if let top = field.stats?.topValues.first {
            let raw = top.value
            sampleTextColored(raw)
                .font(.system(size: 11.5, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
        } else if let nested = field.nestedFields, !nested.isEmpty {
            Text("{ \(nested.count) field\(nested.count == 1 ? "" : "s") }")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        } else {
            Text("—")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        }
    }

    @ViewBuilder
    private func sampleTextColored(_ raw: String) -> some View {
        let color: Color = {
            if raw.hasPrefix("\"") && raw.hasSuffix("\"") {
                return Theme.successDeep
            } else if Int(raw) != nil || Double(raw) != nil {
                return Theme.warningDeep
            } else if raw.lowercased() == "true" || raw.lowercased() == "false" {
                return Theme.violetDeep
            } else if raw.lowercased() == "null" {
                return Theme.textMuted
            } else {
                return Theme.textSecondary
            }
        }()
        Text(raw).foregroundStyle(color)
    }

    // MARK: - Distribution panel

    private var distributionPanel: some View {
        let selected = currentlySelectedField()

        return VStack(alignment: .leading, spacing: 0) {
            if let f = selected {
                distributionContent(for: f)
            } else {
                distributionEmpty
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
    }

    private var distributionEmpty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Distribution")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Select a field on the left to inspect its value frequencies and statistics.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func distributionContent(for field: SchemaField) -> some View {
        let path = pathForField(field.id, in: viewModel.schemaFields, prefix: viewModel.activeTab.selectedCollection ?? "")
        let primaryType = field.types.first?.typeName ?? "—"
        let card = field.stats?.distinctCount ?? field.stats?.topValues.count
        return VStack(alignment: .leading, spacing: 0) {
            // Title
            Text("Distribution")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(path ?? field.name)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Theme.primaryDeep)
                .padding(.top, 2)

            // Summary row
            HStack(spacing: 10) {
                summaryTile(
                    label: "Cardinality",
                    value: card.map { "\($0)" } ?? "—"
                )
                summaryTile(
                    label: "Primary type",
                    value: primaryType,
                    valueColor: typeColor(primaryType)
                )
            }
            .padding(.top, 14)

            // Value frequencies
            if let stats = field.stats, !stats.topValues.isEmpty {
                distSection(title: "Value frequencies") {
                    valueFrequencyHisto(stats.topValues)
                }
            }

            // Numeric range
            if let stats = field.stats, stats.numericMin != nil {
                distSection(title: "Numeric range") {
                    numericRangeRow(stats: stats)
                }
            }

            // String range
            if let stats = field.stats, stats.stringMinLength != nil {
                distSection(title: "String length") {
                    stringRangeRow(stats: stats)
                }
            }

            // Notes
            distSection(title: "Notes") {
                notesContent(for: field)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryTile(label: String, value: String, valueColor: Color = Theme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).sectionHeaderStyle()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface3)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func distSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).sectionHeaderStyle()
            content()
        }
        .padding(.top, 18)
    }

    private func valueFrequencyHisto(_ values: [TopValue]) -> some View {
        let maxCount = max(1, values.map { $0.count }.max() ?? 1)
        return VStack(spacing: 6) {
            ForEach(values) { v in
                HStack(spacing: 10) {
                    Text(v.value)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textSoft)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 90, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Theme.surface3)
                                .frame(height: 8)
                            Capsule()
                                .fill(Theme.brandGradient)
                                .frame(width: max(2, geo.size.width * CGFloat(v.count) / CGFloat(maxCount)), height: 8)
                        }
                    }
                    .frame(height: 8)

                    Text(v.count.formatted())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 56, alignment: .trailing)
                }
            }
        }
    }

    private func numericRangeRow(stats: SchemaFieldStats) -> some View {
        HStack(spacing: 18) {
            if let min = stats.numericMin { stat("min", formatNumeric(min)) }
            if let max = stats.numericMax { stat("max", formatNumeric(max)) }
            if let avg = stats.numericAvg { stat("avg", formatNumeric(avg)) }
            Spacer()
        }
    }

    private func stringRangeRow(stats: SchemaFieldStats) -> some View {
        HStack(spacing: 18) {
            if let minLen = stats.stringMinLength { stat("min len", "\(minLen)") }
            if let maxLen = stats.stringMaxLength { stat("max len", "\(maxLen)") }
            Spacer()
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).sectionHeaderStyle()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    @ViewBuilder
    private func notesContent(for field: SchemaField) -> some View {
        let pct = field.frequency * 100
        let missing = field.totalDocuments - field.presence
        if field.frequency < 0.95 {
            Text("\(Int(round(100 - pct)))% of documents are missing this field (\(missing.formatted()) of \(field.totalDocuments.formatted())). ")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            + Text("Suggest backfilling a default value")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.primaryDeep)
            + Text(".")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        } else if field.hasMixedTypes {
            let types = field.types.map { $0.typeName }.joined(separator: ", ")
            Text("This field has mixed types (\(types)). Consider tightening the validator to a single BSON type.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        } else {
            Text("Healthy: \(Int(round(pct)))% presence, single BSON type, no anomalies detected.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - State views

    private var noCollectionView: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.primaryTint)
                    .frame(width: 56, height: 56)
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.primaryDeep)
            }
            Text("Select a collection")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Choose a database and collection from the sidebar to analyze its schema.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var analyzingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text("Analyzing schema…")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.primaryTint)
                    .frame(width: 56, height: 56)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.primaryDeep)
            }
            Text("No schema analysis yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Pick a sample size and press Analyze to discover the shape of this collection.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func flattenFields(_ fields: [SchemaField], depth: Int = 0) -> [(SchemaField, Int)] {
        var out: [(SchemaField, Int)] = []
        for f in fields {
            out.append((f, depth))
            if let nested = f.nestedFields {
                out.append(contentsOf: flattenFields(nested, depth: depth + 1))
            }
        }
        return out
    }

    private func maxDepth(_ fields: [SchemaField], current: Int = 1) -> Int {
        var d = current
        for f in fields {
            if let nested = f.nestedFields, !nested.isEmpty {
                d = max(d, maxDepth(nested, current: current + 1))
            }
        }
        return d
    }

    /// Meta line for the "Fields detected" stat card. Shows the diff against
    /// the most recent prior sample when there is one, otherwise falls back
    /// to the root-field count.
    private func fieldsDetectedMeta() -> String {
        let added = viewModel.schemaAddedFields.count
        let removed = viewModel.schemaRemovedFields.count
        if added == 0 && removed == 0 {
            return "\(viewModel.schemaFields.count) at root"
        }
        var parts: [String] = []
        if added > 0 { parts.append("+\(added) new") }
        if removed > 0 { parts.append("-\(removed) gone") }
        return parts.joined(separator: " · ") + " since last sample"
    }

    /// Top-3 sparse field paths (frequency < 95%), least-present first. Used
    /// to populate the Sparse-fields stat card with concrete field names so
    /// the user knows which ones to inspect.
    private func sparseFieldsPreview() -> String {
        var paths: [(String, Double)] = []
        func walk(_ fields: [SchemaField], prefix: [String]) {
            for f in fields {
                let p = prefix + [f.name]
                if f.frequency < 0.95 {
                    paths.append((p.joined(separator: "."), f.frequency))
                }
                if let nested = f.nestedFields {
                    walk(nested, prefix: p)
                }
            }
        }
        walk(viewModel.schemaFields, prefix: [])
        paths.sort { $0.1 < $1.1 }
        let top = paths.prefix(3).map(\.0)
        if top.isEmpty { return "—" }
        return "watch " + top.joined(separator: ", ")
    }

    private func deepestPath() -> String? {
        var best: [String] = []
        func walk(_ fields: [SchemaField], path: [String]) {
            for f in fields {
                let p = path + [f.name]
                if let nested = f.nestedFields, !nested.isEmpty {
                    walk(nested, path: p)
                } else if p.count > best.count {
                    best = p
                }
            }
        }
        walk(viewModel.schemaFields, path: [])
        return best.isEmpty ? nil : best.joined(separator: ".")
    }

    private func pathForField(_ id: SchemaField.ID, in fields: [SchemaField], prefix: String) -> String? {
        for f in fields {
            let p = prefix.isEmpty ? f.name : "\(prefix).\(f.name)"
            if f.id == id { return p }
            if let nested = f.nestedFields, let found = pathForField(id, in: nested, prefix: p) {
                return found
            }
        }
        return nil
    }

    private func currentlySelectedField() -> SchemaField? {
        guard let id = selectedFieldId else { return nil }
        return findField(id, in: viewModel.schemaFields)
    }

    private func findField(_ id: SchemaField.ID, in fields: [SchemaField]) -> SchemaField? {
        for f in fields {
            if f.id == id { return f }
            if let nested = f.nestedFields, let found = findField(id, in: nested) {
                return found
            }
        }
        return nil
    }

    private func presenceBadge(_ freq: Double) -> BadgeKind {
        if freq >= 0.95 { return .success }
        if freq >= 0.70 { return .warning }
        return .danger
    }

    private func typeColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "string":
            return Color(red: 0.204, green: 0.659, blue: 0.325)   // #34A853
        case "int", "int32", "int64":
            return Color(red: 0.957, green: 0.722, blue: 0.376)   // #F4B860
        case "double", "decimal", "decimal128", "number":
            return Color(red: 0.898, green: 0.561, blue: 0.718)   // #E58FB7
        case "bool", "boolean":
            return Color(red: 0.435, green: 0.718, blue: 0.878)   // #6FB7E0
        case "date", "timestamp":
            return Color(red: 0.725, green: 0.541, blue: 0.910)   // #B98AE8
        case "objectid":
            return Color(red: 0.357, green: 0.392, blue: 0.447)   // #5B6472
        case "array":
            return Color(red: 0.863, green: 0.541, blue: 0.282)   // #DC8A48
        case "object", "document":
            return Color(red: 0.122, green: 0.302, blue: 0.549)   // #1F4D8C
        case "null":
            return Color(red: 0.784, green: 0.761, blue: 0.718)   // #C8C2B7
        default:
            return Theme.textMuted
        }
    }

    private func formatNumeric(_ n: Double) -> String {
        if n == n.rounded() && abs(n) < 1e15 { return Int64(n).formatted() }
        return String(format: "%.4g", n)
    }

    // MARK: - Export

    private func exportSchema() {
        let summary = renderSchemaSummary()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
    }

    private func renderSchemaSummary() -> String {
        var lines: [String] = []
        let db = viewModel.activeTab.selectedDatabase ?? "?"
        let coll = viewModel.activeTab.selectedCollection ?? "?"
        lines.append("# Schema · \(db).\(coll)")
        lines.append("")
        for (field, depth) in flattenFields(viewModel.schemaFields) {
            let indent = String(repeating: "  ", count: depth)
            let pct = Int(round(field.frequency * 100))
            let typeStr = field.types.map { "\($0.typeName)(\($0.count))" }.joined(separator: ", ")
            lines.append("\(indent)- \(field.name) [\(typeStr)] \(pct)%")
        }
        return lines.joined(separator: "\n")
    }
}
