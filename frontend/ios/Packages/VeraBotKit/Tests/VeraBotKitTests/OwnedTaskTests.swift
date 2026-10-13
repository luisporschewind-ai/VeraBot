import Foundation
import Testing
@testable import VeraBotCore
@Test func ownedTaskContract() throws {
 let data=Data(#"{"id":2,"owner_bot_id":7,"owner_name":"A","goal":"g","completion_criteria":"c","state":"awaiting_user","version":3,"used_tokens":20,"token_limit":20000,"cursor":4,"steps":[],"waits":[{"id":1,"step_id":2,"kind":"await_user","question":"Which week?","action_id":null}]}"#.utf8)
 let task=try JSONDecoder().decode(OwnedTask.self,from:data)
 #expect(task.waits.first?.question == "Which week?");#expect(task.statusTitle == "等你处理")
}
@Test func stableTaskRequestIdentity() throws {
 var intent=TaskRequestIdentity()
 let a=intent.key(for:Data("a".utf8));#expect(a == intent.key(for:Data("a".utf8)));#expect(a != intent.key(for:Data("b".utf8)))
}
@Test func scheduledTaskContract() throws {
 let t=try JSONDecoder().decode(ScheduledTask.self,from:Data(#"{"id":1,"bot_id":2,"title":"t","instruction":"i","state":"active","timezone":"UTC","repeat":"daily","version":1,"start_at_utc":"2026-10-14T01:00:00+00:00"}"#.utf8))
 #expect(t.executionMode == "read_only")
}

@Test func acknowledgedRequestGetsNewIdentity() {
 var request=TaskRequestIdentity();let data=Data("same".utf8)
 let old=request.key(for:data);request.acknowledge();#expect(request.key(for:data) != old)
}

import VeraBotData
import VeraBotNetworking
import VeraBotPersistence
@MainActor @Test func closedTaskScopeCannotReopenOldDatabase() async throws {
 let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("cache.db")
 let db=LocalDatabase(url:url);try db.open();defer{db.close();try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
 let repo=OwnedTaskRepository(api:APIClient(baseURL:URL(string:"http://unused.test")!,token:"test"),store:ConversationStore(database:db))
 repo.close()
 await #expect(throws:CancellationError.self){try await repo.cachedTasks()}
}

@Test(.enabled(if:ProcessInfo.processInfo.environment["VERABOT_OWNED_STREAM_FIXTURE"] != nil))
func ownedSSEYieldsBeforeConnectionEnds() async throws {
 let raw=try #require(ProcessInfo.processInfo.environment["VERABOT_OWNED_STREAM_FIXTURE"])
 let client=APIClient(baseURL:try #require(URL(string:raw)),token:"local-fixture")
 let started=Date()
 for try await snapshot in client.ownedTaskStream(1,afterID:0) {
  #expect(snapshot.state == "running")
  #expect(Date().timeIntervalSince(started)<3)
  break
 }
}
