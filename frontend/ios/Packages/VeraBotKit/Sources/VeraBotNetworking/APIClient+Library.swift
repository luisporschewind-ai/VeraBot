import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import VeraBotCore

extension APIClient: LibraryAPI {
    /// Preview bytes use the library lifetime and the same authenticated/refreshing transport as REST.
    public func libraryThumbnail(id: String) async throws -> Data {
        let path = "/api/library/items/\(id)/thumb"
        let (data, status) = try await send(path) { token in
            var request = makeRequest(path, method: "GET", body: nil, token: token)
            request.timeoutInterval = 30
            return request
        }
        guard status == 200 else { throw Self.apiError(status: status, data: data) }
        return data
    }

    public func libraryPage(cursor: String?) async throws -> LibraryPage {
        try await call("/api/library/items", query: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [])
    }
    public func librarySearch(query: String, botID: Int?) async throws -> [LibraryItem] {
        var params = [URLQueryItem(name: "q", value: query)]
        if let botID { params.append(.init(name: "bot_id", value: String(botID))) }
        var items: [LibraryItem] = []; var cursor: String?
        repeat {
            let page: LibraryPage = try await call("/api/library/items", query: params + (cursor.map { [.init(name: "cursor", value: $0)] } ?? []))
            items += page.items; cursor = page.nextCursor
        } while cursor != nil
        return items
    }
    public func libraryItem(id: String) async throws -> LibraryItem { try await call("/api/library/items/\(id)") }
    public func libraryLink(id: String, botID: Int) async throws {
        let _: OKResponse = try await call("/api/library/items/\(id)/bots/\(botID)", method: "PUT")
    }
    public func libraryUnlink(id: String, botID: Int) async throws {
        let _: OKResponse = try await call("/api/library/items/\(id)/bots/\(botID)", method: "DELETE")
    }
    public func libraryDelete(id: String) async throws { let _: OKResponse = try await call("/api/library/items/\(id)", method: "DELETE") }
    public func libraryUpload(data: Data, filename: String, mime: String, botID: Int?, requestKey: String) async throws -> LibraryItem {
        let path = "/api/library/items", boundary = UUID().uuidString
        var payload = Data()
        func append(_ text: String) { payload.append(Data(text.utf8)) }
        if let botID { append("--\(boundary)\r\nContent-Disposition: form-data; name=\"bot_id\"\r\n\r\n\(botID)\r\n") }
        let safeName = filename.replacingOccurrences(of: "\"", with: "_").replacingOccurrences(of: "\r", with: "_").replacingOccurrences(of: "\n", with: "_")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: \(mime)\r\n\r\n")
        payload.append(data); append("\r\n--\(boundary)--\r\n")
        let bytes = payload
        let (result,status) = try await send(path) { token in
            var req = makeRequest(path, method: "POST", body: bytes, token: token, headers: ["Idempotency-Key":requestKey])
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval=90;return req
        }
        guard (200..<300).contains(status) else { throw Self.apiError(status: status, data: result) }
        return try JSONDecoder().decode(LibraryItem.self, from: result)
    }
}
