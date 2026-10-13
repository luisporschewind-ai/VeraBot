import SwiftUI
import VeraBotCore
struct TaskEditorView:View {
 let botID:Int
 @Environment(AppState.self) private var app
 @Environment(\.dismiss) private var dismiss
 @State private var goal=""
 @State private var criteria=""
 @State private var periodic=false
 @State private var repeatRule="daily"
 @State private var start=Date().addingTimeInterval(3600)
 @State private var busy=false
 @State private var error:String?
 var body:some View {
  Form {
   Section("你希望完成什么"){TextField("任务目标",text:$goal,axis:.vertical);TextField("怎样算完成",text:$criteria,axis:.vertical)}
   Section {
    Toggle("周期执行",isOn:$periodic)
    if periodic {
     Picker("频率",selection:$repeatRule){Text("每天").tag("daily");Text("工作日").tag("weekdays");Text("一次").tag("once")}
     DatePicker("首次时间",selection:$start,in:Date()...,displayedComponents:[.date,.hourAndMinute])
     Text("时区：\(TimeZone.current.identifier)").font(.footnote).foregroundStyle(.secondary)
    }
   }
   Section("执行范围"){
    Text("使用该 Bot 已获准的查询能力。咨询其他 Bot 受既有权限限制，外部写操作需要你逐次批准。总用量上限 20,000，等待你时不继续调用模型。")
    Text("确定后创建任务；普通聊天不会自动变成持续任务。")
   }
   if let error {Section{Text(error).foregroundStyle(.secondary)}}
  }
  .navigationTitle("交办任务")
  .toolbar {
   ToolbarItem(placement:.cancellationAction){Button("取消"){dismiss()}.disabled(busy)}
   ToolbarItem(placement:.confirmationAction){Button("确认交办"){Task{await submit()}}.disabled(busy || goal.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || criteria.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
  }
  .interactiveDismissDisabled(busy)
 }
 private func submit() async {
  busy=true;defer{busy=false};let g=app.sessionGeneration
  do {
   if periodic {
    let f=ISO8601DateFormatter();f.timeZone=TimeZone.current
    let body=ScheduledTaskCreate(botID:botID,title:String(goal.prefix(200)),instruction:goal+"\n完成标准："+criteria,startAt:f.string(from:start),timezone:TimeZone.current.identifier,repeatRule:repeatRule)
    guard let repo=app.scheduledTaskRepository else{return};_ = try await repo.create(body)
   } else {
    guard let repo=app.ownedTaskRepository else{return};_ = try await repo.create(.init(botID:botID,goal:goal,completionCriteria:criteria))
   }
   guard app.isCurrentSession(g) else{return};dismiss()
  } catch {guard app.isCurrentSession(g) else{return};self.error=app.message(for:error)}
 }
}
