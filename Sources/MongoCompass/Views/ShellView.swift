import SwiftUI

struct ShellView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var outputLines: [ShellOutputLine] = []
    @State private var currentInput = ""
    @State private var commandHistory: [String] = []
    @State private var historyIndex: Int = -1
    @State private var shellProcess: Process?
    @State private var stdinPipe: Pipe?
    @State private var isRunning = false
    @State private var mongoshNotFound = false

    struct ShellOutputLine: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.green)
                    Text("MongoDB Shell")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }

                Spacer()

                if isRunning {
                    HStack(spacing: 6) {
                        StatusDot(color: Theme.green, size: 6)
                        Text("Connected")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Button {
                    outputLines.removeAll()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Clear")
                    }
                }
                .buttonStyle(.ghost)

                if isRunning {
                    Button {
                        stopShell()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                            Text("Disconnect")
                        }
                    }
                    .buttonStyle(AccentButtonStyle(color: Theme.crimson, isCompact: true))
                } else {
                    Button {
                        startShell()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                            Text("Connect")
                        }
                    }
                    .buttonStyle(.accentCompact)
                    .disabled(!viewModel.isConnected)
                }
            }
            .padding(14)
            .background(Theme.surface.opacity(0.4))

            ThemedDivider()

            if mongoshNotFound {
                mongoshNotFoundView
            } else {
                // Terminal area
                VStack(spacing: 0) {
                    // Output area
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 1) {
                                ForEach(outputLines) { line in
                                    Text(line.text)
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundStyle(line.isError ? Theme.crimson : Theme.green.opacity(0.9))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(line.id)
                                }
                            }
                            .padding(12)
                        }
                        .onChange(of: outputLines.count) { _, _ in
                            if let lastLine = outputLines.last {
                                withAnimation {
                                    proxy.scrollTo(lastLine.id, anchor: .bottom)
                                }
                            }
                        }
                    }

                    ThemedDivider()

                    // Input area
                    HStack(spacing: 8) {
                        Text(">")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.green)

                        ShellTextField(
                            text: $currentInput,
                            onSubmit: { sendCommand() },
                            onUpArrow: { navigateHistoryUp() },
                            onDownArrow: { navigateHistoryDown() }
                        )
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white)
                        .disabled(!isRunning)

                        Button {
                            sendCommand()
                        } label: {
                            Image(systemName: "return")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isRunning || currentInput.isEmpty)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.surface.opacity(0.6))
                }
                .background(Color(red: 0.02, green: 0.05, blue: 0.08))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.midnight)
        .onDisappear {
            stopShell()
        }
    }

    // MARK: - mongosh Not Found View

    private var mongoshNotFoundView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Theme.amber)

            Text("mongosh not found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 8) {
                Text("The MongoDB Shell (mongosh) is required but was not found on your system.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)

                ThemedDivider()

                Text("Install using Homebrew:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)

                Text("brew install mongosh")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.green)
                    .padding(10)
                    .background(Theme.midnight)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.border, lineWidth: 1)
                    )

                Text("Or download from: https://www.mongodb.com/try/download/shell")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.skyBlue)
            }
            .frame(maxWidth: 450)

            Button {
                mongoshNotFound = false
                startShell()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
            }
            .buttonStyle(.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Shell Process Management

    private func findMongosh() -> String? {
        let searchPaths = [
            "/usr/local/bin/mongosh",
            "/opt/homebrew/bin/mongosh",
            "/usr/bin/mongosh",
            "/opt/local/bin/mongosh"
        ]

        // Try which first
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
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                    return path
                }
            }
        } catch { }

        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func startShell() {
        guard let mongoshPath = findMongosh() else {
            mongoshNotFound = true
            return
        }

        mongoshNotFound = false

        let uri = viewModel.connectionURI.isEmpty ? "mongodb://localhost:27017" : viewModel.connectionURI

        outputLines.append(ShellOutputLine(
            text: "Connecting to \(uri)...",
            isError: false
        ))

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: mongoshPath)
        process.arguments = [uri, "--quiet"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        // Read stdout asynchronously
        stdout.fileHandleForReading.readabilityHandler = { [self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let str = String(data: data, encoding: .utf8) {
                let lines = str.components(separatedBy: "\n")
                DispatchQueue.main.async {
                    for line in lines where !line.isEmpty {
                        self.outputLines.append(ShellOutputLine(text: line, isError: false))
                    }
                }
            }
        }

        // Read stderr asynchronously
        stderr.fileHandleForReading.readabilityHandler = { [self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let str = String(data: data, encoding: .utf8) {
                let lines = str.components(separatedBy: "\n")
                DispatchQueue.main.async {
                    for line in lines where !line.isEmpty {
                        self.outputLines.append(ShellOutputLine(text: line, isError: true))
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
                text: "Connected. Type MongoDB commands below.",
                isError: false
            ))

            // Monitor process termination
            process.terminationHandler = { [self] _ in
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.outputLines.append(ShellOutputLine(
                        text: "Shell session ended.",
                        isError: false
                    ))
                }
            }
        } catch {
            outputLines.append(ShellOutputLine(
                text: "Error starting mongosh: \(error.localizedDescription)",
                isError: true
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
        guard isRunning, let stdin = stdinPipe, !currentInput.isEmpty else { return }

        let command = currentInput

        // Add to history
        commandHistory.append(command)
        historyIndex = commandHistory.count

        // Display input in output
        outputLines.append(ShellOutputLine(text: "> \(command)", isError: false))

        // Write to stdin
        let commandData = (command + "\n").data(using: .utf8)!
        stdin.fileHandleForWriting.write(commandData)

        currentInput = ""
    }

    private func navigateHistoryUp() {
        guard !commandHistory.isEmpty else { return }
        if historyIndex > 0 {
            historyIndex -= 1
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

// MARK: - Shell TextField (with arrow key support)

struct ShellTextField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onUpArrow: () -> Void
    var onDownArrow: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = ShellNSTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.drawsBackground = false
        textField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textField.textColor = NSColor.white
        textField.focusRingType = .none
        textField.placeholderString = "Type a command..."
        textField.placeholderAttributedString = NSAttributedString(
            string: "Type a command...",
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.3),
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            ]
        )
        textField.onUpArrow = onUpArrow
        textField.onDownArrow = onDownArrow
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if let shellField = nsView as? ShellNSTextField {
            shellField.onUpArrow = onUpArrow
            shellField.onDownArrow = onDownArrow
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: ShellTextField

        init(_ parent: ShellTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

// MARK: - Custom NSTextField for Arrow Keys

class ShellNSTextField: NSTextField {
    var onUpArrow: (() -> Void)?
    var onDownArrow: (() -> Void)?

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 126 { // Up arrow
            onUpArrow?()
        } else if event.keyCode == 125 { // Down arrow
            onDownArrow?()
        } else {
            super.keyUp(with: event)
        }
    }
}
