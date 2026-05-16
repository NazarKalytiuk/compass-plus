import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
struct AggregationView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var showCodeGenSheet = false
    @State private var codeGenLanguage: CodeLanguage = .python
    @State private var showSavePipelineSheet = false
    @State private var savePipelineName = ""
    @State private var showLoadPipelineSheet = false
    @State private var deletePipelineId: UUID?
    @State private var showDeletePipelineAlert = false
    @State private var showAddStageMenu = false
    @State private var draggedStageId: UUID?
    @State private var explainSheetText: String?
    @State private var isExplaining: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if viewModel.activeTab.selectedCollection == nil {
                noCollectionView
            } else {
                HStack(alignment: .top, spacing: 14) {
                    pipelineColumn
                        .frame(width: 480)
                    previewColumn
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 16)
                .frame(maxHeight: .infinity)
                .background(Theme.surface0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface0)
        .sheet(isPresented: $showCodeGenSheet) { codeGenerationSheet }
        .sheet(isPresented: $showSavePipelineSheet) { savePipelineSheet }
        .sheet(isPresented: $showLoadPipelineSheet) { loadPipelineSheet }
        .alert("Delete Pipeline", isPresented: $showDeletePipelineAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let id = deletePipelineId { viewModel.deletePipeline(id: id) }
            }
        } message: {
            Text("Are you sure you want to delete this saved pipeline?")
        }
    }

    // MARK: - Top toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            breadcrumb

            Text("draft · unsaved").pillBadge(.accent)

            Spacer()

            Menu {
                Toggle("allowDiskUse", isOn: Bindable(viewModel).allowDiskUse)
                Divider()
                Section("Result limit") {
                    Picker("Limit", selection: Bindable(viewModel).aggregationResultLimit) {
                        Text("100").tag(100)
                        Text("500").tag(500)
                        Text("1 000").tag(1000)
                        Text("5 000").tag(5000)
                        Text("∞").tag(0)
                    }
                }
                Divider()
                Button {
                    showCodeGenSheet = true
                } label: {
                    Label("Generate code…", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11))
                    Text("Options")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(Theme.textSoft)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button {
                showLoadPipelineSheet = true
            } label: {
                Text("Load saved…")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                savePipelineName = ""
                showSavePipelineSheet = true
            } label: {
                Text("Save pipeline")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.pipelineStages.isEmpty)

            Button {
                runExplain()
            } label: {
                HStack(spacing: 5) {
                    if isExplaining {
                        ProgressView().controlSize(.mini).scaleEffect(0.6)
                    } else {
                        Image(systemName: "list.bullet.indent").font(.system(size: 10))
                    }
                    Text("Explain")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textSoft)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isExplaining || viewModel.pipelineStages.isEmpty || viewModel.activeTab.selectedCollection == nil)

            Button {
                Task { await viewModel.runAggregation() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill").font(.system(size: 10))
                    Text("Run")
                }
            }
            .buttonStyle(.accentCompact)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.isLoading || viewModel.activeTab.selectedCollection == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface1)
        .shadow(color: Theme.shadowAmbient.opacity(0.6), radius: 0.5, y: 0.5)
        .sheet(isPresented: Binding(get: { explainSheetText != nil }, set: { if !$0 { explainSheetText = nil } })) {
            explainSheet
        }
    }

    /// Renders the most recent explain output in a code-surface modal.
    @ViewBuilder
    private var explainSheet: some View {
        if let text = explainSheetText {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pipeline explain")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc").font(.system(size: 11))
                            Text("Copy")
                        }
                    }
                    .buttonStyle(.ghost)
                    Button("Close") { explainSheetText = nil }
                        .buttonStyle(.ghost)
                        .keyboardShortcut(.escape, modifiers: [])
                }
                ScrollView(.vertical, showsIndicators: true) {
                    Text(text)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.codeFg)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(Theme.codeBg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(16)
            .frame(width: 720, height: 520)
            .background(Theme.surface0)
        }
    }

    private func runExplain() {
        guard let database = viewModel.activeTab.selectedDatabase,
              let collection = viewModel.activeTab.selectedCollection else { return }
        isExplaining = true
        Task {
            defer { isExplaining = false }
            do {
                let pipeline = try Self.pipelineForExplain(viewModel.pipelineStages.filter { $0.enabled })
                let result = try await viewModel.mongoService.explainAggregation(
                    database: database, collection: collection, pipeline: pipeline
                )
                let data = try JSONSerialization.data(
                    withJSONObject: result,
                    options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
                )
                explainSheetText = String(data: data, encoding: .utf8) ?? "{}"
            } catch {
                explainSheetText = "Explain failed:\n\(error.localizedDescription)"
            }
        }
    }

    /// Lightweight copy of AppViewModel.buildPipeline kept local so the
    /// toolbar Explain button can pre-flight without exposing that private
    /// helper.
    private static func pipelineForExplain(_ stages: [PipelineStage]) throws -> [[String: Any]] {
        var pipeline: [[String: Any]] = []
        for stage in stages {
            let data = stage.body.data(using: .utf8) ?? Data()
            let body = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            pipeline.append([stage.type: body])
        }
        return pipeline
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
            Text("pipeline")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        }
    }

    // MARK: - Pipeline column (left)

    private var pipelineColumn: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 10) {
                ForEach(Array(viewModel.pipelineStages.enumerated()), id: \.element.id) { index, stage in
                    pipelineStageCard(index: index, stage: stage)
                }
                addStageButton
                    .padding(.top, 4)
            }
            .padding(.trailing, 4)
        }
    }

    private var addStageButton: some View {
        Menu {
            ForEach(PipelineStage.availableTypes, id: \.self) { type in
                Button {
                    viewModel.addPipelineStage()
                    if let idx = viewModel.pipelineStages.indices.last {
                        viewModel.pipelineStages[idx].type = type
                        viewModel.pipelineStages[idx].body = PipelineStage.template(for: type)
                    }
                } label: {
                    Text("\(type) — \(stageDescription(type))")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("Add stage")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.primaryDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    // MARK: - Stage card

    private func pipelineStageCard(index: Int, stage: PipelineStage) -> some View {
        let isValidJSON = validateJSON(stage.body)
        let stageCount = viewModel.pipelineStages.count
        let kind = stageBadgeKind(stage.type)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)

                Text(stage.type)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(kind.background)
                    .foregroundStyle(kind.foreground)
                    .clipShape(Capsule())

                Text(stageDescription(stage.type))
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Picker("", selection: Binding(
                    get: { stage.type },
                    set: { newType in updateStageType(index: index, from: stage.type, to: newType) }
                )) {
                    ForEach(PipelineStage.availableTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .labelsHidden()
                .frame(width: 26)
                .help("Change stage type")

                Button { viewModel.movePipelineStageUp(at: index) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(index > 0 ? Theme.textSecondary : Theme.textMuted.opacity(0.5))
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(index == 0).help("Move up")

                Button { viewModel.movePipelineStageDown(at: index) } label: {
                    Image(systemName: "arrow.down").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(index < stageCount - 1 ? Theme.textSecondary : Theme.textMuted.opacity(0.5))
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(index >= stageCount - 1).help("Move down")

                Toggle("", isOn: Binding(
                    get: { viewModel.pipelineStages[index].enabled },
                    set: { viewModel.pipelineStages[index].enabled = $0 }
                ))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                .help(stage.enabled ? "Disable stage" : "Enable stage")

                Button { viewModel.duplicatePipelineStage(at: index) } label: {
                    Image(systemName: "plus.square.on.square")
                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Duplicate")

                Button { viewModel.pipelineStages[index].collapsed.toggle() } label: {
                    Image(systemName: stage.collapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(stage.collapsed ? "Expand" : "Collapse")

                Button { viewModel.removePipelineStage(at: index) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.danger)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Remove")
            }

            if !stage.collapsed {
                MongoJSONEditor(
                    text: Binding(
                        get: { viewModel.pipelineStages[index].body },
                        set: { viewModel.pipelineStages[index].body = $0 }
                    ),
                    isValid: isValidJSON,
                    isDisabled: !stage.enabled
                )
                .frame(minHeight: 120, idealHeight: 150, maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                stageMetaRow(index: index, stage: stage, isValidJSON: isValidJSON)
                slowStageHint(for: stage)
            } else {
                Text(collapsedBodyPreview(stage.body))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.codeString)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .codeSurface(padding: 8, cornerRadius: 6)
            }
        }
        .padding(12)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
        .opacity(stage.enabled ? (draggedStageId == stage.id ? 0.4 : 1.0) : 0.55)
        .onDrag {
            draggedStageId = stage.id
            return NSItemProvider(object: stage.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], delegate: PipelineStageDropDelegate(
            targetId: stage.id,
            stages: viewModel.pipelineStages,
            draggedId: $draggedStageId,
            move: { from, to in viewModel.movePipelineStage(from: IndexSet(integer: from), to: to) }
        ))
    }

    private func stageMetaRow(index: Int, stage: PipelineStage, isValidJSON: Bool) -> some View {
        let previewing = viewModel.stagePreviewInProgress.contains(stage.id)
        let preview = viewModel.stagePreviews[stage.id]
        let previewError = viewModel.stagePreviewErrors[stage.id]
        let hasTimingData = stage.ms != nil

        // Dot color reflects explain-derived timing first, preview second.
        let dotColor: Color = {
            if let ms = stage.ms {
                return ms > 100 ? Theme.warning : Theme.success
            }
            if previewError != nil { return Theme.danger }
            if preview != nil { return Theme.success }
            return Theme.textMuted
        }()

        return HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)

            if hasTimingData {
                Text("Out:")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Text("\(stage.outCount ?? 0) doc\((stage.outCount ?? 0) == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textSoft)
                if let ms = stage.ms {
                    Text("·")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                    Text("\(formatStageMs(ms)) ms")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ms > 100 ? Theme.warningDeep : Theme.textSoft)
                }
                if let usedIndex = stage.usedIndex, !usedIndex.isEmpty {
                    Text("·")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                    Text("index: \(usedIndex)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.successDeep)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else if let preview = preview {
                Text("Out:")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Text("\(preview.count) doc\(preview.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textSoft)
            } else if previewError != nil {
                Text("Preview failed")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dangerDeep)
            } else if !isValidJSON {
                Text("Invalid JSON")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dangerDeep)
            } else {
                Text("Ready")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }

            Spacer()

            Button {
                Task { await viewModel.previewStage(at: index) }
            } label: {
                HStack(spacing: 4) {
                    if previewing {
                        ProgressView().controlSize(.mini).scaleEffect(0.7)
                    } else {
                        Image(systemName: "eye").font(.system(size: 10))
                    }
                    Text(preview == nil ? "Preview" : "Refresh")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Theme.primaryDeep)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isValidJSON || !stage.enabled || previewing)
        }
        .padding(.top, 2)
    }

    private func formatStageMs(_ ms: Double) -> String {
        if ms < 10 { return String(format: "%.1f", ms) }
        return String(format: "%.0f", ms)
    }

    /// Show a warning-card hint when a stage took > 100 ms. For $match stages
    /// we surface the first non-operator field as a candidate index hint;
    /// for other stage types the hint is generic.
    @ViewBuilder
    private func slowStageHint(for stage: PipelineStage) -> some View {
        if let ms = stage.ms, ms > 100, (stage.usedIndex == nil || stage.usedIndex?.isEmpty == true) {
            let field = stage.type == "$match" ? firstMatchField(in: stage.body) : nil
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warningDeep)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Slow stage · \(formatStageMs(ms)) ms")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.warningDeep)
                    if let field {
                        Text("Consider index hint on `{ \(field): 1 }`")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textSoft)
                    } else {
                        Text("No index used — review the stage for a candidate field.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSoft)
                    }
                }
                Spacer()
            }
            .padding(8)
            .background(Theme.warningTint)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// Extract the first non-operator field name from a `$match` body. Returns
    /// nil for empty matches or pure operator bodies like `{ "$and": [...] }`.
    private func firstMatchField(in body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
              let dict = parsed as? [String: Any] else { return nil }
        for key in dict.keys where !key.hasPrefix("$") {
            return key
        }
        return nil
    }

    private func collapsedBodyPreview(_ body: String) -> String {
        let collapsed = body
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? "(empty)" : collapsed
    }

    private func updateStageType(index: Int, from oldType: String, to newType: String) {
        viewModel.pipelineStages[index].type = newType
        let currentBody = viewModel.pipelineStages[index].body
        let oldTemplate = PipelineStage.template(for: oldType)
        if currentBody == oldTemplate || currentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            viewModel.pipelineStages[index].body = PipelineStage.template(for: newType)
        }
    }

    // MARK: - Stage type pill mapping

    private func stageBadgeKind(_ type: String) -> BadgeKind {
        switch type {
        case "$match":   return .success
        case "$group":   return .accent
        case "$project": return .info
        case "$lookup":  return .violet
        case "$sort":    return .neutral
        case "$limit", "$skip": return .danger
        case "$unwind":  return .violet
        case "$addFields", "$set", "$replaceRoot", "$replaceWith": return .info
        case "$count":   return .accent
        case "$facet":   return .violet
        default:         return .neutral
        }
    }

    private func stageDescription(_ type: String) -> String {
        switch type {
        case "$match":      return "filter documents"
        case "$group":      return "group and accumulate"
        case "$project":    return "shape output"
        case "$lookup":     return "join collection"
        case "$sort":       return "reorder stream"
        case "$limit":      return "limit output"
        case "$skip":       return "skip documents"
        case "$unwind":     return "expand array"
        case "$addFields":  return "compute fields"
        case "$set":        return "set fields"
        case "$count":      return "count documents"
        case "$facet":      return "parallel pipelines"
        case "$replaceRoot":return "promote subdoc"
        case "$replaceWith":return "promote subdoc"
        default:            return "stage"
        }
    }

    // MARK: - Preview column (right)

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            previewHead

            if viewModel.isLoading {
                runningView
            } else if let error = viewModel.aggregationError {
                aggregationErrorView(error)
            } else if viewModel.aggregationResults.isEmpty {
                emptyPreviewView
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(viewModel.aggregationResults.enumerated()), id: \.offset) { i, doc in
                            previewCard(doc: doc, index: i, total: viewModel.aggregationResults.count)
                        }
                    }
                    .padding(.trailing, 4)
                }
            }
        }
    }

    private var previewHead: some View {
        HStack(spacing: 10) {
            Text("Live preview")
                .sectionHeaderStyle()
            if !viewModel.aggregationResults.isEmpty {
                Text("\(viewModel.aggregationResults.count) document\(viewModel.aggregationResults.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if viewModel.aggregationTruncated {
                Text("capped").pillBadge(.warning)
            }
            Button {
                Task { await viewModel.runAggregation() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .toolbarIconButton()
            }
            .buttonStyle(.plain)
            .help("Re-run pipeline")
            .disabled(viewModel.isLoading)
        }
        .padding(.bottom, 10)
    }

    private func previewCard(doc: [String: Any], index: Int, total: Int) -> some View {
        let pills = detectPreviewPills(in: doc)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(pills) { pill in
                    Text(pill.label).pillBadge(pill.kind)
                }
                Text("document \(index + 1) / \(total)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(orderedDocKeys(Array(doc.keys)), id: \.self) { key in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\"\(key)\"")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color(red: 0.122, green: 0.302, blue: 0.549))
                            .frame(width: 180, alignment: .leading)
                        previewValueView(doc[key])
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
        .contextMenu {
            Button("Copy JSON") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prettyPrintJSON(doc), forType: .string)
            }
        }
    }

    @ViewBuilder
    private func previewValueView(_ value: Any?) -> some View {
        if let s = value as? String {
            Text("\"\(s)\"")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.successDeep)
                .lineLimit(2)
                .truncationMode(.tail)
        } else if let b = value as? Bool {
            Text(b ? "true" : "false")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.violetDeep)
        } else if let n = value as? NSNumber {
            Text(formatNumber(n))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.warningDeep)
        } else if value is NSNull {
            Text("null")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        } else if let arr = value as? [Any] {
            Text("[ \(arr.count) item\(arr.count == 1 ? "" : "s") ]")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        } else if let dict = value as? [String: Any] {
            Text("{ \(dict.keys.count) field\(dict.keys.count == 1 ? "" : "s") }")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        } else if let v = value {
            Text(String(describing: v))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSoft)
                .lineLimit(2)
        } else {
            Text("—")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        }
    }

    private struct DetectedPill: Identifiable {
        let id = UUID()
        let label: String
        let kind: BadgeKind
    }

    private func detectPreviewPills(in doc: [String: Any]) -> [DetectedPill] {
        var pills: [DetectedPill] = []
        if let tier = doc["tier"] as? String {
            pills.append(DetectedPill(label: "tier · \(tier)", kind: .accent))
        } else if let id = doc["_id"] as? String, id.count < 24 {
            pills.append(DetectedPill(label: id, kind: .accent))
        }
        if let status = doc["status"] as? String {
            let kind: BadgeKind
            switch status.lowercased() {
            case "active", "success", "ok": kind = .success
            case "pending":                  kind = .warning
            case "failed", "error":          kind = .danger
            default:                         kind = .neutral
            }
            pills.append(DetectedPill(label: status, kind: kind))
        }
        return pills
    }

    private func orderedDocKeys(_ keys: [String]) -> [String] {
        let priority = ["_id", "tier", "status", "name", "label", "key", "count", "total", "sum", "avg", "revenue", "orders"]
        var ordered: [String] = []
        var seen = Set<String>()
        for p in priority {
            if let m = keys.first(where: { $0.lowercased() == p.lowercased() }), !seen.contains(m) {
                ordered.append(m); seen.insert(m)
            }
        }
        for k in keys where !seen.contains(k) { ordered.append(k); seen.insert(k) }
        return ordered
    }

    private func formatNumber(_ n: NSNumber) -> String {
        let s = n.stringValue
        if let intVal = Int(s), abs(intVal) >= 1000 { return intVal.formatted() }
        if let d = Double(exactly: n), abs(d) >= 1000 {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 2
            return f.string(from: n) ?? s
        }
        return s
    }

    // MARK: - State views

    private var runningView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text("Running aggregation…")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func aggregationErrorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.dangerTint)
                    .frame(width: 56, height: 56)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.dangerDeep)
            }
            Text("Aggregation error")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(error)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.dangerDeep)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyPreviewView: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.primaryTint)
                    .frame(width: 56, height: 56)
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.primaryDeep)
            }
            Text("No results yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Build your pipeline and press ⌘↩ to run.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noCollectionView: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.primaryTint)
                    .frame(width: 56, height: 56)
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.primaryDeep)
            }
            Text("Select a collection")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Choose a database and collection from the sidebar to build aggregation pipelines.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sheets

    private var codeGenerationSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Generate aggregation code")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Done") { showCodeGenSheet = false }
                    .buttonStyle(.accent)
            }

            Picker("Language", selection: $codeGenLanguage) {
                ForEach(CodeLanguage.allCases, id: \.self) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.segmented)

            let code = viewModel.generateAggregationCode(language: codeGenLanguage)

            ScrollView {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.codeFg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .codeSurface(padding: 12, cornerRadius: 8)
                    .textSelection(.enabled)
            }

            CopyButton(text: code, label: "Copy to Clipboard")
        }
        .padding(20)
        .frame(width: 620, height: 470)
        .background(Theme.surface0)
    }

    private var savePipelineSheet: some View {
        let existsWithSameName = viewModel.savedPipelines.contains {
            $0.name == savePipelineName
                && $0.database == (viewModel.activeTab.selectedDatabase ?? "")
                && $0.collection == (viewModel.activeTab.selectedCollection ?? "")
        }
        return VStack(spacing: 16) {
            Text("Save pipeline")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Pipeline name").sectionHeaderStyle()
                TextField("My pipeline", text: $savePipelineName)
                    .textFieldStyle(.themedSans)
                if existsWithSameName && !savePipelineName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle").font(.system(size: 10))
                        Text("A pipeline with this name exists — it will be overwritten.")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(Theme.warningDeep)
                }
            }

            HStack {
                Button("Cancel") { showSavePipelineSheet = false }
                    .buttonStyle(.ghost)
                Spacer()
                Button(existsWithSameName ? "Overwrite" : "Save") {
                    if !savePipelineName.isEmpty {
                        viewModel.savePipeline(name: savePipelineName)
                        showSavePipelineSheet = false
                    }
                }
                .buttonStyle(.accent)
                .disabled(savePipelineName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Theme.surface0)
    }

    private var loadPipelineSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Load pipeline")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Done") { showLoadPipelineSheet = false }
                    .buttonStyle(.accent)
            }

            if viewModel.savedPipelines.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.textMuted)
                    Text("No saved pipelines")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.savedPipelines) { pipeline in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pipeline.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("\(pipeline.database).\(pipeline.collection) · \(pipeline.stages.count) stage\(pipeline.stages.count == 1 ? "" : "s")")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Theme.textSecondary)
                                }

                                Spacer()

                                Button {
                                    viewModel.loadPipeline(pipeline)
                                    showLoadPipelineSheet = false
                                } label: {
                                    Text("Load")
                                }
                                .buttonStyle(.accentCompact)

                                Button {
                                    deletePipelineId = pipeline.id
                                    showDeletePipelineAlert = true
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(Theme.danger)
                                }
                                .buttonStyle(.plain)
                            }
                            .cardStyle(padding: 10, cornerRadius: 8)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 500, height: 400)
        .background(Theme.surface0)
    }

    // MARK: - Helpers

    private func validateJSON(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil
    }
}

// MARK: - Copy button (used in code-gen sheet)

@MainActor
private struct CopyButton: View {
    let text: String
    let label: String
    @State private var justCopied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(.easeOut(duration: 0.15)) { justCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut(duration: 0.2)) { justCopied = false }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                Text(justCopied ? "Copied" : label)
            }
        }
        .buttonStyle(.ghost)
    }
}

// MARK: - Drag-and-drop reordering for pipeline stages

private struct PipelineStageDropDelegate: DropDelegate {
    let targetId: UUID
    let stages: [PipelineStage]
    @Binding var draggedId: UUID?
    let move: (Int, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedId,
              draggedId != targetId,
              let from = stages.firstIndex(where: { $0.id == draggedId }),
              let to = stages.firstIndex(where: { $0.id == targetId })
        else { return }
        // SwiftUI's onMove uses an "insertion index": dropping after the
        // target needs `to + 1`, dropping before needs `to`. Match the
        // visual drag direction to that semantic.
        let insertion = from < to ? to + 1 : to
        move(from, insertion)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedId = nil
        return true
    }

    func dropExited(info: DropInfo) {
        // Keep draggedId set until performDrop so visual fade stays through
        // hover transitions between cards.
    }
}
