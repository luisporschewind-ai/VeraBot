// 图片附件（Attachments P1，后端 schema v12）：上传 / 下载 / 删除。
// 路径与字段见 backend/verabot/api/routers/attachments.py；契约测试 ATT-CONTRACT 会检查这里的路径和上传字段名。
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import VeraBotCore

extension APIClient {
    /// multipart 上传，字段 file（可选 bot_id）。返回 201 + Attachment（status = pending）。
    public func uploadAttachment(data: Data, mime: String, botID: Int?) async throws -> Attachment {
        let path = "/api/attachments"
        let boundary = "VeraBotBoundary-\(UUID().uuidString)"
        let ext = mime == "image/gif" ? "gif" : (mime == "image/png" ? "png" : "jpg")
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        if let botID {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"bot_id\"\r\n\r\n")
            append("\(botID)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"image.\(ext)\"\r\n")
        append("Content-Type: \(mime)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        let payload = body
        let (result, status) = try await send(path) { token in
            var req = URLRequest(url: baseURL.appending(path: path))
            req.httpMethod = "POST"
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            req.httpBody = payload
            req.timeoutInterval = 90
            return req
        }
        guard (200..<300).contains(status) else { throw Self.apiError(status: status, data: result) }
        return try JSONDecoder().decode(Attachment.self, from: result)
    }

    public func attachmentContent(id: String) async throws -> Data {
        try await attachmentBytes("/api/attachments/\(id)/content")
    }

    public func attachmentThumb(id: String) async throws -> Data {
        try await attachmentBytes("/api/attachments/\(id)/thumb")
    }

    /// 只能删未发送（pending）的；已发送的图随消息删除（清空对话 / 删除 Bot）。
    public func deleteAttachment(id: String) async throws -> OKResponse {
        try await call("/api/attachments/\(id)", method: "DELETE")
    }

    private func attachmentBytes(_ path: String) async throws -> Data {
        let (data, status) = try await send(path) { token in
            var req = URLRequest(url: baseURL.appending(path: path))
            req.httpMethod = "GET"
            req.cachePolicy = .reloadIgnoringLocalCacheData
            if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            req.timeoutInterval = 60
            return req
        }
        guard (200..<300).contains(status) else { throw Self.apiError(status: status, data: data) }
        return data
    }
}
