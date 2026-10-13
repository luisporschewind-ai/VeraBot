import Foundation
import VeraBotCore
extension APIClient {
 public func primaryBot() async throws -> PrimaryBotSettings {try await call("/api/primary-bot")}
 public func updatePrimaryBot(_ patch:PrimaryBotPatch) async throws -> PrimaryBotSettings {
  try await call("/api/primary-bot",method:"PATCH",body:encode(patch))
 }
}
