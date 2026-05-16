import SwiftUI
import AppKit

@MainActor
struct ShellView: View {
    @Environment(AppViewModel.self) private var viewModel

    // MARK: - Shell process state

    @State private var outputLines: [ShellOutputLine] = []
    @State private var caretVisible = false
    @State private var currentInput = ""
    @State private var commandHistory: [String] = []
    @State private var historyIndex: Int = -1
    @State private var shellProcess: Process?
    @State private var stdinPipe: Pipe?
    @State private var isRunning = false
    @State private var mongoshNotFound = false
    @State private var mongoshPath: String? = nil
    @State private var mongoshVersion: String? = nil
    @State private var isLocatingMongosh = false

    // MARK: - Saved commands state

    @State private var showSaveSheet = false
    @State private var saveCommandName = ""
    @State private var saveCommandCategory = "Custom"
    @State private var savedSearchQuery = ""
    @State private var selectedCategory: String = "All"

    @FocusState private var inputFocused: Bool

    // MARK: - Models

    enum LineKind { case dim, echo, output, error }

    struct ShellOutputLine: Identifiable {
        let id = UUID()
        let text: String
        let kind: LineKind
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if mongoshNotFound {
                mongoshNotFoundBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface0)
        .onAppear { resolveMongoshIfNeeded() }
        .onDisappear { stopShell() }
        .sheet(isPresented: $showSaveSheet) { saveCommandSheet }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            breadcrumb
            statusPill
            Spacer()
            ghostBtn("Clear") {
                outputLines.removeAll()
            }
            .disabled(outputLines.isEmpty)
            ghostBtn("Copy session") { copySession() }
                .disabled(outputLines.isEmpty)
            if isRunning {
                Button { stopShell() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill").font(.system(size: 10))
                        Text("Disconnect")
                    }
                }
                .buttonStyle(.accentCompact)
            } else {
                Button { startShell() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill").font(.system(size: 10))
                        Text("Connect")
                    }
                }
                .buttonStyle(.accentCompact)
                .disabled(!viewModel.isConnected || mongoshNotFound)
            }
            Button {
                openSaveSheet(seed: currentInput)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                    Text("Save command")
                }
            }
            .buttonStyle(.accentCompact)
            .disabled(currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface1)
        .shadow(color: Theme.shadowAmbient.opacity(0.6), radius: 0.5, y: 0.5)
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRunning ? Theme.success : Theme.textMuted)
                .frame(width: 7, height: 7)
                .padding(.trailing, 2)
            if let db = viewModel.activeTab.selectedDatabase, !db.isEmpty {
                Text(db)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.codeKey)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            Text("shell")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
            if let v = mongoshVersion, !v.isEmpty {
                Text("· mongosh \(v)")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if isLocatingMongosh {
            Text("locating mongosh…").pillBadge(.info)
        } else if mongoshNotFound {
            Text("not installed").pillBadge(.danger)
        } else if isRunning {
            Text("connected").pillBadge(.success)
        } else {
            Text("disconnected").pillBadge(.neutral)
        }
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

    private func copySession() {
        let text = outputLines.map { line -> String in
            switch line.kind {
            case .echo: return "\(promptLabel) \(line.text)"
            default: return line.text
            }
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Content (split)

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            termWrap
            savedSidebar
                .frame(width: 320)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    // MARK: - Terminal wrap

    private var termWrap: some View {
        VStack(spacing: 8) {
            terminal
            termInput
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var terminal: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if outputLines.isEmpty {
                        terminalPlaceholder
                    } else {
                        ForEach(outputLines) { line in
                            terminalLineView(line)
                                .id(line.id)
                        }
                    }
                    liveTail
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.codeBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: Color.black.opacity(0.25), radius: 4, y: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: outputLines.count) { _, _ in
                if let last = outputLines.last {
                    withAnimation(.linear(duration: 0.06)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var liveTail: some View {
        HStack(spacing: 6) {
            Text(promptLabel)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.codePrompt)
            if isRunning {
                Rectangle()
                    .fill(Theme.codePrompt)
                    .frame(width: 8, height: 14)
                    .opacity(caretVisible ? 1 : 0.15)
                    .animation(.linear(duration: 0.55).repeatForever(autoreverses: true), value: caretVisible)
                    .onAppear { caretVisible.toggle() }
            } else {
                Text("(disconnected)")
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.codeMuted)
            }
        }
        .padding(.top, 4)
    }

    private var promptLabel: String {
        let db = viewModel.activeTab.selectedDatabase
        let name = (db?.isEmpty == false) ? db! : "test"
        return "\(name) >"
    }

    private func terminalLineView(_ line: ShellOutputLine) -> some View {
        Group {
            switch line.kind {
            case .echo:
                HStack(alignment: .top, spacing: 6) {
                    Text(promptLabel)
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.codePrompt)
                    Text(line.text)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Theme.codeKey)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .dim:
                Text(line.text)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.codeMuted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .error:
                Text(line.text)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.danger.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .output:
                Text(Self.highlightShellOutput(line.text))
                    .font(.system(size: 12.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .lineSpacing(3)
    }

    /// Build a colour-tinted AttributedString for shell output. Lexer-lite —
    /// regex passes for double-quoted strings, BSON wrappers
    /// (`ObjectId(...)` / `ISODate(...)` / `UUID(...)`), `$keys`, numbers,
    /// and boolean/null literals.
    static func highlightShellOutput(_ raw: String) -> AttributedString {
        var attr = AttributedString(raw)
        attr.foregroundColor = Theme.codeFg
        let full = NSRange(raw.startIndex..., in: raw)

        let patterns: [(String, Color)] = [
            // double-quoted strings (non-greedy, allow escaped quotes)
            ("\"(?:\\\\.|[^\"\\\\])*\"", Theme.codeString),
            // single-quoted strings
            ("'(?:\\\\.|[^'\\\\])*'", Theme.codeString),
            // BSON wrappers
            ("\\b(ObjectId|ISODate|UUID|NumberLong|NumberInt|NumberDecimal|BinData|Timestamp)\\b", Theme.codeKeyword),
            // bool / null literals
            ("\\b(true|false|null|undefined)\\b", Theme.codeBool),
            // $-prefixed keys
            ("\\$[A-Za-z_][A-Za-z0-9_]*", Theme.codeKey),
            // numbers (after strings so digits inside quotes don't recolour)
            ("\\b-?\\d+(?:\\.\\d+)?\\b", Theme.codeNumber)
        ]

        for (pat, color) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pat) else { continue }
            regex.enumerateMatches(in: raw, range: full) { match, _, _ in
                guard let m = match,
                      let range = Range(m.range, in: raw),
                      let attrRange = attr.range(of: String(raw[range])) else { return }
                // `attr.range(of:)` returns the FIRST occurrence — for repeated
                // tokens that's wrong. Fall back to direct range mapping via
                // NSRange→AttributedString.Index pair.
                _ = attrRange
                let lower = AttributedString.Index(raw.utf16.index(raw.utf16.startIndex, offsetBy: m.range.location), within: attr)
                let upper = AttributedString.Index(raw.utf16.index(raw.utf16.startIndex, offsetBy: m.range.location + m.range.length), within: attr)
                if let lo = lower, let hi = upper, lo < hi {
                    attr[lo..<hi].foregroundColor = color
                }
            }
        }
        return attr
    }

    private var terminalPlaceholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("// Compass+ MongoDB Shell")
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Theme.codeKeyword)
            Text(isRunning
                 ? "Type a command below and press return."
                 : "Press Connect to start a mongosh session.")
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Theme.codeMuted)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Input bar

    private var termInput: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("›")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.codePrompt)
                .padding(.top, 2)

            TextField(
                isRunning ? "Run a mongosh command…  (⌘↵ to submit, ↵ for newline)" : "Connect to start a session",
                text: $currentInput,
                axis: .vertical
            )
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(Theme.codeFg)
            .focused($inputFocused)
            .disabled(!isRunning)
            .onKeyPress(.upArrow) {
                // Only walk history when the input fits on a single line —
                // otherwise let arrow keys move the caret inside multi-line
                // text as a user would expect.
                guard !currentInput.contains("\n") else { return .ignored }
                navigateHistoryUp()
                return .handled
            }
            .onKeyPress(.downArrow) {
                guard !currentInput.contains("\n") else { return .ignored }
                navigateHistoryDown()
                return .handled
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 4) {
                iconBtn("arrow.up", help: "History (↑)") { navigateHistoryUp() }
                iconBtn("bookmark", help: "Save command") {
                    openSaveSheet(seed: currentInput)
                }
                Button { sendCommand() } label: {
                    HStack(spacing: 5) {
                        Text("Run").font(.system(size: 12, weight: .semibold))
                        Text("⌘↵")
                            .font(.system(size: 10, design: .monospaced))
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!isRunning || currentInput.isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.codeBg2)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func iconBtn(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Saved sidebar

    private var savedSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            savedHead
            savedSearch
            savedCats
            savedList
        }
        .padding(14)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
        .frame(maxHeight: .infinity)
    }

    private var savedHead: some View {
        HStack(spacing: 8) {
            Text("Saved commands")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("\(viewModel.savedCommands.count)")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textMuted)
            Spacer()
            Button {
                openSaveSheet(seed: currentInput)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Save current command")
            .disabled(currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var savedSearch: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)
            TextField("Filter saved…", text: $savedSearchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surface3)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var savedCats: some View {
        WrapHStack(spacing: 4, lineSpacing: 4) {
            ForEach(Array(categoryList.enumerated()), id: \.offset) { _, item in
                let (name, count, kind) = item
                let selected = selectedCategory == name
                Button {
                    selectedCategory = name
                } label: {
                    Text("\(name) · \(count)")
                        .pillBadge(selected ? .accent : kind)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var categoryList: [(String, Int, BadgeKind)] {
        var counts: [String: Int] = [:]
        for cmd in viewModel.savedCommands {
            let cat = cmd.category.isEmpty ? "Custom" : cmd.category
            counts[cat, default: 0] += 1
        }
        let palette: [BadgeKind] = [.neutral, .info, .success, .warning, .violet, .danger]
        var rows: [(String, Int, BadgeKind)] = [("All", viewModel.savedCommands.count, .accent)]
        for (i, entry) in counts.sorted(by: { $0.value > $1.value }).enumerated() {
            rows.append((entry.key, entry.value, palette[i % palette.count]))
        }
        return rows
    }

    private var savedList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if viewModel.savedCommands.isEmpty {
                    savedEmpty
                        .padding(.vertical, 14)
                } else if filteredSaved.isEmpty {
                    Text("No matches")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    ForEach(Array(filteredSaved.enumerated()), id: \.element.id) { idx, cmd in
                        savedRow(cmd, hotkeyHint: idx < 9 ? "⌘\(idx + 1)" : "")
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .background(
            // Hidden ⌘1…⌘9 hotkeys that run the first 9 saved commands.
            HStack(spacing: 0) {
                ForEach(Array(filteredSaved.prefix(9).enumerated()), id: \.element.id) { idx, cmd in
                    Button("") { runSavedCommand(cmd) }
                        .keyboardShortcut(
                            KeyEquivalent(Character("\(idx + 1)")),
                            modifiers: .command
                        )
                }
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        )
        .frame(maxHeight: .infinity)
    }

    private var savedEmpty: some View {
        VStack(spacing: 8) {
            Image(systemName: "bookmark")
                .font(.system(size: 16))
                .foregroundStyle(Theme.textMuted)
            Text("No saved commands")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Type a mongosh command, then save it for later.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var filteredSaved: [SavedCommand] {
        let q = savedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return viewModel.savedCommands.filter { cmd in
            let cat = cmd.category.isEmpty ? "Custom" : cmd.category
            let matchCategory = (selectedCategory == "All") ||
                cat.lowercased() == selectedCategory.lowercased()
            guard matchCategory else { return false }
            if q.isEmpty { return true }
            return cmd.name.lowercased().contains(q) ||
                cmd.command.lowercased().contains(q) ||
                cmd.category.lowercased().contains(q)
        }
    }

    private func savedRow(_ cmd: SavedCommand, hotkeyHint: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cmd.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(cmd.command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !hotkeyHint.isEmpty {
                Text(hotkeyHint)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(currentInput == cmd.command ? Theme.surfaceHover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            currentInput = cmd.command
            inputFocused = true
        }
        .contextMenu {
            Button("Run") { runSavedCommand(cmd) }
                .disabled(!isRunning)
            Button("Load into input") {
                currentInput = cmd.command
                inputFocused = true
            }
            Divider()
            Button("Delete", role: .destructive) {
                viewModel.removeSavedCommand(id: cmd.id)
            }
        }
    }

    // MARK: - mongosh missing banner

    private var mongoshNotFoundBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("mongosh not found on this system")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("The MongoDB Shell binary couldn't be located in any standard install path.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }

            Text("brew install mongosh")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.codeString)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.codeBg)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                Spacer()
                ghostBtn("Locate mongosh…") { locateMongoshManually() }
                Button {
                    mongoshNotFound = false
                    resolveMongoshIfNeeded(force: true)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10))
                        Text("Retry")
                    }
                }
                .buttonStyle(.accentCompact)
            }
        }
        .padding(14)
        .background(Theme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
    }

    // MARK: - Save sheet

    private var saveCommandSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.primaryDeep)
                Text("Save Command")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Command").sectionHeaderStyle()
                Text(currentInput.trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.codeString)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.codeBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").sectionHeaderStyle()
                TextField("e.g. List databases", text: $saveCommandName)
                    .textFieldStyle(.themedSans)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Category").sectionHeaderStyle()
                TextField("Custom", text: $saveCommandCategory)
                    .textFieldStyle(.themedSans)
            }

            HStack {
                Spacer()
                Button { showSaveSheet = false } label: { Text("Cancel") }
                    .buttonStyle(.ghost)
                    .keyboardShortcut(.cancelAction)
                Button {
                    viewModel.saveShellCommand(
                        name: saveCommandName,
                        command: currentInput,
                        category: saveCommandCategory
                    )
                    showSaveSheet = false
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                        Text("Save")
                    }
                }
                .buttonStyle(.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(Theme.surface1)
    }

    private func openSaveSheet(seed: String) {
        let trimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        saveCommandName = ""
        saveCommandCategory = "Custom"
        showSaveSheet = true
    }

    private func runSavedCommand(_ cmd: SavedCommand) {
        guard isRunning else {
            currentInput = cmd.command
            inputFocused = true
            return
        }
        currentInput = cmd.command
        viewModel.markCommandUsed(id: cmd.id)
        sendCommand()
    }

    // MARK: - mongosh discovery

    private func resolveMongoshIfNeeded(force: Bool = false) {
        if !force && mongoshPath != nil { return }
        isLocatingMongosh = true
        Task.detached {
            let path = Self.findMongoshNonisolated()
            let version = path.flatMap { Self.runMongoshVersionNonisolated(path: $0) }
            await MainActor.run {
                self.mongoshPath = path
                self.mongoshVersion = version
                self.mongoshNotFound = (path == nil)
                self.isLocatingMongosh = false
            }
        }
    }

    private nonisolated static func runMongoshVersionNonisolated(path: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let raw, !raw.isEmpty else { return nil }
            return raw.hasPrefix("v") ? raw : "v\(raw)"
        } catch {
            return nil
        }
    }

    private nonisolated static func findMongoshNonisolated() -> String? {
        let searchPaths = [
            "/usr/local/bin/mongosh",
            "/opt/homebrew/bin/mongosh",
            "/usr/bin/mongosh",
            "/opt/local/bin/mongosh"
        ]
        let whichProcess = Process()
        let pipe = Pipe()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["mongosh"]
        whichProcess.standardOutput = pipe
        whichProcess.standardError = Pipe()
        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            if whichProcess.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                    return path
                }
            }
        } catch { }
        for path in searchPaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private func runMongoshVersion(path: String) -> String? {
        Self.runMongoshVersionNonisolated(path: path)
    }

    private func findMongosh() -> String? {
        Self.findMongoshNonisolated()
    }

    private func locateMongoshManually() {
        let panel = NSOpenPanel()
        panel.title = "Locate mongosh"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            if FileManager.default.isExecutableFile(atPath: path) {
                mongoshPath = path
                mongoshVersion = runMongoshVersion(path: path)
                mongoshNotFound = false
            } else {
                outputLines.append(ShellOutputLine(
                    text: "Selected file is not executable: \(path)",
                    kind: .error
                ))
            }
        }
    }

    private func restartShell() {
        let wasRunning = isRunning
        if wasRunning { stopShell() }
        outputLines.removeAll()
        if wasRunning { startShell() }
    }

    // MARK: - Shell process

    private func startShell() {
        let resolvedPath = mongoshPath ?? findMongosh()
        guard let mongoshPath = resolvedPath else {
            mongoshNotFound = true
            return
        }
        mongoshNotFound = false
        self.mongoshPath = mongoshPath

        let uri = viewModel.connectionURI.isEmpty
            ? "mongodb://localhost:27017"
            : viewModel.connectionURI

        outputLines.append(ShellOutputLine(text: "Connecting to \(uri)…", kind: .dim))

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: mongoshPath)
        process.arguments = [uri, "--quiet"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let str = String(data: data, encoding: .utf8) {
                let lines = str.components(separatedBy: "\n")
                DispatchQueue.main.async {
                    for line in lines where !line.isEmpty {
                        self.outputLines.append(ShellOutputLine(text: line, kind: .output))
                    }
                }
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let str = String(data: data, encoding: .utf8) {
                let lines = str.components(separatedBy: "\n")
                DispatchQueue.main.async {
                    for line in lines where !line.isEmpty {
                        self.outputLines.append(ShellOutputLine(text: line, kind: .error))
                    }
                }
            }
        }

        do {
            try process.run()
            shellProcess = process
            stdinPipe = stdin
            isRunning = true
            outputLines.append(ShellOutputLine(
                text: "Connected. Using DB: \(viewModel.activeTab.selectedDatabase ?? "test")",
                kind: .dim
            ))
            process.terminationHandler = { _ in
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.outputLines.append(ShellOutputLine(
                        text: "Shell session ended.",
                        kind: .dim
                    ))
                }
            }
        } catch {
            outputLines.append(ShellOutputLine(
                text: "Error starting mongosh: \(error.localizedDescription)",
                kind: .error
            ))
        }
    }

    private func stopShell() {
        if let process = shellProcess, process.isRunning {
            process.terminate()
        }
        shellProcess = nil
        stdinPipe = nil
        isRunning = false
    }

    private func sendCommand() {
        guard isRunning, let stdin = stdinPipe else { return }
        let trimmed = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let command = currentInput
        commandHistory.append(command)
        historyIndex = commandHistory.count
        outputLines.append(ShellOutputLine(text: command, kind: .echo))
        let data = (command + "\n").data(using: .utf8)!
        stdin.fileHandleForWriting.write(data)
        currentInput = ""
    }

    private func navigateHistoryUp() {
        guard !commandHistory.isEmpty else { return }
        if historyIndex > 0 {
            historyIndex -= 1
            currentInput = commandHistory[historyIndex]
        } else if historyIndex == -1 {
            historyIndex = commandHistory.count - 1
            currentInput = commandHistory[historyIndex]
        }
    }

    private func navigateHistoryDown() {
        guard !commandHistory.isEmpty else { return }
        if historyIndex < commandHistory.count - 1 {
            historyIndex += 1
            currentInput = commandHistory[historyIndex]
        } else {
            historyIndex = commandHistory.count
            currentInput = ""
        }
    }
}

// MARK: - WrapHStack — simple wrapping HStack for pill rows

struct WrapHStack: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var totalW: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxW, x > 0 {
                y += rowH + lineSpacing
                x = 0
                rowH = 0
            }
            x += size.width + spacing
            totalW = max(totalW, x)
            rowH = max(rowH, size.height)
        }
        return CGSize(
            width: min(totalW, maxW),
            height: y + rowH
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxW = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x - bounds.minX + size.width > maxW, x > bounds.minX {
                y += rowH + lineSpacing
                x = bounds.minX
                rowH = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
