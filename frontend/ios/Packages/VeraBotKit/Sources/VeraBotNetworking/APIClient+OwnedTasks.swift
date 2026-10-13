import Foundation
import VeraBotCore
extension APIClient {
 public func ownedTasks(botID:Int) async throws -> OwnedTasksResponse {try await call("/api/owned-tasks",query:[URLQueryItem(name:"bot_id",value:String(botID))])}
 public func ownedTask(_ id:Int) async throws -> OwnedTask {try await call("/api/owned-tasks/\(id)")}
 public func createOwnedTask(_ body:OwnedTaskCreate,key:String) async throws -> OwnedTask {try await call("/api/owned-tasks",method:"POST",body:encode(body),headers:["Idempotency-Key":key])}
 public func ownedControl(_ task:OwnedTask,action:String,botID:Int?=nil) async throws -> OwnedTask {
  struct Body:Encodable{let expected_version:Int;let bot_id:Int?}
  return try await call("/api/owned-tasks/\(task.id)/\(action)",method:"POST",body:encode(Body(expected_version:task.version,bot_id:botID)))
 }
 public func answerOwnedTask(_ task:OwnedTask,message:String,key:String) async throws -> OwnedTask {
  struct Body:Encodable{let expected_version:Int;let message:String}
  return try await call("/api/owned-tasks/\(task.id)/inputs",method:"POST",body:encode(Body(expected_version:task.version,message:message)),headers:["Idempotency-Key":key])
 }
 public func ownedTaskStream(_ id:Int,afterID:Int) -> AsyncThrowingStream<OwnedTask,Error> {
  AsyncThrowingStream {continuation in
   let generation=session?.generation
   let task=Task {
    do {
     func check() throws {try Task.checkCancellation();if let generation,session?.isCurrent(generation) != true{throw CancellationError()}}
     let path="/api/owned-tasks/\(id)/events/stream"
     func request(_ token:String?)->URLRequest {
      var r=makeRequest(path,method:"GET",body:nil,query:[URLQueryItem(name:"after_id",value:String(afterID))],token:token,headers:["Accept":"text/event-stream"]);r.timeoutInterval=300;return r
     }
     try check();let sent=token
     var (bytes,response)=try await urlSession.bytes(for:request(sent))
     var status=(response as? HTTPURLResponse)?.statusCode ?? 0
     if status==401,let fresh=await refreshedToken(after:sent,path:path,generation:generation){try check();(bytes,response)=try await urlSession.bytes(for:request(fresh));status=(response as? HTTPURLResponse)?.statusCode ?? 0}
     guard (200..<300).contains(status) else{throw APIError(status:status,message:"无法读取任务进度")}
     var lines:[String]=[]
     for try await raw in bytes.lines {
      try check();let line=raw.hasSuffix("\r") ? String(raw.dropLast()):raw
      if line.hasPrefix("data:"){lines.append(String(line.dropFirst(5)).trimmingCharacters(in:.whitespaces))}
      if line.isEmpty && !lines.isEmpty {
       let value=try JSONDecoder().decode(OwnedTask.self,from:Data(lines.joined(separator:"\n").utf8));lines=[]
       if value.id==id{continuation.yield(value)}
      }
     }
     continuation.finish()
    } catch {continuation.finish(throwing:error)}
   }
   continuation.onTermination={_ in task.cancel()}
  }
 }
}
