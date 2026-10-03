import Foundation
import Testing
@testable import VeraBotCore

@Test func attachmentDecodesBackendJSON() throws {
    let json = #"{"id":"att_abc","kind":"image","mime":"image/gif","width":40,"height":30,"bytes":1234,"status":"pending","expires_at":"2026-10-04T12:00:00+00:00"}"#
    let a = try JSONDecoder().decode(Attachment.self, from: Data(json.utf8))
    #expect(a.id == "att_abc" && a.isGIF && a.status == "pending")
    #expect(a.expiresAt == "2026-10-04T12:00:00+00:00")
    #expect(abs(a.aspectRatio - 0.75) < 0.0001)
}

@Test func chatMessageWithoutAttachmentsKeyDecodesAsEmpty() throws {
    let old = #"{"id":1,"role":"user","content":"hi","traces":[],"created_at":"2026-10-03"}"#
    let m = try JSONDecoder().decode(ChatMessage.self, from: Data(old.utf8))
    #expect(m.attachments.isEmpty)
    let new = #"{"id":2,"role":"user","content":"","traces":[],"attachments":[{"id":"att_x","kind":"image","mime":"image/jpeg","width":10,"height":20,"bytes":5,"status":"attached","expires_at":null}]}"#
    let m2 = try JSONDecoder().decode(ChatMessage.self, from: Data(new.utf8))
    #expect(m2.attachments.map(\.id) == ["att_x"] && m2.attachments[0].expiresAt == nil)
}

@Test func chatRequestEncodesAttachmentIDs() throws {
    let data = try JSONEncoder().encode(ChatRequest(message: "", attachmentIDs: ["att_1"]))
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(obj?["message"] as? String == "")
    #expect(obj?["attachment_ids"] as? [String] == ["att_1"])
}

@Test func gifSniffing() {
    #expect(AttachmentLimits.isGIF(Data("GIF89a....".utf8)))
    #expect(!AttachmentLimits.isGIF(Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0])))
}

@Test func previewFileExtension() {
    #expect(AttachmentLimits.fileExtension(for: Data("GIF89a....".utf8)) == "gif")
    #expect(AttachmentLimits.fileExtension(for: Data("GIF87a....".utf8)) == "gif")
    #expect(AttachmentLimits.fileExtension(for: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0])) == "png")
    #expect(AttachmentLimits.fileExtension(for: Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0])) == "jpg")
    #expect(AttachmentLimits.fileExtension(for: Data()) == "jpg")
}
