import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import VeraBotCore

struct LibraryUploadSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let botID: Int?
    let onComplete: () -> Void
    @State private var chooseFile = false
    @State private var photo: PhotosPickerItem?
    @State private var data: Data?
    @State private var filename = ""
    @State private var mime = ""
    @State private var requestKey = UUID().uuidString
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Button("选择文件",systemImage:"doc") { chooseFile=true }
                PhotosPicker(selection:$photo,matching:.images) { Label("选择图片",systemImage:"photo") }
                if !filename.isEmpty { Text(filename) }
            }
            Section {
                Text(botID == nil ? "资料会保存到全局资料库，之后可以关联 Bot。":"上传后当前 Bot 可以主动检索和读取此资料。")
                Text("支持现有文件与图片格式，单个原件最多 10 MB。").font(.footnote).foregroundStyle(.secondary)
            }
            if let error { Section { Text(error).foregroundStyle(.secondary) } }
        }
        .navigationTitle("上传资料").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
            ToolbarItem(placement:.confirmationAction) { Button(busy ? "上传中…":"上传") { Task { await send() } }.disabled(data==nil || busy) }
        }
        .fileImporter(isPresented:$chooseFile,allowedContentTypes:[.data],allowsMultipleSelection:false) { result in
            do {
                guard let url=try result.get().first else { return }
                let allowed=url.startAccessingSecurityScopedResource();defer { if allowed { url.stopAccessingSecurityScopedResource() } }
                let bytes=(try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
                guard bytes<=AttachmentLimits.maxBytes else { throw CocoaError(.fileReadTooLarge) }
                let value=try Data(contentsOf:url);guard value.count<=AttachmentLimits.maxBytes else { throw CocoaError(.fileReadTooLarge) }
                data=value;filename=url.lastPathComponent;mime=UTType(filenameExtension:url.pathExtension)?.preferredMIMEType ?? "application/octet-stream";requestKey=UUID().uuidString;error=nil
            } catch { self.error=error.localizedDescription }
        }
        .onChange(of:photo) { _,item in
            Task {
                guard let item,let raw=try? await item.loadTransferable(type:Data.self) else { return }
                let gif=AttachmentLimits.isGIF(raw)
                let value=gif ? raw : (UIImage(data:raw)?.jpegData(compressionQuality:0.85) ?? raw)
                guard value.count<=AttachmentLimits.maxBytes else { error="图片超过 10 MB";return }
                data=value;mime=gif ? "image/gif":"image/jpeg";filename=gif ? "图片.gif":"图片.jpg";requestKey=UUID().uuidString;error=nil
            }
        }
        .interactiveDismissDisabled(busy)
    }
    private func send() async {
        guard let data,let repo=app.libraryRepository else { return }
        busy=true;defer { busy=false }
        do { _ = try await repo.upload(data:data,filename:filename,mime:mime,botID:botID,requestKey:requestKey);onComplete();dismiss() }
        catch { self.error=error.localizedDescription }
    }
}
