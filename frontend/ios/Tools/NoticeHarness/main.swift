import Foundation

@main struct NoticeHarness {
    static func main() {
        var queue = NoticeQueue<String>(capacity: 2)
        queue.show("正在保存", key: "save")
        precondition(queue.current?.message == "正在保存", "first notice must become visible")
        let original = queue.current!.id
        queue.show("正在保存", key: "save")
        precondition(queue.current?.id == original && queue.pending.isEmpty, "duplicates must not restart the timer")
        queue.show("已保存", key: "save")
        let completion = queue.current!.id
        precondition(completion != original && queue.current?.message == "已保存", "same operation must update in place")
        queue.dismiss(id: original)
        precondition(queue.current?.id == completion, "stale timer must not dismiss an updated notice")
        queue.show("一", key: "one")
        queue.show("旧内容", key: "two")
        queue.show("新内容", key: "two")
        precondition(queue.pending.map(\.message) == ["一", "新内容"], "queued update must retain its position")
        queue.show("三", key: "three")
        precondition(queue.pending.map(\.message) == ["新内容", "三"], "overflow must retain the newest bounded backlog")
        queue.dismiss(id: completion)
        precondition(queue.current?.message == "新内容", "dismiss must advance FIFO")
        queue.show("需要处理", key: "urgent", replacing: true)
        precondition(queue.current?.message == "需要处理" && queue.pending.map(\.message) == ["三"], "explicit replacement must keep the remaining queue")
        queue.clear()
        precondition(queue.current == nil && queue.pending.isEmpty, "leaving a scope must clear every notice")
        queue.dismiss(id: completion)
        precondition(queue.current == nil, "stale dismiss after clear must be harmless")
        print("Notice queue: 10 checks passed")
    }
}
