import Foundation
public struct OwnedTask:Codable,Sendable,Identifiable,Hashable {
 public let id:Int
 public let ownerBotID:Int?
 public let ownerName:String
 public let goal:String
 public let completionCriteria:String
 public let state:String
 public let version:Int
 public let usedTokens:Int
 public let reservedTokens:Int?
 public let tokenLimit:Int
 public let cursor:Int
 public let steps:[OwnedStep]
 public let waits:[OwnedWait]
 public var statusTitle:String {
  switch state {case "queued":return "待执行";case "running":return "正在处理";case "awaiting_user","awaiting_approval":return "等你处理";case "retry_wait":return "稍后重试";case "completed":return "已完成";case "stopped":return "已停止";case "interrupted":return "已中断";default:return "未完成"}
 }
 public var canContinue:Bool {["stopped","interrupted","failed"].contains(state)}
 enum CodingKeys:String,CodingKey {case id,goal,state,version,cursor,steps,waits;case ownerBotID="owner_bot_id",ownerName="owner_name",completionCriteria="completion_criteria",usedTokens="used_tokens",tokenLimit="token_limit",reservedTokens="reserved_tokens"}
}
public struct OwnedStep:Codable,Sendable,Hashable,Identifiable {
 public let id:Int
 public let botID:Int?
 public let kind:String
 public let status:String
 public let resultJSON:String?
 public var resultText:String? {
  guard let resultJSON,let data=resultJSON.data(using:.utf8),let obj=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else{return nil}
  return obj["text"] as? String
 }
 enum CodingKeys:String,CodingKey {case id,kind,status;case botID="bot_id",resultJSON="result_json"}
}
public struct OwnedWait:Codable,Sendable,Hashable,Identifiable {
 public let id:Int
 public let stepID:Int
 public let kind:String
 public let question:String
 public let actionID:Int?
 enum CodingKeys:String,CodingKey {case id,kind,question;case stepID="step_id",actionID="action_id"}
}
public struct OwnedTasksResponse:Decodable,Sendable {public let tasks:[OwnedTask]}
public struct OwnedTaskCreate:Codable,Sendable {
 public let botID:Int
 public let goal:String
 public let completionCriteria:String
 public let tokenLimit:Int
 public init(botID:Int,goal:String,completionCriteria:String,tokenLimit:Int=20000){self.botID=botID;self.goal=goal;self.completionCriteria=completionCriteria;self.tokenLimit=tokenLimit}
 enum CodingKeys:String,CodingKey {case goal;case botID="bot_id",completionCriteria="completion_criteria",tokenLimit="token_limit"}
}
public struct TaskRequestIdentity:Codable,Sendable {
 private var payload:Data?
 private var requestKey=UUID().uuidString
 public init(){}
 public var pendingPayload:Data? {payload}
 public mutating func acknowledge(){self=Self()}
 public mutating func key(for data:Data)->String {
  if let payload,payload != data{requestKey=UUID().uuidString}
  payload=data;return requestKey
 }
}
