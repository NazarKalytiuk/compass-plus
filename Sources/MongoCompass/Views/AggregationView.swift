import SwiftUI
import AppKit

struct AggregationView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var showCodeGenSheet = false
    @State private var codeGenLanguage: CodeLanguage = .python
    @State private var showSavePipelineSheet = false
    @State private var savePipelineName = ""
    @State private var showLoadPipelineSheet = false
    @State private var deletePipelineId: UUID?
    @State private var showDeletePipelineAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Aggregation Pipeline")
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
                HSplitView {
                    pipelineBuilderPanel
                        .frame(minWidth: 360, idealWidth: 480)
                    resultsPanel
                        .frame(minWidth: 300, idealWidth: 500)
                }
            }

            ThemedDivider()

            // Bottom toolbar
            bottomToolbar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.midnight)
        .sheet(isPresented: $showCodeGenSheet) {
            codeGenerationSheet
        }
        .sheet(isPresented: $showSavePipelineSheet) {
            savePipelineSheet
        }
        .sheet(isPresented: $showLoadPipelineSheet) {
            loadPipelineSheet
        }
        .alert("Delete Pipeline", isPresented: $showDeletePipelineAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let id = deletePipelineId {
                    viewModel.deletePipeline(id: id)
                }
            }
        } message: {
            Text("Are you sure you want to delete this saved pipeline?")
        }
    }

    // MARK: - Pipeline Builder Panel

    private var pipelineBuilderPanel: some View {
        @Bindable var viewModel = viewModel
        return VStack(spacing: 0) {
            // Add stage header
            HStack {
                Text("PIPELINE STAGES")
                    .sectionHeaderStyle()

                Spacer()

                Button {
                    viewModel.addPipelineStage()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Stage")
                    }
                }
                .buttonStyle(.accentCompact)
            }
            .padding(14)

            ThemedDivider()

            // Stages list
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(viewModel.pipelineStages.enumerated()), id: \.element.id) { index, stage in
                        pipelineStageCard(index: index, stage: stage)
                    }
                }
                .padding(14)
            }

            ThemedDivider()

            // Run button + controls
            runControls
        }
        .background(Theme.midnight)
    }

    private var runControls: some View {
        @Bindable var viewModel = viewModel
        return HStack(spacing: 12) {
            Button {
                Task {
                    await viewModel.runAggregation()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("Run Pipeline")
                    Text("⌘↵")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.midnight.opacity(0.6))
                }
            }
            .buttonStyle(.accent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.isLoading)

            Spacer()

            Toggle(isOn: $viewModel.allowDiskUse) {
                Text("allowDiskUse")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("Lift the 100MB memory limit for $sort and $group")
        }
        .padding(14)
    }

    // MARK: - Stage Card

    private func pipelineStageCard(index: Int, stage: PipelineStage) -> some View {
        @Bindable var viewModel = viewModel
        let isValidJSON = validateJSON(stage.body)
        let stageCount = viewModel.pipelineStages.count

        return VStack(alignment: .leading, spacing: 10) {
            // Top row: collapse, number, type, reorder, validation, enable, duplicate, delete
            HStack(spacing: 6) {
                // Collapse toggle
                Button {
                    viewModel.pipelineStages[index].collapsed.toggle()
                } label: {
                    Image(systemName: stage.collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                .help(stage.collapsed ? "Expand stage" : "Collapse stage")

                // Stage number
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 18)

                // Stage type picker
                Picker("", selection: Binding(
                    get: { stage.type },
                    set: { newType in
                        updateStageType(index: index, from: stage.type, to: newType)
                    }
                )) {
                    ForEach(PipelineStage.availableTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 170)

                Spacer(minLength: 6)

                // Reorder up
                Button {
                    viewModel.movePipelineStageUp(at: index)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(index > 0 ? Theme.textSecondary : Theme.textSecondary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
                .help("Move stage up")

                // Reorder down
                Button {
                    viewModel.movePipelineStageDown(at: index)
                } label: {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(index < stageCount - 1 ? Theme.textSecondary : Theme.textSecondary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(index >= stageCount - 1)
                .help("Move stage down")

                // Validation indicator
                Image(systemName: isValidJSON ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isValidJSON ? Theme.green : Theme.crimson)
                    .font(.system(size: 13))
                    .help(isValidJSON ? "Valid JSON" : "Invalid JSON")

                // Enable/disable toggle
                Toggle("", isOn: $viewModel.pipelineStages[index].enabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help(stage.enabled ? "Disable stage" : "Enable stage")

                // Duplicate
                Button {
                    viewModel.duplicatePipelineStage(at: index)
                } label: {
                    Image(systemName: "plus.square.on.square")
                        .foregroundStyle(Theme.textSecondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Duplicate stage")

                // Delete
                Button {
                    viewModel.removePipelineStage(at: index)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.crimson)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Remove stage")
            }

            if stage.collapsed {
                // Collapsed: one-line body preview
                Text(collapsedBodyPreview(stage.body))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Theme.midnight)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            } else {
                // Expanded: full editor
                MongoJSONEditor(
                    text: $viewModel.pipelineStages[index].body,
                    isValid: isValidJSON,
                    isDisabled: !stage.enabled
                )
                .frame(minHeight: 110, idealHeight: 140)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isValidJSON ? Theme.border : Theme.crimson.opacity(0.5), lineWidth: 1)
                )

                // Preview controls + preview output
                stagePreviewSection(index: index, stage: stage, isValidJSON: isValidJSON)
            }
        }
        .cardStyle(padding: 12, cornerRadius: 8)
        .opacity(stage.enabled ? 1.0 : 0.6)
    }

    @ViewBuilder
    private func stagePreviewSection(index: Int, stage: PipelineStage, isValidJSON: Bool) -> some View {
        let previewing = viewModel.stagePreviewInProgress.contains(stage.id)
        let preview = viewModel.stagePreviews[stage.id]
        let previewError = viewModel.stagePreviewErrors[stage.id]

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    Task {
                        await viewModel.previewStage(at: index)
                    }
                } label: {
                    HStack(spacing: 4) {
                        if previewing {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "eye")
                                .font(.system(size: 10))
                        }
                        Text(preview == nil ? "Preview output" : "Refresh preview")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.ghost)
                .disabled(!isValidJSON || !stage.enabled || previewing)

                if preview != nil || previewError != nil {
                    Button {
                        viewModel.clearStagePreview(stageId: stage.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear preview")
                }

                Spacer()
            }

            if let preview = preview {
                stagePreviewList(preview)
            } else if let err = previewError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.crimson)
                    Text(err)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.crimson)
                        .lineLimit(3)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.crimson.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func stagePreviewList(_ preview: [[String: Any]]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("sample output")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text("(\(preview.count) doc\(preview.count == 1 ? "" : "s"))")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            if preview.isEmpty {
                Text("(no documents)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.midnight)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(preview.enumerated()), id: \.offset) { _, doc in
                        Text(prettyPrintJSON(doc))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(6)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(Theme.midnight)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
    }

    /// Apply a new stage type, preserving the user's custom body unless the body
    /// still matches the previous type's template exactly.
    private func updateStageType(index: Int, from oldType: String, to newType: String) {
        @Bindable var viewModel = viewModel
        viewModel.pipelineStages[index].type = newType
        let currentBody = viewModel.pipelineStages[index].body
        let oldTemplate = PipelineStage.template(for: oldType)
        if currentBody == oldTemplate || currentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            viewModel.pipelineStages[index].body = PipelineStage.template(for: newType)
        }
    }

    private func collapsedBodyPreview(_ body: String) -> String {
        let collapsed = body
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? "(empty)" : collapsed
    }

    // MARK: - Results Panel

    private var resultsPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("RESULTS")
                    .sectionHeaderStyle()

                if !viewModel.aggregationResults.isEmpty {
                    Text("(\(viewModel.aggregationResults.count) doc\(viewModel.aggregationResults.count == 1 ? "" : "s"))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }

                if viewModel.aggregationTruncated {
                    Text("capped")
                        .pillBadge(color: Theme.amber)
                        .help("Result set reached the \(viewModel.aggregationResultLimit)-document limit. Raise the limit to see more.")
                }

                Spacer()
            }
            .padding(14)

            ThemedDivider()

            // Content
            if viewModel.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Running aggregation...")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.aggregationError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.crimson)
                    Text("Aggregation Error")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.crimson)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.aggregationResults.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.textSecondary)
                    Text("No results yet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Build your pipeline and press ⌘↵ to run.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(viewModel.aggregationResults.enumerated()), id: \.offset) { index, doc in
                            ResultDocumentCard(index: index, doc: doc)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(Theme.midnight)
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 12) {
            Button {
                showCodeGenSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                    Text("Generate Code")
                }
            }
            .buttonStyle(.ghost)

            Spacer()

            Text("Limit")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Picker("", selection: Binding(
                get: { viewModel.aggregationResultLimit },
                set: { viewModel.aggregationResultLimit = $0 }
            )) {
                Text("100").tag(100)
                Text("500").tag(500)
                Text("1000").tag(1000)
                Text("5000").tag(5000)
                Text("∞").tag(0)
            }
            .labelsHidden()
            .frame(width: 80)
            .help("Maximum number of result documents to materialize")

            Button {
                showLoadPipelineSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                    Text("Load")
                }
            }
            .buttonStyle(.ghost)

            Button {
                savePipelineName = ""
                showSavePipelineSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save")
                }
            }
            .buttonStyle(.ghost)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surface.opacity(0.3))
    }

    // MARK: - No Collection View

    private var noCollectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
            Text("Select a collection")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text("Choose a database and collection from the sidebar to build aggregation pipelines.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Code Generation Sheet

    private var codeGenerationSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Generate Aggregation Code")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Done") {
                    showCodeGenSheet = false
                }
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
                    .foregroundStyle(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.midnight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }

            CopyButton(text: code, label: "Copy to Clipboard")
        }
        .padding(20)
        .frame(width: 600, height: 450)
        .background(Theme.surface)
    }

    // MARK: - Save Pipeline Sheet

    private var savePipelineSheet: some View {
        let existsWithSameName = viewModel.savedPipelines.contains {
            $0.name == savePipelineName
                && $0.database == (viewModel.activeTab.selectedDatabase ?? "")
                && $0.collection == (viewModel.activeTab.selectedCollection ?? "")
        }
        return VStack(spacing: 16) {
            Text("Save Pipeline")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 4) {
                Text("Pipeline Name")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                TextField("My Pipeline", text: $savePipelineName)
                    .textFieldStyle(.themed)
                if existsWithSameName && !savePipelineName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                        Text("A pipeline with this name exists — it will be overwritten.")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(Theme.amber)
                }
            }

            HStack {
                Button("Cancel") {
                    showSavePipelineSheet = false
                }
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
        .background(Theme.surface)
    }

    // MARK: - Load Pipeline Sheet

    private var loadPipelineSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Load Pipeline")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Done") {
                    showLoadPipelineSheet = false
                }
                .buttonStyle(.accent)
            }

            if viewModel.savedPipelines.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.textSecondary)
                    Text("No saved pipelines")
                        .font(.system(size: 14))
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
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text("\(pipeline.database).\(pipeline.collection) - \(pipeline.stages.count) stages")
                                        .font(.system(size: 12))
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
                                        .foregroundStyle(Theme.crimson)
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
        .background(Theme.surface)
    }

    // MARK: - Helpers

    private func validateJSON(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil
    }
}

// MARK: - Result Document Card (with copy feedback)

private struct ResultDocumentCard: View {
    let index: Int
    let doc: [String: Any]
    @State private var justCopied = false

    var body: some View {
        let jsonString = prettyPrintJSON(doc)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Document \(index + 1)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.green)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(jsonString, forType: .string)
                    withAnimation(.easeOut(duration: 0.15)) { justCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.easeOut(duration: 0.2)) { justCopied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        if justCopied {
                            Text("Copied")
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .foregroundStyle(justCopied ? Theme.green : Theme.textSecondary)
                }
                .toolbarIconButton(isActive: justCopied)
                .buttonStyle(.plain)
                .help("Copy JSON")
            }

            ThemedDivider()

            Text(jsonString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle(padding: 10, cornerRadius: 8)
    }
}

// MARK: - Copy Button (with feedback)

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
