import Foundation

/// Only transport failures and HTTP 5xx belong on the connection fallback.
/// Account/validation errors stay with their form; cancellation stays silent.
public enum ConnectionIssue: String, Equatable, Sendable {
    case offline, timedOut, unreachable, serviceUnavailable

    public static func classify(_ error: Error) -> Self? {
        if let error = error as? APIError {
            return (500...599).contains(error.status) ? .serviceUnavailable : nil
        }
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return nil }
        switch URLError.Code(rawValue: error.code) {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff: return .offline
        case .timedOut: return .timedOut
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .secureConnectionFailed, .serverCertificateUntrusted,
             .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid: return .unreachable
        default: return nil
        }
    }

    public var title: String {
        switch self {
        case .offline: "网络暂时断开了"
        case .timedOut: "连接有点慢"
        case .unreachable: "暂时连接不上"
        case .serviceUnavailable: "服务暂时不可用"
        }
    }

    public var message: String {
        switch self {
        case .offline: "我在这里。检查一下 Wi-Fi 或蜂窝网络，再试一次吧。"
        case .timedOut: "这次等得有点久。网络恢复后，我们再试一次。"
        case .unreachable: "我还没能连上服务。稍等一会儿，再试一次吧。"
        case .serviceUnavailable: "服务暂时没能回应。我陪你等一会儿。"
        }
    }
}
