import Foundation

/// Captured per-phase outcome of a connection diagnose pass. Each phase is
/// independently `nil` when not attempted (e.g. TLS skipped on a plaintext
/// URI). All non-nil phases include a status and, where meaningful, timing.
struct ConnectionDiagnostics {
    struct Phase {
        var ok: Bool
        var detail: String           // user-visible value (e.g. "resolved · 18 ms")
        var error: String?           // populated when ok == false
    }

    var host: String = ""
    var port: Int = 27017
    var tlsEnabled: Bool = false

    var dns: Phase?                  // nil if hostname parse failed
    var tls: Phase?                  // nil for plaintext URIs
    var auth: Phase?                 // nil when DNS/TLS short-circuited
}
