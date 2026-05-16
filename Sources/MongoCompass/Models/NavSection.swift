import SwiftUI

enum NavSection: String, CaseIterable, Identifiable {
    case explorer = "Explorer"
    case aggregation = "Aggregations"
    case schema = "Schema"
    case investigate = "Investigate"
    case metrics = "Metrics"
    case shell = "Shell"
    case dumpRestore = "Dump / Restore"
    case queryLog = "Query Log"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .explorer: return "doc.text.magnifyingglass"
        case .queryLog: return "clock.arrow.circlepath"
        case .aggregation: return "line.3.horizontal.decrease.circle"
        case .investigate: return "magnifyingglass.circle"
        case .metrics: return "chart.bar"
        case .dumpRestore: return "externaldrive"
        case .schema: return "list.bullet.indent"
        case .shell: return "terminal"
        }
    }
}
