import Foundation

@Observable
final class MetricsService: @unchecked Sendable {

    // MARK: - Published State

    var currentMetrics: ServerMetrics?
    var history: [MetricsSnapshot] = []
    var currentOps: [CurrentOp] = []

    // MARK: - Internal State

    private weak var mongoService: MongoService?
    private var pollingTask: Task<Void, Never>?
    private var previousStatus: ServerMetrics?
    private var previousTimestamp: Date?
    private let maxHistoryPoints = 60
    private let pollingInterval: TimeInterval = 5.0

    // MARK: - Init

    init(mongoService: MongoService) {
        self.mongoService = mongoService
    }

    deinit {
        stop()
    }

    // MARK: - Start / Stop

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.poll()
                do {
                    try await Task.sleep(nanoseconds: UInt64(self.pollingInterval * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        previousStatus = nil
        previousTimestamp = nil
    }

    // MARK: - Polling

    private func poll() async {
        guard let service = mongoService, service.isConnected else { return }

        do {
            let status = try await service.getServerStatus()
            let now = Date()

            // Detect server restart (uptime regression)
            if let prev = previousStatus, status.uptime < prev.uptime {
                previousStatus = nil
                previousTimestamp = nil
                history.removeAll()
            }

            // Calculate deltas if we have a previous sample
            if let prev = previousStatus, let prevTime = previousTimestamp {
                let elapsed = now.timeIntervalSince(prevTime)
                guard elapsed > 0 else { return }

                let totalOpsPrev = prev.opcounters.values.reduce(0, +)
                let totalOpsCurr = status.opcounters.values.reduce(0, +)
                let opsPerSec = Double(totalOpsCurr - totalOpsPrev) / elapsed

                let networkInPerSec = Double(status.networkBytesIn - prev.networkBytesIn) / elapsed
                let networkOutPerSec = Double(status.networkBytesOut - prev.networkBytesOut) / elapsed

                let snapshot = MetricsSnapshot(
                    timestamp: now,
                    opsPerSec: Swift.max(0, opsPerSec),
                    memoryMB: Double(status.memoryResident),
                    networkInPerSec: Swift.max(0, networkInPerSec),
                    networkOutPerSec: Swift.max(0, networkOutPerSec)
                )

                history.append(snapshot)
                if history.count > maxHistoryPoints {
                    history.removeFirst(history.count - maxHistoryPoints)
                }
            }

            previousStatus = status
            previousTimestamp = now
            currentMetrics = status

            // Also fetch current ops
            let ops = try await service.getCurrentOps()
            currentOps = ops

        } catch {
            // Silently continue polling; connection may have been lost temporarily.
        }
    }
}
