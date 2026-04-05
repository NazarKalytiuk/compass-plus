import SwiftUI

@MainActor
struct DumpRestoreView: View {
    @Environment(AppViewModel.self) private var viewModel

    enum Tab: String, CaseIterable {
        case dump = "Dump (Export)"
        case restore = "Restore (Import)"
    }

    enum OperationStatus: Equatable {
        case idle
        case running
        case complete
        case error
    }

    @State private var selectedTab: Tab = .dump

    // Dump state
    @State private var dumpDatabase = ""
    @State private var dumpCollection = ""
    @State private var dumpOutputPath = ""
    @State private var dumpGzip = false
    @State private var dumpOutput: [String] = []
    @State private var dumpStatus: OperationStatus = .idle

    // Restore state
    @State private var restoreInputPath = ""
    @State private var restoreTargetDatabase = ""
    @State private var restoreDrop = false
    @State private var restoreOutput: [String] = []
    @State private var restoreStatus: OperationStatus = .idle

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 350)

                Spacer()
            }
            .padding(14)
            .background(Theme.surface.opacity(0.4))

            ThemedDivider()

            switch selectedTab {
            case .dump:
                dumpTab
            case .restore:
                restoreTab
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.midnight)
        .onAppear {
            if dumpDatabase.isEmpty, let db = viewModel.activeTab.selectedDatabase {
                dumpDatabase = db
            }
        }
    }

    // MARK: - Dump Tab

    private var dumpTab: some View {
        VStack(spacing: 0) {
            // Tool availability
            toolAvailabilityBanner(
                isAvailable: viewModel.dumpRestoreService.isDumpAvailable,
                toolName: "mongodump"
            )

            ScrollView {
                VStack(spacing: 16) {
                    // Configuration card
                    VStack(alignment: .leading, spacing: 14) {
                        Text("DUMP CONFIGURATION")
                            .sectionHeaderStyle()

                        // Database picker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Database")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                            Picker("", selection: $dumpDatabase) {
                                Text("Select database...").tag("")
                                ForEach(viewModel.databases, id: \.self) { db in
                                    Text(db).tag(db)
                                }
                            }
                            .frame(maxWidth: 300)
                        }

                        // Collection picker (optional)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Collection (optional - leave empty to dump entire database)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                            Picker("", selection: $dumpCollection) {
                                Text("All collections").tag("")
                                if !dumpDatabase.isEmpty, let collections = viewModel.collections[dumpDatabase] {
                                    ForEach(collections, id: \.self) { col in
                                        Text(col).tag(col)
                                    }
                                }
                            }
                            .frame(maxWidth: 300)
                        }

                        // Output directory
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Output Directory")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                            HStack {
                                TextField("/path/to/output", text: $dumpOutputPath)
                                    .textFieldStyle(.themed)
                                Button {
                                    selectFolder { path in
                                        dumpOutputPath = path
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "folder")
                                        Text("Browse")
                                    }
                                }
                                .buttonStyle(.ghost)
                            }
                        }

                        // Options
                        HStack(spacing: 20) {
                            Toggle("Gzip compression", isOn: $dumpGzip)
                                .toggleStyle(.checkbox)
                        }

                        // Dump button
                        HStack {
                            Spacer()
                            Button {
                                runDump()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Start Dump")
                                }
                            }
                            .buttonStyle(.accent)
                            .disabled(dumpDatabase.isEmpty || dumpOutputPath.isEmpty || dumpStatus == .running || !viewModel.dumpRestoreService.isDumpAvailable)
                        }
                    }
                    .cardStyle()

                    // Output console
                    outputConsole(
                        title: "Dump Output",
                        lines: dumpOutput,
                        status: dumpStatus
                    )
                }
                .padding(14)
            }
        }
    }

    // MARK: - Restore Tab

    private var restoreTab: some View {
        VStack(spacing: 0) {
            // Tool availability
            toolAvailabilityBanner(
                isAvailable: viewModel.dumpRestoreService.isRestoreAvailable,
                toolName: "mongorestore"
            )

            ScrollView {
                VStack(spacing: 16) {
                    // Configuration card
                    VStack(alignment: .leading, spacing: 14) {
                        Text("RESTORE CONFIGURATION")
                            .sectionHeaderStyle()

                        // Input path
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Input Directory / File")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                            HStack {
                                TextField("/path/to/dump", text: $restoreInputPath)
                                    .textFieldStyle(.themed)
                                Button {
                                    selectFolder { path in
                                        restoreInputPath = path
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "folder")
                                        Text("Browse")
                                    }
                                }
                                .buttonStyle(.ghost)
                            }
                        }

                        // Target database (optional override)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Target Database (optional override)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                            TextField("Leave empty to use original database names", text: $restoreTargetDatabase)
                                .textFieldStyle(.themed)
                                .frame(maxWidth: 400)
                        }

                        // Drop existing toggle
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Drop existing collections before restoring", isOn: $restoreDrop)
                                .toggleStyle(.checkbox)

                            if restoreDrop {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Theme.amber)
                                    Text("Warning: Existing data in matching collections will be deleted before restore.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.amber)
                                }
                                .padding(8)
                                .background(Theme.amber.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }

                        // Restore button
                        HStack {
                            Spacer()
                            Button {
                                runRestore()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Start Restore")
                                }
                            }
                            .buttonStyle(.accent)
                            .disabled(restoreInputPath.isEmpty || restoreStatus == .running || !viewModel.dumpRestoreService.isRestoreAvailable)
                        }
                    }
                    .cardStyle()

                    // Output console
                    outputConsole(
                        title: "Restore Output",
                        lines: restoreOutput,
                        status: restoreStatus
                    )
                }
                .padding(14)
            }
        }
    }

    // MARK: - Shared Components

    private func toolAvailabilityBanner(isAvailable: Bool, toolName: String) -> some View {
        Group {
            if !isAvailable {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.amber)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(toolName) not found")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.amber)
                        Text("Install MongoDB Database Tools: brew install mongodb-database-tools")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer()
                }
                .padding(12)
                .background(Theme.amber.opacity(0.1))

                ThemedDivider()
            }
        }
    }

    private func outputConsole(title: String, lines: [String], status: OperationStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased())
                    .sectionHeaderStyle()

                Spacer()

                statusIndicator(status)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if lines.isEmpty {
                            Text("Output will appear here...")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                        } else {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(lineColor(line))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                    }
                    .padding(10)
                }
                .onChange(of: lines.count) { _, newCount in
                    if newCount > 0 {
                        withAnimation {
                            proxy.scrollTo(newCount - 1, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(minHeight: 200, maxHeight: 300)
            .background(Color(red: 0.02, green: 0.05, blue: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
        .cardStyle()
    }

    private func statusIndicator(_ status: OperationStatus) -> some View {
        HStack(spacing: 6) {
            switch status {
            case .idle:
                StatusDot(color: Theme.textSecondary, size: 6)
                Text("Idle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            case .running:
                ProgressView()
                    .controlSize(.small)
                Text("Running...")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.amber)
            case .complete:
                StatusDot(color: Theme.green, size: 6)
                Text("Complete")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.green)
            case .error:
                StatusDot(color: Theme.crimson, size: 6)
                Text("Error")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.crimson)
            }
        }
    }

    // MARK: - Actions

    private func runDump() {
        guard !dumpDatabase.isEmpty, !dumpOutputPath.isEmpty else { return }

        dumpOutput.removeAll()
        dumpStatus = .running

        let uri = viewModel.connectionURI.isEmpty ? "mongodb://localhost:27017" : viewModel.connectionURI
        let collection = dumpCollection.isEmpty ? nil : dumpCollection

        let stream = viewModel.dumpRestoreService.dump(
            uri: uri,
            database: dumpDatabase,
            collection: collection,
            outputPath: dumpOutputPath,
            gzip: dumpGzip
        )

        Task {
            for await line in stream {
                await MainActor.run {
                    dumpOutput.append(line)
                }
            }
            await MainActor.run {
                if let lastLine = dumpOutput.last, lastLine.contains("successfully") {
                    dumpStatus = .complete
                } else if let lastLine = dumpOutput.last, lastLine.lowercased().contains("error") {
                    dumpStatus = .error
                } else {
                    dumpStatus = .complete
                }
            }
        }
    }

    private func runRestore() {
        guard !restoreInputPath.isEmpty else { return }

        restoreOutput.removeAll()
        restoreStatus = .running

        let uri = viewModel.connectionURI.isEmpty ? "mongodb://localhost:27017" : viewModel.connectionURI
        let database = restoreTargetDatabase.isEmpty ? nil : restoreTargetDatabase

        let stream = viewModel.dumpRestoreService.restore(
            uri: uri,
            inputPath: restoreInputPath,
            database: database,
            drop: restoreDrop
        )

        Task {
            for await line in stream {
                await MainActor.run {
                    restoreOutput.append(line)
                }
            }
            await MainActor.run {
                if let lastLine = restoreOutput.last, lastLine.contains("successfully") {
                    restoreStatus = .complete
                } else if let lastLine = restoreOutput.last, lastLine.lowercased().contains("error") {
                    restoreStatus = .error
                } else {
                    restoreStatus = .complete
                }
            }
        }
    }

    // MARK: - Helpers

    private func selectFolder(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a directory"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            completion(url.path)
        }
    }

    private func lineColor(_ line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("failed") {
            return Theme.crimson
        }
        if lower.contains("warning") {
            return Theme.amber
        }
        if lower.contains("successfully") || lower.contains("done") || lower.contains("complete") {
            return Theme.green
        }
        return Color.white.opacity(0.85)
    }
}
