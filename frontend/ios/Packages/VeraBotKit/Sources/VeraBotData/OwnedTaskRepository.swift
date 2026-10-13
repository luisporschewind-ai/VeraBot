import Foundation
import VeraBotCore
import VeraBotNetworking
import VeraBotPersistence
@MainActor public final class OwnedTaskRepository {
 private let api:APIClient
 private let store:ConversationStore
 private var generation=0
 private var closed=false
 private func requireOpen() throws {if closed{throw CancellationError()}}
 public init(api:APIClient,store:ConversationStore){self.api=api;self.store=store}
 public func close(){closed=true;generation += 1}
 public func save(_ value:OwnedTask) async throws {try requireOpen();try await store.saveConversation(value,kind:"owned-task",id:value.id)}
 public func cachedTasks() async throws -> [OwnedTask]{try requireOpen();return try await store.conversations(OwnedTask.self,kind:"owned-task")}
 public func refresh(botID:Int) async throws -> [OwnedTask]{try requireOpen();
  let g=generation;let fresh=try await api.ownedTasks(botID:botID).tasks
  guard g==generation else{throw CancellationError()}
  for task in fresh{try await store.saveConversation(task,kind:"owned-task",id:task.id)}
  guard g==generation else{throw CancellationError()};return fresh
 }
 public func create(_ body:OwnedTaskCreate) async throws -> OwnedTask {try requireOpen();
  let g=generation;let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
  let data=try encoder.encode(body)
  var intent=(try await store.conversation(TaskRequestIdentity.self,kind:"owned-task-request",id:body.botID)) ?? TaskRequestIdentity()
  let key=intent.key(for:data);try await store.saveConversation(intent,kind:"owned-task-request",id:body.botID)
  let fresh=try await api.createOwnedTask(body,key:key)
  guard g==generation else{throw CancellationError()};try await store.saveConversation(fresh,kind:"owned-task",id:fresh.id)
  intent.acknowledge();try await store.saveConversation(intent,kind:"owned-task-request",id:body.botID)
  guard g==generation else{throw CancellationError()};return fresh
 }
 public func answer(_ task:OwnedTask,message:String) async throws -> OwnedTask {try requireOpen();
  struct Body:Codable {let taskID:Int;let version:Int;let message:String}
  let g=generation;let e=JSONEncoder();e.outputFormatting=[.sortedKeys]
  var intent=try await store.conversation(TaskRequestIdentity.self,kind:"owned-answer",id:task.id) ?? TaskRequestIdentity()
  let key=intent.key(for:try e.encode(Body(taskID:task.id,version:task.version,message:message)))
  try await store.saveConversation(intent,kind:"owned-answer",id:task.id)
  let fresh=try await api.answerOwnedTask(task,message:message,key:key)
  guard g==generation else{throw CancellationError()}
  try await save(fresh);intent.acknowledge();try await store.saveConversation(intent,kind:"owned-answer",id:task.id)
  guard g==generation else{throw CancellationError()};return fresh
 }
 public func pendingAnswer(taskID:Int) async throws -> String? {try requireOpen();
  guard let intent=try await store.conversation(TaskRequestIdentity.self,kind:"owned-answer",id:taskID),let data=intent.pendingPayload,let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else{return nil}
  return object["message"] as? String
 }

}
