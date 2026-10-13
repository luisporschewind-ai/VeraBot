import Foundation

public enum GroupExecutionReducer {
    private static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue?) -> T? {
        guard let value, let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    @discardableResult
    public static func apply(_ event: GroupExecutionEvent, to state: inout GroupExecutionViewState,
                             groupID: Int) -> Bool {
        guard event.groupID == groupID, event.id > state.snapshot.eventCursor else {return false}
        state.snapshot.eventCursor = event.id
        if event.kind == "group_cleared" {
            state = .init(snapshot:.init(eventCursor:event.id));return true
        }
        if let current = state.snapshot.task {
            if let id = event.taskID, id < current.id {
                let resumed = event.kind == "task_updated" && !current.state.canStop && decode(GroupTask.self,from:{if case .object(let data) = event.payload {return data["task"]};return nil}())?.state.canStop == true
                if !resumed {return false}
            }
            if event.taskID == current.id && event.version < current.version {return false}
        }
        guard case .object(let payload) = event.payload else {return true}
        if event.kind == "task_updated", let task = decode(GroupTask.self,from:payload["task"]) {
            if task.id != state.snapshot.task?.id {state.snapshot.clarification = nil}
            state.snapshot.task = task
        } else if event.kind == "clarification_updated" {
            state.snapshot.clarification = decode(GroupClarification.self,from:payload["clarification"])
        } else if event.kind == "handoff_scheduled", case .string("handoff")? = payload["kind"],
                  case .number(let memberID)? = payload["to_member_id"] {
            state.snapshot.task?.ownerMemberID = Int(memberID)
        }
        if let current = state.snapshot.task, event.taskID == current.id, event.version > current.version {
            state.snapshot.task?.version = event.version
        }
        if ["message_start","message_snapshot","message_done"].contains(event.kind),
           let message = decode(GroupMessage.self,from:payload["message"]), message.groupID == groupID {
            if let index = state.messages.firstIndex(where:{$0.id == message.id}) {state.messages[index] = message}
            else {state.messages.append(message)}
            state.messages.sort {$0.id < $1.id}
        } else if event.kind == "message_snapshot", case .number(let id)? = payload["message_id"], case .string(let content)? = payload["content"] {
            if let index = state.messages.firstIndex(where:{$0.id == Int(id)}) {state.messages[index].content = content;state.messages[index].status = .streaming}
            else {state.messages.append(.init(id:Int(id),memberID:nil,content:content,status:.streaming,groupID:groupID,turnID:0,role:.bot))}
        }
        return true
    }
}
