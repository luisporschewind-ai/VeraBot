import SwiftUI
import VeraBotCore
struct TaskApprovalView:View {
 let actionID:Int
 var onResolved:()->Void
 @Environment(AppState.self) private var app
 @State private var action:PendingAction?
 @State private var error:String?
 @State private var busy=false
 var body:some View {
  Form {
   if let action {
    Section("待确认操作"){
     Text(action.label ?? "外部操作")
     Text(action.toolRisk.label).font(.footnote).foregroundStyle(.secondary)
     ForEach(action.arguments?.argumentPairs ?? [],id:\.0){pair in LabeledContent(pair.0,value:pair.1)}
     ForEach(action.warnings,id:\.self){Text($0).foregroundStyle(.secondary)}
     if action.argsUnavailable == true{Text("操作参数无法读取，请恢复连接后再确认。")}
    }
    if action.status == "pending" {Section{Button("批准并继续"){Task{await decide(true)}}.disabled(action.argsUnavailable == true);Button("拒绝",role:.destructive){Task{await decide(false)}}}.disabled(busy)}
    else {Text("操作已处理，返回任务查看后续进度。")}
   }
   if let error{Text(error)}
  }.navigationTitle("操作确认")
  .task{let g=app.sessionGeneration;do{let a=try await app.groupAPI.pendingAction(id:actionID);guard app.isCurrentSession(g) else{return};action=a}catch{if app.isCurrentSession(g){self.error=app.message(for:error)}}}
 }
 private func decide(_ approve:Bool) async {
  busy=true;defer{busy=false};let g=app.sessionGeneration
  do{let a=try await (approve ? app.groupAPI.confirmPendingAction(id:actionID):app.groupAPI.cancelPendingAction(id:actionID));guard app.isCurrentSession(g) else{return};action=a;onResolved()}catch{if app.isCurrentSession(g){self.error=app.message(for:error)}}
 }
}
