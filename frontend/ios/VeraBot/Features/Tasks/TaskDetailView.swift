import SwiftUI
import VeraBotCore
struct TaskDetailView:View {
 let initial:OwnedTask
 @Environment(AppState.self) private var app
 @State private var current:OwnedTask?
 @State private var answer=""
 @State private var error:String?
 @State private var busy=false
 @State private var confirmStop=false
 @State private var choosingOwner=false
 @State private var bots:[Bot]=[]
 var task:OwnedTask{current ?? initial}
 var body:some View {
  List {
   Section("任务"){Text(task.goal);LabeledContent("状态",value:task.statusTitle);LabeledContent("负责人",value:task.ownerName);Text("完成标准："+task.completionCriteria);Text("已知用量 \(task.usedTokens) / \(task.tokenLimit)").font(.footnote);if let reserved=task.reservedTokens,reserved>0{Text("另有 \(reserved) 用量预留待核实").font(.footnote).foregroundStyle(.secondary)}}
   if let error {Section{Text(error).foregroundStyle(.secondary)}}
   ForEach(task.steps){step in if let text=step.resultText{Section(step.kind == "consult" ? "咨询结果":"进度"){Text(text)}}}
   ForEach(task.waits){wait in
    Section("需要你帮助"){
     Text(wait.question)
     if let aid=wait.actionID,task.state == "awaiting_approval" {
      NavigationLink("查看操作并确认"){TaskApprovalView(actionID:aid,onResolved:{Task{await reload()}})}
     } else {
      TextField("补充材料或下一步安排",text:$answer,axis:.vertical)
      Button("回复并继续"){Task{await submitAnswer()}}.disabled(busy || answer.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
     }
    }
   }
   Section {
    if task.canContinue{Button("继续任务"){Task{await control("continue")}}}
    if task.state != "completed" && task.state != "stopped"{Button("停止任务",role:.destructive){confirmStop=true}}
    if task.canContinue || task.state == "awaiting_user"{Button("移交给其他 Bot"){choosingOwner=true;Task{bots=(try? await app.api.bots().bots) ?? []}}}
   }.disabled(busy)
  }
  .navigationTitle("任务详情")
  .confirmationDialog("停止这项任务？",isPresented:$confirmStop){Button("停止",role:.destructive){Task{await control("stop")}}}
  .confirmationDialog("选择接手的 Bot",isPresented:$choosingOwner){ForEach(bots){bot in Button(bot.name){Task{await control("transfer",botID:bot.id)}}}}
  .refreshable{await reload()}
  .task(id:task.version){
   if answer.isEmpty,let repo=app.ownedTaskRepository {answer=(try? await repo.pendingAnswer(taskID:task.id)) ?? ""}
   let g=app.sessionGeneration;let client=app.groupAPI
   do {
    for try await value in client.ownedTaskStream(task.id,afterID:task.cursor){
     guard app.isCurrentSession(g) else{return};current=value
     if let repo=app.ownedTaskRepository{try? await repo.save(value)}
    }
   } catch {if !Task.isCancelled,app.isCurrentSession(g){self.error=app.message(for:error)}}
  }
 }
 private func reload() async {let g=app.sessionGeneration;do{let v=try await app.groupAPI.ownedTask(task.id);guard app.isCurrentSession(g) else{return};current=v;error=nil}catch{if app.isCurrentSession(g){self.error=app.message(for:error)}}}
 private func control(_ action:String,botID:Int?=nil) async {
  busy=true;defer{busy=false};let g=app.sessionGeneration
  do{let v=try await app.groupAPI.ownedControl(task,action:action,botID:botID);guard app.isCurrentSession(g) else{return};current=v;error=nil}catch{if app.isCurrentSession(g){self.error=app.message(for:error);await reload()}}
 }
 private func submitAnswer() async {
  busy=true;defer{busy=false};let g=app.sessionGeneration
  do{guard let repo=app.ownedTaskRepository else{return};let v=try await repo.answer(task,message:answer);guard app.isCurrentSession(g) else{return};current=v;answer="";error=nil}catch{if app.isCurrentSession(g){self.error=app.message(for:error)}}
 }
}
