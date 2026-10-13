import Foundation
import VeraBotCore
extension APIClient {
 public func scheduledTasks(botID:Int) async throws -> ScheduledTasksResponse {try await call("/api/scheduled-tasks",query:[URLQueryItem(name:"bot_id",value:String(botID))])}
 public func createScheduledTask(_ body:ScheduledTaskCreate,key:String) async throws -> ScheduledTask {try await call("/api/scheduled-tasks",method:"POST",body:encode(body),headers:["Idempotency-Key":key])}
 public func scheduledControl(_ task:ScheduledTask,action:String) async throws -> ScheduledTask {
  struct Version:Encodable{let expected_version:Int}
  return try await call("/api/scheduled-tasks/\(task.id)"+(action == "delete" ? "" : "/\(action)"),method:action == "delete" ? "DELETE":"POST",body:encode(Version(expected_version:task.version)))
 }
 public func runScheduledTask(_ id:Int,key:String) async throws -> ScheduledRun {try await call("/api/scheduled-tasks/\(id)/run",method:"POST",headers:["Idempotency-Key":key])}
 public func scheduledHistory(_ id:Int) async throws -> ScheduledRunsResponse {try await call("/api/scheduled-tasks/\(id)/runs")}
 public func updateScheduledTask(_ task:ScheduledTask,title:String,instruction:String) async throws -> ScheduledTask {
  struct Body:Encodable{let title:String;let instruction:String;let expected_version:Int}
  return try await call("/api/scheduled-tasks/\(task.id)",method:"PATCH",body:encode(Body(title:title,instruction:instruction,expected_version:task.version)))
 }
}
