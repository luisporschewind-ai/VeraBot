import Foundation
import VeraBotCore
import VeraBotNetworking
import VeraBotPersistence
@MainActor public final class ScheduledTaskRepository {
 private let api:APIClient
 private let store:ConversationStore
 private var generation=0
 private var closed=false
 private func requireOpen() throws {if closed{throw CancellationError()}}
 public func close(){closed=true;generation += 1}
 public init(api:APIClient,store:ConversationStore){self.api=api;self.store=store}
 public func create(_ body:ScheduledTaskCreate) async throws -> ScheduledTask {try requireOpen();
  let e=JSONEncoder();e.outputFormatting=[.sortedKeys]
  let g=generation
  var request=try await store.conversation(TaskRequestIdentity.self,kind:"scheduled-request",id:body.botID) ?? TaskRequestIdentity()
  let key=request.key(for:try e.encode(body));try await store.saveConversation(request,kind:"scheduled-request",id:body.botID)
  let result=try await api.createScheduledTask(body,key:key)
  guard g==generation else{throw CancellationError()}
  request.acknowledge();try await store.saveConversation(request,kind:"scheduled-request",id:body.botID)
  guard g==generation else{throw CancellationError()};return result
 }
 public func run(id:Int) async throws -> ScheduledRun {try requireOpen();
  let g=generation
  var intent=try await store.conversation(TaskRequestIdentity.self,kind:"scheduled-run-request",id:id) ?? TaskRequestIdentity()
  let key=intent.key(for:Data(String(id).utf8));try await store.saveConversation(intent,kind:"scheduled-run-request",id:id)
  let result=try await api.runScheduledTask(id,key:key)
  guard g==generation else{throw CancellationError()}
  intent.acknowledge();try await store.saveConversation(intent,kind:"scheduled-run-request",id:id)
  guard g==generation else{throw CancellationError()};return result
 }

}
