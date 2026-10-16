import Foundation
import SwiftData

/// Uma página visitada. Há um registro por endereço e perfil; novas visitas atualizam a
/// data e a contagem, que ajudam a ordenar as sugestões da barra de endereço.
@Model
final class HistoryEntry {
    var profileID: UUID
    var urlString: String
    var title: String
    var lastVisited: Date
    var visitCount: Int

    init(profileID: UUID, urlString: String, title: String, lastVisited: Date, visitCount: Int = 1) {
        self.profileID = profileID
        self.urlString = urlString
        self.title = title
        self.lastVisited = lastVisited
        self.visitCount = visitCount
    }

    var url: URL? { URL(string: urlString) }

    var displayTitle: String {
        title.isEmpty ? (url?.host() ?? urlString) : title
    }
}

/// Períodos para limpar o histórico e os dados de sites.
enum ClearPeriod: String, CaseIterable, Identifiable, Sendable {
    case lastHour, today, todayAndYesterday, allTime

    var id: String { rawValue }

    /// Início do período; `nil` significa desde sempre.
    func startDate(now: Date = .now, calendar: Calendar = .current) -> Date? {
        switch self {
        case .lastHour: now.addingTimeInterval(-3600)
        case .today: calendar.startOfDay(for: now)
        case .todayAndYesterday: calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        case .allTime: nil
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .lastHour: "Last Hour"
        case .today: "Today"
        case .todayAndYesterday: "Today and Yesterday"
        case .allTime: "All History"
        }
    }
}
