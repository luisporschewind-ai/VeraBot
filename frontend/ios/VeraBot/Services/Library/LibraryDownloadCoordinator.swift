import Foundation
import Observation
import Network
import UIKit
import VeraBotCore
import VeraBotData
import VeraBotPersistence
import VeraBotNetworking

private struct LibraryDownloadJob: Codable, Sendable {
    let item: VeraBotCore.LibraryItem
    let mode: LibraryDownloadMode
    let scope: String
    let identifier: String
}

@MainActor @Observable final class LibraryDownloadCoordinator: NSObject {
    private(set) var items: [VeraBotCore.LibraryItem] = []
    private(set) var active = Set<String>()
    private(set) var errors: [String:String] = [:]
    private(set) var revision = 0
    private(set) var isWiFi = false
    var paused: Bool { didSet { try? store.set(key:"downloads.paused",value:paused ? "1":"0"); if paused { cancelAutomatic() } else { enqueue(items:items,mode:.automaticWiFi) } } }
    let files: LibraryFileStore
    private let api: APIClient
    private let store: LibraryStore
    private let scope: String
    private let sessionIsCurrent: @Sendable () -> Bool
    private let monitor = NWPathMonitor()
    private var valid = true
    private var automatic: URLSession!
    private var manual: URLSession!
    private var jobs: [String:LibraryDownloadJob] = [:]
    private var failures = Set<String>()

    nonisolated static func configuration(identifier: String, manual: Bool) -> URLSessionConfiguration {
        let config=URLSessionConfiguration.background(withIdentifier:identifier)
        config.allowsCellularAccess=manual;config.allowsExpensiveNetworkAccess=manual;config.allowsConstrainedNetworkAccess=manual
        config.waitsForConnectivity=true;config.httpMaximumConnectionsPerHost=2
        config.urlCache=nil;config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return config
    }
    init(root: URL, scope: String, store: LibraryStore, api: APIClient, sessionIsCurrent: @escaping @Sendable () -> Bool) {
        self.files=LibraryFileStore(root:root.appendingPathComponent("Originals"));self.scope=scope;self.store=store;self.api=api;self.sessionIsCurrent=sessionIsCurrent
        self.paused=(try? store.value(key:"downloads.paused")) == "1"
        self.items=(try? store.items()) ?? []
        super.init()
        automatic=URLSession(configuration:Self.configuration(identifier:"com.verabot.library.\(scope).auto",manual:false),delegate:self,delegateQueue:nil)
        manual=URLSession(configuration:Self.configuration(identifier:"com.verabot.library.\(scope).manual",manual:true),delegate:self,delegateQueue:nil)
        for session in [automatic!,manual!] {
            session.getAllTasks { [weak self] tasks in
                Task { @MainActor in
                    guard let self,self.valid else { tasks.forEach { $0.cancel() };return }
                    for task in tasks {
                        guard let text=task.taskDescription,let data=text.data(using:.utf8),let job=try? JSONDecoder().decode(LibraryDownloadJob.self,from:data),job.scope==self.scope else { task.cancel();continue }
                        self.jobs[job.item.id]=job;self.active.insert(job.item.id)
                    }
                    self.revision += 1
                }
            }
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let wifi=path.status == .satisfied && path.usesInterfaceType(.wifi) && !path.isExpensive && !path.isConstrained
            Task { @MainActor in
                guard let self,self.valid else { return }; self.isWiFi=wifi
                if !wifi { self.cancelAutomatic() } else { self.enqueue(items:self.items,mode:.automaticWiFi) }
            }
        }
        monitor.start(queue:DispatchQueue(label:"com.verabot.library.network"))
    }
    var downloadedCount: Int { items.filter { files.localURL(item:$0) != nil }.count }
    var remainingBytes: Int64 { items.filter { files.localURL(item:$0) == nil && $0.availability == "available" }.reduce(0) { $0+Int64($1.bytes) } }
    func localURL(id: String) -> URL? { guard valid,let item=items.first(where:{$0.id==id}) else { return nil };return files.localURL(item:item) }
    func updateCatalog(_ list: [VeraBotCore.LibraryItem], complete: Bool) {
        guard valid,sessionIsCurrent() else { return }
        items=list
        if complete {
            try? files.reconcile(items:list)
            let allowed=Set(list.map(\.id))
            for id in active where !allowed.contains(id) { cancel(id:id) }
        }
        revision += 1;enqueue(items:list,mode:.automaticWiFi)
    }
    func enqueue(items list: [VeraBotCore.LibraryItem], mode: LibraryDownloadMode) {
        guard valid,sessionIsCurrent(),LibraryDownloadPolicy.mayStart(mode:mode,isWiFi:isWiFi,paused:paused) else { return }
        var started=false
        for item in list where item.availability == "available" && files.localURL(item:item) == nil && !active.contains(item.id) {
            if mode == .automaticWiFi && failures.contains(item.id) { continue }
            errors[item.id]=nil;failures.remove(item.id)
            if let available=(try? files.root.deletingLastPathComponent().resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage,available<Int64(item.bytes) {
                errors[item.id]="设备存储空间不足，下载已暂停";paused=true;break
            }
            let job=LibraryDownloadJob(item:item,mode:mode,scope:scope,identifier:UUID().uuidString)
            var request=URLRequest(url:api.baseURL.appending(path:"/api/library/items/\(item.id)/content"))
            request.setValue("Bearer \(api.token ?? "")",forHTTPHeaderField:"Authorization")
            request.timeoutInterval=120
            let task=(mode == .automaticWiFi ? automatic! : manual!).downloadTask(with:request)
            task.taskDescription=String(data:(try? JSONEncoder().encode(job)) ?? Data(),encoding:.utf8)
            try? store.set(key:"download.job.\(item.id)",value:task.taskDescription ?? "")
            jobs[item.id]=job;active.insert(item.id);task.resume();started=true
        }
        if started { revision += 1 }
    }
    func prepare(id: String, userInitiated: Bool) async -> URL? {
        if let url=localURL(id:id) { return url }
        guard valid,sessionIsCurrent() else { return nil }
        if !items.contains(where:{$0.id==id}),let item=try? await api.libraryItem(id:id),valid,sessionIsCurrent() { items.append(item) }
        if let item=items.first(where:{$0.id==id}) { enqueue(items:[item],mode:userInitiated ? .manualCellularAllowed:.automaticWiFi) }
        return localURL(id:id)
    }
    func clearDownloaded(item: VeraBotCore.LibraryItem) {
        paused=true;cancel(id:item.id);try? files.remove(item:item);revision += 1
    }
    private func cancel(id: String) {
        for session in [automatic!,manual!] { session.getAllTasks { tasks in tasks.filter { $0.taskDescription?.contains("\"\(id)\"") == true }.forEach { $0.cancel() } } }
        active.remove(id);jobs[id]=nil;try? store.set(key:"download.job.\(id)",value:"")
    }
    private func cancelAutomatic() {
        automatic.getAllTasks { $0.forEach { $0.cancel() } }
    }
    func invalidateSession() {
        valid=false;monitor.cancel();automatic.invalidateAndCancel();manual.invalidateAndCancel();active=[];jobs=[:];items=[];revision += 1
    }
    private func completed(job: LibraryDownloadJob, temp: URL?, status: Int, error: String?) {
        defer { if let temp { try? FileManager.default.removeItem(at:temp) } }
        guard valid,sessionIsCurrent(),job.scope==scope else { return }
        guard let persisted=try? store.value(key:"download.job.\(job.item.id)"),let data=persisted.data(using:.utf8),let saved=try? JSONDecoder().decode(LibraryDownloadJob.self,from:data),saved.identifier==job.identifier else { return }
        try? store.set(key:"download.job.\(job.item.id)",value:"")
        active.remove(job.item.id);jobs[job.item.id]=nil
        guard items.contains(where:{$0.id==job.item.id && $0.resourceVersion==job.item.resourceVersion}) else { return }
        if status == 200,let temp {
            do { try files.commit(tempURL:temp,item:job.item);errors[job.item.id]=nil;failures.remove(job.item.id) }
            catch { errors[job.item.id]=error.localizedDescription;failures.insert(job.item.id)
                if (error as NSError).code == NSFileWriteOutOfSpaceError { paused=true }
            }
        } else if status != -999 {
            errors[job.item.id]=error ?? (status == 401 ? "登录状态已过期，请刷新后重试":"下载失败，请重试")
            failures.insert(job.item.id)
        }
        revision += 1
        if status == -999 { enqueue(items:items,mode:.automaticWiFi) }
    }
}

extension LibraryDownloadCoordinator: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let text=downloadTask.taskDescription,let data=text.data(using:.utf8),let job=try? JSONDecoder().decode(LibraryDownloadJob.self,from:data) else { return }
        let temporary=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".download")
        let status=(downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        do {
            try FileManager.default.moveItem(at:location,to:temporary)
            Task { @MainActor in completed(job:job,temp:temporary,status:status,error:nil) }
        } catch { Task { @MainActor in completed(job:job,temp:nil,status:status,error:error.localizedDescription) } }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error,let text=task.taskDescription,let data=text.data(using:.utf8),let job=try? JSONDecoder().decode(LibraryDownloadJob.self,from:data) else { return }
        let status=(error as NSError).code
        Task { @MainActor in completed(job:job,temp:nil,status:status,error:error.localizedDescription) }
    }
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in LibraryBackgroundEvents.finish(identifier:session.configuration.identifier) }
    }
}

@MainActor enum LibraryBackgroundEvents {
    static var completions: [String:()->Void] = [:]
    static func finish(identifier: String?) { if let identifier { completions.removeValue(forKey:identifier)?() } }
}
final class LibraryAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application:UIApplication, handleEventsForBackgroundURLSession identifier:String,completionHandler:@escaping ()->Void) {
        LibraryBackgroundEvents.completions[identifier]=completionHandler
    }
}
