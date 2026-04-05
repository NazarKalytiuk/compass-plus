import Foundation

// MARK: - DumpRestoreService

final class DumpRestoreService {

    // MARK: - Tool Discovery

    /// Common locations to search for MongoDB tools on macOS.
    private static let searchPaths: [String] = [
        "/usr/local/bin",
        "/opt/homebrew/bin",
        "/usr/bin",
        "/opt/local/bin",
        "/usr/local/opt/mongodb-community/bin",
        "/opt/homebrew/opt/mongodb-community/bin",
        "/usr/local/opt/mongodb-database-tools/bin",
        "/opt/homebrew/opt/mongodb-database-tools/bin"
    ]

    /// Find a tool by name, searching PATH and common install locations.
    func findTool(_ name: String) -> String? {
        // First check system PATH using `which`
        let whichProcess = Process()
        let pipe = Pipe()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = [name]
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
        } catch {
            // Fall through to manual search
        }

        // Search common locations
        for dir in Self.searchPaths {
            let path = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    /// Whether `mongodump` is available on this system.
    var isDumpAvailable: Bool {
        findTool("mongodump") != nil
    }

    /// Whether `mongorestore` is available on this system.
    var isRestoreAvailable: Bool {
        findTool("mongorestore") != nil
    }

    // MARK: - Dump

    /// Run `mongodump` and stream output lines.
    func dump(
        uri: String,
        database: String,
        collection: String? = nil,
        outputPath: String,
        gzip: Bool = false
    ) -> AsyncStream<String> {
        guard let toolPath = findTool("mongodump") else {
            return AsyncStream { continuation in
                continuation.yield("Error: mongodump not found. Install MongoDB Database Tools.")
                continuation.finish()
            }
        }

        var arguments: [String] = [
            "--uri", uri,
            "--db", database,
            "--out", outputPath
        ]

        if let collection = collection, !collection.isEmpty {
            arguments.append(contentsOf: ["--collection", collection])
        }

        if gzip {
            arguments.append("--gzip")
        }

        return runProcess(executablePath: toolPath, arguments: arguments)
    }

    // MARK: - Restore

    /// Run `mongorestore` and stream output lines.
    func restore(
        uri: String,
        inputPath: String,
        database: String? = nil,
        drop: Bool = false
    ) -> AsyncStream<String> {
        guard let toolPath = findTool("mongorestore") else {
            return AsyncStream { continuation in
                continuation.yield("Error: mongorestore not found. Install MongoDB Database Tools.")
                continuation.finish()
            }
        }

        var arguments: [String] = [
            "--uri", uri,
            inputPath
        ]

        if let database = database, !database.isEmpty {
            arguments.insert(contentsOf: ["--db", database], at: arguments.count - 1)
        }

        if drop {
            arguments.insert("--drop", at: arguments.count - 1)
        }

        return runProcess(executablePath: toolPath, arguments: arguments)
    }

    // MARK: - Process Execution

    /// Run a process and return an AsyncStream of its combined stdout + stderr output lines.
    private func runProcess(executablePath: String, arguments: [String]) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task.detached {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                // Buffer to accumulate partial lines
                let outputQueue = DispatchQueue(label: "com.mongocompass.dumpRestore.output")

                // Read handler for pipes
                func readLines(from fileHandle: FileHandle) {
                    var buffer = ""
                    fileHandle.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty else {
                            // EOF
                            outputQueue.sync {
                                if !buffer.isEmpty {
                                    continuation.yield(buffer)
                                    buffer = ""
                                }
                            }
                            fileHandle.readabilityHandler = nil
                            return
                        }
                        if let str = String(data: data, encoding: .utf8) {
                            outputQueue.sync {
                                buffer += str
                                while let newlineRange = buffer.range(of: "\n") {
                                    let line = String(buffer[buffer.startIndex..<newlineRange.lowerBound])
                                    buffer = String(buffer[newlineRange.upperBound...])
                                    continuation.yield(line)
                                }
                            }
                        }
                    }
                }

                readLines(from: stdoutPipe.fileHandleForReading)
                readLines(from: stderrPipe.fileHandleForReading)

                do {
                    try process.run()
                    process.waitUntilExit()

                    // Drain remaining data
                    let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    if let str = String(data: remainingStdout, encoding: .utf8), !str.isEmpty {
                        let lines = str.components(separatedBy: "\n")
                        for line in lines where !line.isEmpty {
                            continuation.yield(line)
                        }
                    }
                    if let str = String(data: remainingStderr, encoding: .utf8), !str.isEmpty {
                        let lines = str.components(separatedBy: "\n")
                        for line in lines where !line.isEmpty {
                            continuation.yield(line)
                        }
                    }

                    let status = process.terminationStatus
                    if status == 0 {
                        continuation.yield("Process completed successfully (exit code 0).")
                    } else {
                        continuation.yield("Process exited with code \(status).")
                    }
                } catch {
                    continuation.yield("Error launching process: \(error.localizedDescription)")
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
