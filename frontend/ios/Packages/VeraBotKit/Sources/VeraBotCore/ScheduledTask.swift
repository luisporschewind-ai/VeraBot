import Foundation
public struct ScheduledTask:Codable,Sendable,Identifiable {
 public let id:Int
 public let botID:Int?
 public let title:String
 public let instruction:String
 public let state:String
 public let version:Int
 public let timezone:String
 public let repeatRule:String
 public let startAtUTC:String
 public let executionMode:String
 enum CodingKeys:String,CodingKey {case id,title,instruction,state,version,timezone;case botID="bot_id",repeatRule="repeat",startAtUTC="start_at_utc",executionMode="execution_mode"}
 public init(from decoder:Decoder)throws {
  let c=try decoder.container(keyedBy:CodingKeys.self)
  id=try c.decode(Int.self,forKey:.id);botID=try c.decodeIfPresent(Int.self,forKey:.botID)
  title=try c.decode(String.self,forKey:.title);instruction=try c.decode(String.self,forKey:.instruction)
  state=try c.decode(String.self,forKey:.state);version=try c.decode(Int.self,forKey:.version)
  timezone=try c.decode(String.self,forKey:.timezone);repeatRule=try c.decode(String.self,forKey:.repeatRule)
  startAtUTC=try c.decode(String.self,forKey:.startAtUTC);executionMode=try c.decodeIfPresent(String.self,forKey:.executionMode) ?? "read_only"
 }
}
public struct ScheduledTasksResponse:Decodable,Sendable{public let tasks:[ScheduledTask]}
public struct ScheduledTaskCreate:Encodable,Sendable {
 public let botID:Int
 public let title:String
 public let instruction:String
 public let startAt:String
 public let timezone:String
 public let repeatRule:String
 public let executionMode:String
 public init(botID:Int,title:String,instruction:String,startAt:String,timezone:String,repeatRule:String,executionMode:String="owned"){self.botID=botID;self.title=title;self.instruction=instruction;self.startAt=startAt;self.timezone=timezone;self.repeatRule=repeatRule;self.executionMode=executionMode}
 enum CodingKeys:String,CodingKey {case title,instruction,timezone;case botID="bot_id",startAt="start_at",repeatRule="repeat",executionMode="execution_mode"}
}
public struct ScheduledRunsResponse:Decodable,Sendable {public let runs:[ScheduledRun]}
public struct ScheduledRun:Decodable,Sendable,Identifiable {
 public let id:Int
 public let state:String
 public let resultText:String?
 public let errorSummary:String?
 public var statusTitle:String {switch state {case "succeeded":return "已完成";case "retry_wait":return "等待处理";case "running":return "正在执行";case "queued":return "待执行";case "cancelled":return "已取消";case "skipped":return "已跳过";case "interrupted":return "已中断";default:return "未完成"}}
 enum CodingKeys:String,CodingKey {case id,state;case resultText="result_text",errorSummary="error_summary"}
}
