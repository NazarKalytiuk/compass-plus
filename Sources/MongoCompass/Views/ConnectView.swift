import SwiftUI
import UniformTypeIdentifiers

struct ConnectView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var uri: String = "mongodb://localhost:27017"
    @State private var name: String = ""
    @State private var environment: ConnectionModel.ConnectionEnvironment = .local

    @State private var isImporting = false
    @State private var isExporting = false
    @State private var importExportError: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                headerSection
                connectionFormSection
                if let error = viewModel.connectionError {
                    errorBanner(error)
                }
                if let error = importExportError {
                    errorBanner(error)
                }
                savedConnectionsSection
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.midnight)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $isExporting,
            document: ConnectionsExportDocument(
                storageService: viewModel.storageService
            ),
            contentType: .json,
            defaultFilename: "mongocompass_connections.json"
        ) { result in
            handleExport(result)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.green)
                Text("Compass+")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Theme.green)
            }
            Text("MongoDB GUI Client")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Connection Form

    private var connectionFormSection: some View {
        VStack(spacing: 16) {
            // URI field
            VStack(alignment: .leading, spacing: 6) {
                Text("Connection URI")
                    .sectionHeaderStyle()
                TextField("mongodb://localhost:27017", text: $uri)
                    .font(.system(size: 15, design: .monospaced))
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Theme.midnight)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                    .foregroundStyle(.white)
            }

            HStack(spacing: 16) {
                // Name field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Connection Name")
                        .sectionHeaderStyle()
                    TextField("My Server", text: $name)
                        .textFieldStyle(.themed)
                }

                // Environment picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Environment")
                        .sectionHeaderStyle()
                    Picker("Environment", selection: $environment) {
                        ForEach(ConnectionModel.ConnectionEnvironment.allCases, id: \.self) { env in
                            Text(env.displayName).tag(env)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                }
            }

            // Connect button
            HStack {
                Spacer()
                if viewModel.isConnecting {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 8)
                    Text("Connecting...")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Button {
                        let connName = name.isEmpty ? extractConnectionName(from: uri) : name
                        Task {
                            await viewModel.connect(uri: uri, name: connName)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                            Text("Connect")
                        }
                    }
                    .buttonStyle(.accent)
                    .disabled(uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Spacer()
            }
        }
        .padding(24)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
        .frame(maxWidth: 700)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.crimson)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.crimson)
            Spacer()
            Button {
                viewModel.connectionError = nil
                importExportError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.crimson.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.crimson.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: 700)
    }

    // MARK: - Saved Connections

    private var savedConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Saved Connections")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    isImporting = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import")
                    }
                }
                .buttonStyle(.ghost)

                Button {
                    isExporting = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export")
                    }
                }
                .buttonStyle(.ghost)
            }

            if viewModel.savedConnections.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.textSecondary)
                    Text("No saved connections yet")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                    Text("Connect to a server and it will appear here.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.savedConnections) { connection in
                        savedConnectionCard(connection)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Saved Connection Card

    private func savedConnectionCard(_ connection: ConnectionModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(connection.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Button {
                    viewModel.storageService.removeConnection(id: connection.id)
                    viewModel.savedConnections = viewModel.storageService.loadConnections()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Text(connection.hostDisplay)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(connection.environment.displayName)
                    .pillBadge(color: connection.environment.color)

                Spacer()

                if let ping = connection.pingMs {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(pingColor(ping))
                            .frame(width: 6, height: 6)
                        Text("\(ping)ms")
                            .font(.system(size: 11))
                            .foregroundStyle(pingColor(ping))
                    }
                }
            }

            Text(relativeTimeString(from: connection.lastUsed))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
        }
        .cardStyle(padding: 14, cornerRadius: 10)
        .contentShape(Rectangle())
        .onTapGesture {
            uri = connection.uri
            name = connection.name
            environment = connection.environment
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    uri == connection.uri ? Theme.green.opacity(0.5) : Color.clear,
                    lineWidth: 1.5
                )
        )
    }

    // MARK: - Helpers

    private func pingColor(_ ms: Int) -> Color {
        if ms < 50 { return Theme.green }
        if ms < 200 { return Theme.amber }
        return Theme.crimson
    }

    private func relativeTimeString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        }
        if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        }
        let days = Int(interval / 86400)
        if days == 1 { return "Yesterday" }
        if days < 30 { return "\(days) days ago" }
        let months = Int(days / 30)
        return "\(months) month\(months == 1 ? "" : "s") ago"
    }

    private func extractConnectionName(from uri: String) -> String {
        let cleaned = uri
            .replacingOccurrences(of: "mongodb://", with: "")
            .replacingOccurrences(of: "mongodb+srv://", with: "")
        if let atIndex = cleaned.firstIndex(of: "@") {
            let afterAt = String(cleaned[cleaned.index(after: atIndex)...])
            if let slashIndex = afterAt.firstIndex(of: "/") {
                return String(afterAt[afterAt.startIndex..<slashIndex])
            }
            return afterAt
        }
        if let slashIndex = cleaned.firstIndex(of: "/") {
            return String(cleaned[cleaned.startIndex..<slashIndex])
        }
        return cleaned
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try viewModel.storageService.importConnections(from: url)
                viewModel.savedConnections = viewModel.storageService.loadConnections()
            } catch {
                importExportError = "Import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            importExportError = "Import failed: \(error.localizedDescription)"
        }
    }

    private func handleExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            break
        case .failure(let error):
            importExportError = "Export failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Connections Export Document (for fileExporter)

struct ConnectionsExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(storageService: StorageService) {
        let connections = storageService.loadConnections()
        self.data = (try? JSONEncoder().encode(connections)) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
