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

extension APIClient {
    public func localNotificationState(ids: [Int]) async throws -> [InboxNotification] {
        struct Body: Encodable { let ids: [Int] }
        struct Response: Decodable { let notifications: [InboxNotification] }
        let result: Response = try await call("/api/notifications/local-state", method: "POST", body: encode(Body(ids: ids)))
        return result.notifications
    }
}
public extension VeraBotAPI {
    func localNotificationState(ids: [Int]) async throws -> [InboxNotification] {
        throw APIError(status: 501, message: "通知同步暂不可用")
    }
}
