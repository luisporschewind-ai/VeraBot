import Foundation
import CryptoKit
import VeraBotCore

/// Immutable original files scoped to a server/account directory, never a shared URL cache.
public final class LibraryFileStore: Sendable {
    public let root: URL
    public init(root: URL) { self.root=root }
    private func fileURL(item: LibraryItem) -> URL {
        let identity=Data((item.id+":"+item.resourceVersion).utf8)
        let hash=SHA256.hash(data:identity).map { String(format:"%02x",$0) }.joined()
        let rawExt=(item.name as NSString).pathExtension.lowercased()
        let safeExt=rawExt.count <= 10 && rawExt.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } ? rawExt : ""
        let ext=safeExt.isEmpty ? (item.mime == "image/png" ? "png" : item.mime == "image/gif" ? "gif" : item.isImage ? "jpg" : "bin") : safeExt
        return root.appendingPathComponent(hash).appendingPathExtension(ext)
    }
    public func localURL(item: LibraryItem) -> URL? {
        let url=fileURL(item:item)
        guard let attrs=try? FileManager.default.attributesOfItem(atPath:url.path),
              (attrs[.size] as? NSNumber)?.intValue == item.bytes else { return nil }
        return url
    }
    @discardableResult public func commit(tempURL: URL, item: LibraryItem) throws -> URL {
        let handle=try FileHandle(forReadingFrom:tempURL);defer { try? handle.close() }
        var hash=SHA256();var size=0
        while let chunk=try handle.read(upToCount:1024*1024), !chunk.isEmpty { size += chunk.count;hash.update(data:chunk) }
        let checksum=hash.finalize().map { String(format:"%02x",$0) }.joined()
        guard size == item.bytes, checksum == item.sha256 else { throw URLError(.cannotDecodeContentData) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        var folder=root;var values=URLResourceValues();values.isExcludedFromBackup=true;try folder.setResourceValues(values)
        let destination=fileURL(item:item)
        let staged=root.appendingPathComponent(UUID().uuidString+".partial")
        try FileManager.default.copyItem(at:tempURL,to:staged)
        defer { try? FileManager.default.removeItem(at:staged) }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:staged.path)
        #endif
        if FileManager.default.fileExists(atPath:destination.path) {
            _ = try FileManager.default.replaceItemAt(destination,withItemAt:staged)
        } else { try FileManager.default.moveItem(at:staged,to:destination) }
        return destination
    }
    public func remove(item: LibraryItem) throws {
        let url=fileURL(item:item)
        if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) }
    }
    public func reconcile(items: [LibraryItem]) throws {
        let expected=Set(items.map { fileURL(item:$0).lastPathComponent })
        for url in (try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? [] {
            if !expected.contains(url.lastPathComponent) { try FileManager.default.removeItem(at:url) }
        }
    }
}
