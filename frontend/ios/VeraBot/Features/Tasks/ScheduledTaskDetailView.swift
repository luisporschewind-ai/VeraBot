import SwiftUI
import VeraBotCore
struct ScheduledTaskDetailView:View {
 let task:ScheduledTask
 @Environment(AppState.self) private var app
 @State private var current:ScheduledTask?
 @State private var runs:[ScheduledRun]=[]
 @State private var error:String?
 @State private var busy=false
 @State private var confirmDelete=false
 @State private var title=""
 @State private var instruction=""
 var item:ScheduledTask{current ?? task}
 var body:some View {
  Form {
   Section("周期任务"){TextField("标题",text:$title);TextField("任务内容",text:$instruction,axis:.vertical);Text("时区："+item.timezone);Button("保存修改"){Task{await save()}}}
   Section {
    Button(item.state == "paused" ? "恢复排程":"暂停排程"){Task{await control(item.state == "paused" ? "resume":"pause")}}
    Button("立即执行一次"){Task{await run()}}
    Button("删除周期任务",role:.destructive){confirmDelete=true}
   }.disabled(busy)
   if let error{Text(error)}
   Section("执行历史"){ForEach(runs){run in VStack(alignment:.leading){Text(run.statusTitle);if let result=run.resultText{Text(result)};if let problem=run.errorSummary{Text(problem).foregroundStyle(.secondary)}}}}
  }.navigationTitle("周期任务")
  .task{title=item.title;instruction=item.instruction;await history()}
  .refreshable{await history()}
  .confirmationDialog("删除这项周期任务？",isPresented:$confirmDelete){Button("删除",role:.destructive){Task{await control("delete")}}}
 }

 private func control(_ action:String) async {
  busy=true;defer{busy=false};let g=app.sessionGeneration
  do{let fresh=try await app.groupAPI.scheduledControl(item,action:action);guard app.isCurrentSession(g) else{return};current=fresh;error=nil}
  catch {if app.isCurrentSession(g){self.error=app.message(for:error);await refreshDefinition()}}
 }
 private func save() async {
  busy=true;defer{busy=false};let g=app.sessionGeneration
  do{let fresh=try await app.groupAPI.updateScheduledTask(item,title:title,instruction:instruction);guard app.isCurrentSession(g) else{return};current=fresh;error=nil}
  catch {if app.isCurrentSession(g){self.error=app.message(for:error);await refreshDefinition()}}
 }
 private func run() async {
  busy=true;defer{busy=false};let g=app.sessionGeneration
  do{guard let repo=app.scheduledTaskRepository else{return};_ = try await repo.run(id:item.id);guard app.isCurrentSession(g) else{return};await history()}
  catch {if app.isCurrentSession(g){self.error=app.message(for:error)}}
 }
 private func history() async {
  let g=app.sessionGeneration
  do{let fresh=try await app.groupAPI.scheduledHistory(item.id).runs;guard app.isCurrentSession(g) else{return};runs=fresh}
  catch {if app.isCurrentSession(g){self.error=app.message(for:error)}}
 }
 private func refreshDefinition() async {
  let g=app.sessionGeneration
  if let fresh=try? await app.groupAPI.scheduledTasks(botID:item.botID ?? 0).tasks.first(where:{$0.id==item.id}),app.isCurrentSession(g){current=fresh}
 }
}
