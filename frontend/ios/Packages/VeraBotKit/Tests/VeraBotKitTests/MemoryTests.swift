import Foundation
import Testing
@testable import VeraBotCore
@testable import VeraBotNetworking

// MEM-UI-01：记忆模型与后端 JSON（docs/design/MEMORY_GROWTH.md §5.5）一一对应。

private let memoryJSON = ##"""
{"id":41,"scope":"global","bot_id":null,"bot_name":null,"type":"profile","content":"用户希望被称呼为「小林」",
 "sensitivity":"normal","sensitive":false,"source":"explicit_chat","source_bot_id":7,"source_bot_name":"Vera",
 "status":"active","action":"create","target_id":null,"target_content":null,"confidence":1.0,"use_count":3,
 "last_used_at":"2026-10-02T01:20:00+00:00","confirmed_at":"2026-10-01T08:00:00+00:00","expires_at":null,
 "created_at":"2026-10-01T07:59:30+00:00","updated_at":"2026-10-01T08:00:00+00:00"}
"""##

@Test func decodesMemory() throws {
    let m = try JSONDecoder().decode(Memory.self, from: Data(memoryJSON.utf8))
    #expect(m.id == 41)
    #expect(m.scope == .global)
    #expect(m.type == .profile)
    #expect(m.status == .active)
    #expect(m.botId == nil)
    #expect(m.sourceBotName == "Vera")
    #expect(m.useCount == 3)
    #expect(m.sourceTitle == "来自与 Vera 的对话")
    #expect(m.sensitive == false)
    #expect(m.evidence.isEmpty)
    #expect(m.reason == nil)
}

@Test func decodesImplicitCandidateEvidenceAndSuggestions() throws {
    let candidateJSON = ##"{"id":42,"scope":"bot","bot_id":7,"type":"routine","content":"每周徒步","source":"implicit_extraction","status":"candidate","evidence":[{"message_id":31,"date":"2026-10-01","role":"user"}],"reason":"重复提到"}"##
    let candidate = try JSONDecoder().decode(Memory.self, from: Data(candidateJSON.utf8))
    #expect(candidate.evidence.count == 1)
    #expect(candidate.evidence[0].messageID == 31)
    #expect(candidate.reason == "重复提到")

    let suggestionJSON = ##"{"suggestions":[{"id":9,"kind":"routine_reminder","title":"周末徒步","created_at":"2026-10-07","expires_at":"2026-11-06"}]}"##
    let response = try JSONDecoder().decode(MemorySuggestionsResponse.self, from: Data(suggestionJSON.utf8))
    #expect(response.suggestions.first?.id == 9)
    #expect(response.suggestions.first?.kind == .routineReminder)
    #expect(response.suggestions.first?.title == "周末徒步")
}

@Test func oldSuggestionAndQuickPromptResponsesDefaultSafely() throws {
    let suggestions = try JSONDecoder().decode(MemorySuggestionsResponse.self, from: Data("{}".utf8))
    let prompts = try JSONDecoder().decode(QuickPromptsResponse.self, from: Data("{}".utf8))
    #expect(suggestions.suggestions.isEmpty)
    #expect(prompts.prompts.isEmpty)
}

@Test func quickPromptSettingDefaultsOnAndPersistsPerKey() throws {
    let suite = "VeraBotKitTests.quickPrompts.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(defaults.object(forKey: SettingsKeys.quickPromptsEnabled) == nil)
    #expect((defaults.object(forKey: SettingsKeys.quickPromptsEnabled) as? Bool) ?? SettingsKeys.quickPromptsEnabledDefault)
    defaults.set(false, forKey: SettingsKeys.quickPromptsEnabled)
    #expect(defaults.bool(forKey: SettingsKeys.quickPromptsEnabled) == false)
}

@Test func quickPromptResponseIsBoundedToSix() throws {
    let prompts = (1...8).map { "提问\($0)" }
    let data = try JSONSerialization.data(withJSONObject: ["prompts": prompts])
    #expect(try JSONDecoder().decode(QuickPromptsResponse.self, from: data).prompts.count == 6)
}

@Test func unknownMemoryEnumsDecodeAsUnknown() throws {
    let json = ##"{"id":1,"scope":"team","type":"mood","content":"x","status":"archived","action":"merge","sensitivity":"religion"}"##
    let m = try JSONDecoder().decode(Memory.self, from: Data(json.utf8))
    #expect(m.scope == .unknown)
    #expect(m.type == .unknown)
    #expect(m.status == .unknown)
    #expect(m.action == .unknown)
    #expect(m.sensitivity == .unknown)
}

@Test func decodesSensitiveMemory() throws {
    let json = ##"{"id":2,"scope":"global","type":"fact","content":"用户对青霉素过敏","sensitivity":"health","sensitive":true,"status":"active","source":"memory_page"}"##
    let m = try JSONDecoder().decode(Memory.self, from: Data(json.utf8))
    #expect(m.sensitive)
    #expect(m.sensitivity.title == "健康信息")
    #expect(m.sourceTitle == "你手动添加")
    #expect(m.detailLine().hasPrefix("事实 · 健康信息 · 你手动添加"))
}

@Test func decodesMemoriesResponse() throws {
    let json = ##"{"memories":[\##(memoryJSON)],"counts":{"active":23,"proposed":1,"candidate":0,"global":14,"by_bot":{"7":9}},"limits":{"max_active":200,"max_chars":200}}"##
    let r = try JSONDecoder().decode(MemoriesResponse.self, from: Data(json.utf8))
    #expect(r.memories.count == 1)
    #expect(r.counts?.active == 23)
    #expect(r.counts?.byBot["7"] == 9)
    #expect(r.limits?.maxChars == 200)
}

@Test func confirmResultDecodesBothShapes() throws {
    let a = try JSONDecoder().decode(MemoryConfirmResult.self, from: Data(memoryJSON.utf8))
    let b = try JSONDecoder().decode(MemoryConfirmResult.self, from: Data(#"{"ok":true,"deleted_id":12}"#.utf8))
    if case .memory(let m) = a { #expect(m.id == 41) } else { Issue.record("expected memory") }
    if case .deleted(let id) = b { #expect(id == 12) } else { Issue.record("expected deleted") }
}

@Test func oldBotJSONDefaultsToBotAndGlobal() throws {
    let json = ##"{"id":7,"name":"Vera","avatar":"🐼","color":"#0F766E"}"##
    let bot = try JSONDecoder().decode(Bot.self, from: Data(json.utf8))
    #expect(bot.memoryAccess == .botAndGlobal)
    #expect(bot.memoryCount == nil)
    let v4 = ##"{"id":7,"name":"Vera","avatar":"🐼","color":"#0F766E","memory_access":"bot","memory_count":4}"##
    let b2 = try JSONDecoder().decode(Bot.self, from: Data(v4.utf8))
    #expect(b2.memoryAccess == .bot)
    #expect(b2.memoryCount == 4)
}

@Test func botPatchEncodesMemoryAccess() throws {
    let data = try JSONEncoder().encode(BotPatch(memoryAccess: .botAndGlobal))
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(obj?["memory_access"] as? String == "bot_and_global")
    #expect(obj?.keys.count == 1)
}

@Test func memoryCreateAndPatchEncodeSnakeCase() throws {
    let c = try JSONSerialization.jsonObject(with: JSONEncoder().encode(MemoryCreate(content: "x", type: .fact, scope: .bot, botId: 7))) as? [String: Any]
    #expect(c?["bot_id"] as? Int == 7)
    #expect(c?["scope"] as? String == "bot")
    #expect(c?["type"] as? String == "fact")
    let p = try JSONSerialization.jsonObject(with: JSONEncoder().encode(MemoryPatch(content: "y"))) as? [String: Any]
    #expect(p?.keys.sorted() == ["content"])
}

@Test func memoryQueryItems() {
    let q = MemoryQuery(statuses: [.proposed, .active], ids: [3, 4], visibleTo: 7)
    let items = Dictionary(uniqueKeysWithValues: q.queryItems.map { ($0.name, $0.value ?? "") })
    #expect(items["status"] == "proposed,active")
    #expect(items["ids"] == "3,4")
    #expect(items["visible_to"] == "7")
    #expect(items["scope"] == nil)
}

@Test func decodesMessageFeedbackOnChatMessage() throws {
    let json = #"{"id":3,"role":"assistant","content":"好","traces":[],"created_at":"2026-10-05","feedback":{"rating":-1,"reason":"too_long"}}"#
    let m = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
    #expect(m.feedback?.rating == -1)
    #expect(m.feedback?.reason == "too_long")
    let old = #"{"id":1,"role":"user","content":"hi","traces":[]}"#
    let legacy = try JSONDecoder().decode(ChatMessage.self, from: Data(old.utf8))
    #expect(legacy.feedback == nil)
    let body = try JSONDecoder().decode(MessageFeedbackResponse.self, from: Data(
        #"{"ok":true,"feedback":{"rating":-1,"reason":"too_long"},"style_trace":null}"#.utf8))
    #expect(body.ok && body.feedback?.reason == "too_long" && body.styleTrace == nil)
}

@Test func parsesMemoryProposalFromTrace() throws {
    let json = ##"{"id":"c1","name":"remember","args":{"content":"用户不吃香菜","type":"preference","scope":"global"},"result":{"memory_id":41,"status":"proposed","action":"create","content":"用户不吃香菜","type":"preference","scope":"global","sensitive":false,"expires_at":"2026-10-08T00:00:00+00:00","note":"…"}}"##
    let t = try JSONDecoder().decode(ToolTrace.self, from: Data(json.utf8))
    let p = try #require(t.memoryProposal)
    #expect(p.isCard)
    #expect(p.memoryID == 41)
    #expect(p.type == .preference)
    #expect(p.scope == .global)
    #expect(p.action == .create)
}

@Test func parsesNonCardMemoryResults() throws {
    let known = ##"{"id":"c2","name":"remember","args":{},"result":{"status":"already_known","memory_id":41}}"##
    let blocked = ##"{"id":"c3","name":"remember","args":{"content":"（已隐藏）"},"result":{"error":"密码、验证码、密钥、证件号、卡号等信息不会被记住","code":"sensitive_credential"}}"##
    let forget = ##"{"id":"c4","name":"forget_memory","args":{"memory_id":41},"result":{"memory_id":50,"status":"proposed","action":"delete","content":"","type":"preference","scope":"global","target_id":41,"target_content":"用户不吃香菜"}}"##
    let weather = ##"{"id":"c5","name":"get_weather","args":{},"result":{"ok":true}}"##
    let d = JSONDecoder()
    let k = try #require(try d.decode(ToolTrace.self, from: Data(known.utf8)).memoryProposal)
    #expect(!k.isCard)
    #expect(k.summary == "已在记忆中")
    let b = try #require(try d.decode(ToolTrace.self, from: Data(blocked.utf8)).memoryProposal)
    #expect(b.errorCode == "sensitive_credential")
    #expect(!b.isCard)
    let f = try #require(try d.decode(ToolTrace.self, from: Data(forget.utf8)).memoryProposal)
    #expect(f.isCard && f.action == .delete && f.targetContent == "用户不吃香菜")
    #expect(try d.decode(ToolTrace.self, from: Data(weather.utf8)).memoryProposal == nil)
}

@Test func apiErrorReadsDetailCode() {
    let data = Data(##"{"detail":{"message":"密码类信息不会被记住","code":"sensitive_credential"}}"##.utf8)
    let e = APIClient.apiError(status: 422, data: data)
    #expect(e.message == "密码类信息不会被记住")
    #expect(e.code == "sensitive_credential")
    let plain = APIClient.apiError(status: 404, data: Data(##"{"detail":"记忆不存在"}"##.utf8))
    #expect(plain.message == "记忆不存在" && plain.code == nil)
}

@Test func decodesSettingsAndClearResponses() throws {
    let s = try JSONDecoder().decode(MemorySettings.self, from: Data(#"{"enabled":true,"server_enabled":true,"active_count":3,"max_active":200,"max_chars":200}"#.utf8))
    #expect(s.enabled && s.activeCount == 3)
    let old = try JSONDecoder().decode(ClearMessagesResponse.self, from: Data(#"{"ok":true}"#.utf8))
    #expect(old.deletedMemories == 0)
    let new = try JSONDecoder().decode(ClearMessagesResponse.self, from: Data(#"{"ok":true,"deleted_memories":5}"#.utf8))
    #expect(new.deletedMemories == 5)
    let done = try JSONDecoder().decode(ChatDone.self, from: Data(#"{"message_id":9,"usage":{},"memory_ids":[1,2]}"#.utf8))
    #expect(done.memoryIDs == [1, 2] && done.messageID == 9)
}

@Test func m4ModelsDecodeOptionalGrowthReviewReferencesAndExport() throws {
    let d=JSONDecoder()
    let growth=try d.decode(BotGrowth.self,from:Data(#"{"bot_id":4,"memory_counts":{"fact":2},"assisted_count":8,"recent_memories":[]}"#.utf8))
    #expect(growth.assistedCount==8 && growth.firstConversationAt==nil)
    let review=try d.decode(MonthlyMemoryReview.self,from:Data(#"{"month":"2026-10","review_status":"pending","assisted_count":3,"candidate_count":1}"#.utf8))
    #expect(review.newMemories.isEmpty && review.capabilities.isEmpty && review.suggestion==nil)
    let refs=try d.decode(MemoryReferencesResponse.self,from:Data(#"{"message_id":7,"memories":[]}"#.utf8))
    #expect(refs.messageId==7 && refs.memories.isEmpty)
    let export=try d.decode(MemoryExportResponse.self,from:Data(#"{"format":"verabot-memory-export-v1","memories":[{"id":5,"scope":"global","bot_id":null,"type":"fact","source":"memory_page","source_bot_id":null,"source_message_id":null,"status":"active","action":"create","target_id":null,"sensitivity":"normal","confidence":1,"use_count":2,"last_used_at":null,"confirmed_at":"2026-10-01","expires_at":null,"created_at":"2026-10-01","updated_at":"2026-10-01","content":"茶"}]}"#.utf8))
    #expect(export.memories.count==1 && export.memories[0].content=="茶" && export.memories[0].useCount==2)
}

@Test func memoryFilterIsCaseInsensitiveAndKeepsTypeAndCandidateSearch() throws {
    let data=Data(#"{"id":1,"scope":"bot","bot_id":2,"type":"preference","content":"Likes Green Tea","status":"candidate","source":"implicit_extraction"}"#.utf8)
    let item=try JSONDecoder().decode(Memory.self,from:data)
    #expect(MemoryFilter.matches(item,query:"GREEN",type:nil))
    #expect(MemoryFilter.matches(item,query:"tea",type:.preference))
    #expect(!MemoryFilter.matches(item,query:"tea",type:.fact))
    #expect(MemoryFilter.matches(item,query:"",type:.preference))
}
