import Foundation
import VeraBotCore

extension APIClient {
    public func notificationEvents(after: Int? = nil, through: Int? = nil) async throws -> NotificationEventPage {
        var query: [URLQueryItem] = []
        if let after { query.append(URLQueryItem(name: "after", value: String(after))) }
        if let through { query.append(URLQueryItem(name: "through", value: String(through))) }
        return try await call("/api/notification-events", query: query)
    }
}
