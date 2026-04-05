import SwiftUI

enum NavSection: String, CaseIterable, Identifiable {
    case explorer = "Explorer"
    case queryLog = "Query Log"
    case aggregation = "Aggregation"
    case investigate = "Investigate"
    case metrics = "Metrics"
    case dumpRestore = "Dump & Restore"
    case schema = "Schema"
    case shell = "Shell"

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
