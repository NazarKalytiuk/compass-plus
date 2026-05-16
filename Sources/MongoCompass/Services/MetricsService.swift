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
            var status = try await service.getServerStatus()
            // Replica-set lag — tolerated to be nil on standalones.
            status.replLagMs = try? await service.getReplicationLagMs()
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

                // CPU% — sum of user + system μs delta over wall-clock μs.
                // Can exceed 100% on multi-core. nil if extra_info missing.
                let cpuPercent: Double? = {
                    guard status.hasProcessStats && prev.hasProcessStats else { return nil }
                    let deltaUser = status.cpuUserTimeUs - prev.cpuUserTimeUs
                    let deltaSystem = status.cpuSystemTimeUs - prev.cpuSystemTimeUs
                    let deltaCpuUs = Double(deltaUser + deltaSystem)
                    let elapsedUs = elapsed * 1_000_000.0
                    guard elapsedUs > 0 else { return nil }
                    return Swift.max(0, deltaCpuUs / elapsedUs * 100.0)
                }()

                // Cache hit ratio — pages requested - pages read from disk,
                // divided by pages requested. nil when WT cache absent or
                // there were no cache requests in the window.
                let cacheHitRatio: Double? = {
                    guard status.hasCacheStats && prev.hasCacheStats else { return nil }
                    let deltaRequested = status.cachePagesRequestedFromCache - prev.cachePagesRequestedFromCache
                    let deltaReadIntoCache = status.cachePagesReadIntoCache - prev.cachePagesReadIntoCache
                    guard deltaRequested > 0 else { return nil }
                    let hits = Double(deltaRequested - deltaReadIntoCache)
                    return Swift.max(0, Swift.min(1, hits / Double(deltaRequested)))
                }()

                let diskReadPerSec: Double? = {
                    guard status.hasDiskStats && prev.hasDiskStats else { return nil }
                    let delta = status.diskBytesRead - prev.diskBytesRead
                    return Swift.max(0, Double(delta) / elapsed)
                }()
                let diskWritePerSec: Double? = {
                    guard status.hasDiskStats && prev.hasDiskStats else { return nil }
                    let delta = status.diskBytesWritten - prev.diskBytesWritten
                    return Swift.max(0, Double(delta) / elapsed)
                }()

                let pageFaultsPerSec: Double? = {
                    guard status.hasProcessStats && prev.hasProcessStats else { return nil }
                    let delta = status.pageFaults - prev.pageFaults
                    return Swift.max(0, Double(delta) / elapsed)
                }()

                let wtCacheMB: Double? = status.hasCacheStats
                    ? Double(status.cacheBytesUsed) / (1024 * 1024)
                    : nil

                let snapshot = MetricsSnapshot(
                    timestamp: now,
                    opsPerSec: Swift.max(0, opsPerSec),
                    memoryMB: Double(status.memoryResident),
                    networkInPerSec: Swift.max(0, networkInPerSec),
                    networkOutPerSec: Swift.max(0, networkOutPerSec),
                    cpuPercent: cpuPercent,
                    cacheHitRatio: cacheHitRatio,
                    diskReadPerSec: diskReadPerSec,
                    diskWritePerSec: diskWritePerSec,
                    pageFaultsPerSec: pageFaultsPerSec,
                    replLagMs: status.replLagMs.map(Double.init),
                    wtCacheMB: wtCacheMB
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
