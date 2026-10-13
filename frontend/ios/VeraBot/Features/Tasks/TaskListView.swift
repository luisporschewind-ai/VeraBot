import SwiftUI
import VeraBotCore
import VeraBotNetworking
struct TaskListView:View {
 let botID:Int
 let botName:String
 @Environment(AppState.self) private var app
 @State private var tasks:[OwnedTask]=[]
 @State private var schedules:[ScheduledTask]=[]
 @State private var error:String?
 @State private var creating=false
 var body:some View {
  List {
   Section {
    Toggle("允许主动任务",isOn:Binding(get:{app.primarySettings?.activeEnabled ?? false},set:{value in Task{await app.setActiveTasks(value)}}))
     .disabled(app.primaryBotID == nil)
    Text("只处理你确认交办的任务。完成或需要帮助时会留下消息；后台需保持运行。每日主动额度 \(app.primarySettings?.dailyTokenLimit ?? 20000)，仍计入账号额度。")
     .font(.footnote).foregroundStyle(.secondary)
   }
   if let error {Section{Text(error).foregroundStyle(.secondary)}}
   ForEach(["进行中","等你处理","已完成"],id:\.self){section in
    let values=tasks.filter {category($0)==section}
    if !values.isEmpty {
     Section(section){ForEach(values){task in NavigationLink {TaskDetailView(initial:task)} label:{VStack(alignment:.leading){Text(task.goal).lineLimit(2);Text(task.statusTitle).font(.caption).foregroundStyle(.secondary)}}}}
    }
   }
   if !schedules.isEmpty {Section("周期任务"){ForEach(schedules){schedule in NavigationLink{ScheduledTaskDetailView(task:schedule)} label:{VStack(alignment:.leading){Text(schedule.title);Text(schedule.state == "active" ? "已安排" : "已暂停或结束").font(.caption).foregroundStyle(.secondary)}}}}}
   if tasks.isEmpty && schedules.isEmpty {Section{Text("交办一项任务，或安排周期工作。")}}
  }
  .navigationTitle("\(botName)的任务")
  .toolbar {ToolbarItem(placement:.topBarTrailing){Button{creating=true}label:{Image(systemName:"plus")}.disabled(app.primarySettings?.activeEnabled != true)}}
  .sheet(isPresented:$creating,onDismiss:{Task{await load()}}){NavigationStack{TaskEditorView(botID:botID)}}
  .task{await app.refreshPrimarySettings();await load()}
  .refreshable{await load()}
 }
 private func category(_ t:OwnedTask)->String {
  if ["awaiting_user","awaiting_approval","interrupted","failed"].contains(t.state){return "等你处理"}
  return ["completed","stopped"].contains(t.state) ? "已完成":"进行中"
 }
 private func load() async {
  let g=app.sessionGeneration
  if let repo=app.ownedTaskRepository,let cached=try? await repo.cachedTasks(),app.isCurrentSession(g){tasks=cached.filter{$0.ownerBotID==botID}}
  do {
   let fresh=try await app.groupAPI.ownedTasks(botID:botID).tasks
   let periodic=try await app.groupAPI.scheduledTasks(botID:botID).tasks
   guard app.isCurrentSession(g) else{return};tasks=fresh;schedules=periodic;error=nil
   if let repo=app.ownedTaskRepository{_ = try? await repo.refresh(botID:botID)}
  } catch {guard app.isCurrentSession(g) else{return};self.error=app.message(for:error)}
 }
}
