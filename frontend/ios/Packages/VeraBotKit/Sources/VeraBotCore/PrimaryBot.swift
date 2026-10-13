import Foundation
public struct PrimaryBotSettings: Codable, Sendable, Equatable {
 public let primaryBotID:Int?
 public let activeEnabled:Bool
 public let dailyTokenLimit:Int
 public let version:Int
 enum CodingKeys:String,CodingKey {case primaryBotID="primary_bot_id",activeEnabled="active_enabled",dailyTokenLimit="daily_token_limit",version}
}
public struct PrimaryBotPatch: Encodable,Sendable {
 public let botID:Int?
 public let activeEnabled:Bool
 public let expectedVersion:Int
 public init(botID:Int?,activeEnabled:Bool,expectedVersion:Int){self.botID=botID;self.activeEnabled=activeEnabled;self.expectedVersion=expectedVersion}
 enum CodingKeys:String,CodingKey {case botID="primary_bot_id",activeEnabled="active_enabled",expectedVersion="expected_version"}
 public func encode(to encoder:Encoder)throws {
  var c=encoder.container(keyedBy:CodingKeys.self)
  try c.encode(botID,forKey:.botID);try c.encode(activeEnabled,forKey:.activeEnabled);try c.encode(expectedVersion,forKey:.expectedVersion)
 }
}
