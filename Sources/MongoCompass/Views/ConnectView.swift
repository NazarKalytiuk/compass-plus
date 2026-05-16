import SwiftUI
import UniformTypeIdentifiers
import AppKit

@MainActor
struct ConnectView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var uri: String = "mongodb://localhost:27017"
    @State private var name: String = ""
    @State private var environment: ConnectionModel.ConnectionEnvironment = .local
    @State private var saveConnection: Bool = true

    @State private var isImporting = false
    @State private var isExporting = false
    @State private var importExportError: String?
    @State private var showAdvanced = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack {
                Spacer(minLength: 24)
                connectCard
                    .frame(maxWidth: 720)
                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
        }
        .background(canvasBackground)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $isExporting,
            document: ConnectionsExportDocument(storageService: viewModel.storageService),
            contentType: .json,
            defaultFilename: "mongocompass_connections.json"
        ) { result in
            handleExport(result)
        }
    }

    // MARK: - Canvas

    private var canvasBackground: some View {
        ZStack {
            Theme.surface0
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 1.0, green: 0.961, blue: 0.933),
                    Color.clear
                ]),
                center: UnitPoint(x: 0.5, y: 0.0),
                startRadius: 0,
                endRadius: 600
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    // MARK: - Card

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandBar
                .padding(.bottom, 18)

            Text("Connect to MongoDB")
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.33)
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 4)

            Text(subtitleText)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textMuted)
                .padding(.bottom, 22)

            uriGroup
                .padding(.bottom, 14)

            saveRow
                .padding(.bottom, 22)

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.bottom, 18)

            recentSection
                .padding(.bottom, 22)

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.bottom, 16)

            connectFooter
        }
        .padding(.horizontal, 36)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Theme.shadowElevated, radius: 24, y: 10)
    }

    private var subtitleText: String {
        if viewModel.connectionError != nil {
            return "We couldn't reach this cluster. Check the host or your credentials, then retry."
        }
        return "Paste a connection string or pick a recent cluster. Compass+ never stores credentials in plain text."
    }

    // MARK: - Brand

    private var brandBar: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Theme.brandGradient)
                    .frame(width: 28, height: 28)
                Path { p in
                    p.move(to: CGPoint(x: 9, y: 10))
                    p.addLine(to: CGPoint(x: 19, y: 10))
                    p.addLine(to: CGPoint(x: 14, y: 19))
                    p.closeSubpath()
                }
                .fill(.white)
            }
            HStack(spacing: 0) {
                Text("Compass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("+")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.primary)
                    .padding(.leading, 1)
            }
        }
    }

    // MARK: - URI group

    private var uriGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Connection URI")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textMuted)
                if let err = viewModel.connectionError {
                    Text(errorPillLabel(err)).pillBadge(.danger)
                }
                Spacer()
            }

            uriField

            if let err = viewModel.connectionError {
                errorLine(err)
                    .padding(.top, 4)
                diagRow
                    .padding(.top, 4)
            }
        }
    }

    private var uriField: some View {
        HStack(spacing: 8) {
            Text(detectedPrefix)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
            TextField("admin:password@host/db?retryWrites=true&w=majority", text: uriBody)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
            Text(detectedPrefix == "mongodb+srv://" ? "SRV" : "TCP")
                .pillBadge(.info)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(viewModel.connectionError != nil ? Theme.dangerTint : Theme.surface3)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var detectedPrefix: String {
        uri.hasPrefix("mongodb+srv://") ? "mongodb+srv://" : "mongodb://"
    }

    private var uriBody: Binding<String> {
        Binding(
            get: {
                if uri.hasPrefix("mongodb+srv://") {
                    return String(uri.dropFirst("mongodb+srv://".count))
                }
                if uri.hasPrefix("mongodb://") {
                    return String(uri.dropFirst("mongodb://".count))
                }
                return uri
            },
            set: { newValue in
                uri = detectedPrefix + newValue
            }
        )
    }

    private func errorPillLabel(_ err: String) -> String {
        let lower = err.lowercased()
        if lower.contains("auth") { return "Authentication failed" }
        if lower.contains("timeout") || lower.contains("timed out") { return "Connection timed out" }
        if lower.contains("dns") || lower.contains("hostname") || lower.contains("unreachable") {
            return "Host unreachable"
        }
        return "Connection failed"
    }

    private func errorLine(_ err: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.danger)
                .frame(width: 16, height: 16)
            Text(err)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.dangerDeep)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.dangerTint)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var diagRow: some View {
        HStack(spacing: 8) {
            diagCard(label: "DNS", value: dnsValue, color: dnsColor)
            diagCard(label: "TLS handshake", value: tlsValue, color: tlsColor)
            diagCard(label: "Authentication", value: authValue, color: authColor)
        }
    }

    private var dnsValue: String {
        guard let phase = viewModel.lastDiagnostics?.dns else { return "—" }
        return phase.detail
    }
    private var dnsColor: Color {
        guard let phase = viewModel.lastDiagnostics?.dns else { return Theme.textMuted }
        return phase.ok ? Theme.success : Theme.danger
    }

    private var tlsValue: String {
        if let phase = viewModel.lastDiagnostics?.tls { return phase.detail }
        if viewModel.lastDiagnostics?.tlsEnabled == false { return "not requested" }
        return "—"
    }
    private var tlsColor: Color {
        if let phase = viewModel.lastDiagnostics?.tls {
            return phase.ok ? Theme.success : Theme.danger
        }
        if viewModel.lastDiagnostics?.tlsEnabled == false { return Theme.textMuted }
        return Theme.textMuted
    }

    private var authValue: String {
        guard let phase = viewModel.lastDiagnostics?.auth else { return "—" }
        return phase.detail
    }
    private var authColor: Color {
        guard let phase = viewModel.lastDiagnostics?.auth else { return Theme.textMuted }
        return phase.ok ? Theme.success : Theme.danger
    }

    private func diagCard(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.84)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textMuted)
            HStack(spacing: 6) {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 13, height: 13)
                    .overlay(Circle().fill(color).frame(width: 7, height: 7))
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSoft)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface3)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Save row

    private var saveRow: some View {
        HStack(spacing: 10) {
            pillToggle(isOn: $saveConnection)
            Text("Save connection")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textSoft)
            Spacer()
            envPicker
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
                    .frame(width: 32, height: 18)
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .padding(.horizontal, 2)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var envPicker: some View {
        HStack(spacing: 6) {
            Text("Favorite color")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
            ForEach(ConnectionModel.ConnectionEnvironment.allCases, id: \.self) { env in
                Button {
                    environment = env
                } label: {
                    Circle()
                        .fill(env.color.opacity(0.2))
                        .frame(width: 13, height: 13)
                        .overlay(Circle().fill(env.color).frame(width: 7, height: 7))
                        .opacity(environment == env ? 1 : 0.35)
                }
                .buttonStyle(.plain)
                .help(env.displayName)
            }
        }
    }

    // MARK: - Recent section

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent connections · \(viewModel.savedConnections.count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.94)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                Text(viewModel.savedConnections.contains { $0.environment == environment }
                     ? "Pinned: \(environment.displayName) · then last opened"
                     : "Sorted by last opened")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textMuted)
            }

            if viewModel.savedConnections.isEmpty {
                emptyRecent
            } else {
                let pinned = sortedConnections.filter { $0.environment == environment }
                let rest = sortedConnections.filter { $0.environment != environment }
                VStack(spacing: 4) {
                    if !pinned.isEmpty {
                        ForEach(pinned) { conn in
                            recentRow(conn)
                        }
                        if !rest.isEmpty {
                            Rectangle()
                                .fill(Theme.hairline)
                                .frame(height: 1)
                                .padding(.vertical, 4)
                        }
                    }
                    ForEach(rest) { conn in
                        recentRow(conn)
                    }
                }
            }

            if let err = importExportError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.warning)
                    Text(err)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.warningDeep)
                    Spacer()
                    Button {
                        importExportError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.warningDeep)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.warningTint)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var sortedConnections: [ConnectionModel] {
        viewModel.savedConnections.sorted { $0.lastUsed > $1.lastUsed }
    }

    private var emptyRecent: some View {
        VStack(spacing: 6) {
            Image(systemName: "externaldrive")
                .font(.system(size: 16))
                .foregroundStyle(Theme.textMuted)
            Text("No saved connections yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Connect to a server above and it will appear here.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Theme.surface3)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func recentRow(_ conn: ConnectionModel) -> some View {
        let isSelected = uri == conn.uri
        let dotColor = statusDotColor(for: conn)
        return HStack(spacing: 12) {
            Circle()
                .fill(dotColor.opacity(0.2))
                .frame(width: 13, height: 13)
                .overlay(Circle().fill(dotColor).frame(width: 7, height: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(conn.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(hostLine(conn))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(relativeTimeString(from: conn.lastUsed))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
                .frame(minWidth: 76, alignment: .trailing)

            Button {
                Task { await viewModel.connect(uri: conn.uri, name: conn.name) }
            } label: {
                Text("Connect")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isConnecting)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? Theme.surfaceHover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            uri = conn.uri
            name = conn.name
            environment = conn.environment
        }
        .contextMenu {
            Button("Load into form") {
                uri = conn.uri
                name = conn.name
                environment = conn.environment
            }
            Button("Connect now") {
                Task { await viewModel.connect(uri: conn.uri, name: conn.name) }
            }
            Divider()
            Button("Remove from saved", role: .destructive) {
                viewModel.storageService.removeConnection(id: conn.id)
                viewModel.savedConnections = viewModel.storageService.loadConnections()
            }
        }
    }

    private func hostLine(_ conn: ConnectionModel) -> String {
        let prefix = conn.uri.hasPrefix("mongodb+srv://") ? "mongodb+srv://" : "mongodb://"
        return prefix + conn.hostDisplay
    }

    private func statusDotColor(for conn: ConnectionModel) -> Color {
        if let ping = conn.pingMs {
            if ping < 100 { return Theme.success }
            if ping < 500 { return Theme.warning }
            return Theme.danger
        }
        let days = Int(Date().timeIntervalSince(conn.lastUsed) / 86400)
        if days < 1   { return Theme.success }
        if days < 7   { return Theme.warning }
        if days < 30  { return Theme.textMuted }
        return Theme.danger
    }

    private func relativeTimeString(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60)) min ago" }
        if interval < 86400 { return "\(Int(interval / 3600)) h ago" }
        let calendar = Calendar.current
        if let days = calendar.dateComponents([.day], from: date, to: now).day {
            if days == 1 { return "yesterday" }
            if days < 7  { return "\(days) days ago" }
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    // MARK: - Footer

    private var connectFooter: some View {
        HStack(spacing: 12) {
            helpText
            Spacer()
            advancedButton
            connectCTA
        }
    }

    private var helpText: some View {
        let isError = viewModel.connectionError != nil
        let helpLabel = isError ? "Still stuck?" : "First time?"
        let linkLabel = isError ? "Open the connection log ↗" : "Read the URI guide ↗"
        let linkURL = URL(string: "https://www.mongodb.com/docs/manual/reference/connection-string/")!
        return HStack(spacing: 4) {
            Text(helpLabel)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
            Link(destination: linkURL) {
                Text(linkLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.primaryDeep)
            }
        }
    }

    private var advancedButton: some View {
        Button {
            showAdvanced.toggle()
        } label: {
            Text("Advanced…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSoft)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Theme.surface3)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showAdvanced, arrowEdge: .top) {
            advancedPopover
        }
    }

    private var advancedPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Advanced options")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Connection name").sectionHeaderStyle()
                TextField("e.g. Marketing-Production-Replica", text: $name)
                    .textFieldStyle(.themedSans)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Environment").sectionHeaderStyle()
                Picker("Environment", selection: $environment) {
                    ForEach(ConnectionModel.ConnectionEnvironment.allCases, id: \.self) { env in
                        Text(env.displayName.uppercased()).tag(env)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Rectangle().fill(Theme.hairline).frame(height: 1)

            HStack(spacing: 8) {
                Button {
                    isImporting = true
                    showAdvanced = false
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import…")
                    }
                }
                .buttonStyle(.ghost)
                Button {
                    isExporting = true
                    showAdvanced = false
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export…")
                    }
                }
                .buttonStyle(.ghost)
                Spacer()
                Button {
                    showAdvanced = false
                } label: {
                    Text("Done")
                }
                .buttonStyle(.accent)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private var connectCTA: some View {
        Button {
            let connName = name.isEmpty ? extractConnectionName(from: uri) : name
            Task { await viewModel.connect(uri: uri, name: connName, save: saveConnection) }
        } label: {
            HStack(spacing: 6) {
                if viewModel.isConnecting {
                    ProgressView().controlSize(.small)
                    Text("Connecting…")
                } else {
                    Text(viewModel.connectionError != nil ? "Retry" : "Connect")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background(uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Theme.primary.opacity(0.5)
                        : Theme.primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: Theme.primaryDeep.opacity(0.3), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isConnecting)
    }

    // MARK: - Helpers

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

// MARK: - Connections Export Document

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
