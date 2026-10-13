import Foundation
import VeraBotCore
import VeraBotNetworking
import VeraBotPersistence
/// Scope lives in the supplied account/server-specific store. Old requests are fenced on close.
@MainActor public final class PrimaryBotRepository {
 public private(set) var settings:PrimaryBotSettings?
 private let api:APIClient
 private let store:ConversationStore
 private var generation=0
 private var closed=false
 private func requireOpen() throws {if closed{throw CancellationError()}}
 public init(api:APIClient,store:ConversationStore){self.api=api;self.store=store}
 public func close(){closed=true;generation += 1;settings=nil}
 public func cached() async throws -> PrimaryBotSettings? {try requireOpen();return try await store.conversation(PrimaryBotSettings.self,kind:"primary-bot",id:0)}
 public func load() async throws {try requireOpen();
  let g=generation
  let cached=try await store.conversations(PrimaryBotSettings.self,kind:"primary-bot")
  guard g==generation else{return};settings=cached.first
  let fresh=try await api.primaryBot();guard g==generation else{return}
  try await store.saveConversation(fresh,kind:"primary-bot",id:0)
  guard g==generation else{return};settings=fresh
 }
 public func update(botID:Int?,activeEnabled:Bool,expectedVersion:Int) async throws {try requireOpen();
  let g=generation
  do {
   let fresh=try await api.updatePrimaryBot(.init(botID:botID,activeEnabled:activeEnabled,expectedVersion:expectedVersion))
   guard g==generation else{return}
   try await store.saveConversation(fresh,kind:"primary-bot",id:0)
   guard g==generation else{return};settings=fresh
  } catch {if let e=error as? APIError,e.status==409{try? await load()};throw error}
 }
}
