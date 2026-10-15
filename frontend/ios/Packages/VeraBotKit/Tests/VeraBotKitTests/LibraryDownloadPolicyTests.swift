import Foundation
import Testing
import VeraBotCore
import VeraBotData
import CryptoKit

@Test func libraryAutomaticDownloadRequiresWiFiButManualAllowsCellular() {
    #expect(!LibraryDownloadPolicy.mayStart(mode:.automaticWiFi, isWiFi:false, paused:false))
    #expect(LibraryDownloadPolicy.mayStart(mode:.manualCellularAllowed, isWiFi:false, paused:true))
    #expect(!LibraryDownloadPolicy.mayStart(mode:.automaticWiFi, isWiFi:true, paused:true))
}
@Test func corruptLibraryOriginalNeverBecomesReady() throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let files=LibraryFileStore(root:root)
    let temp=root.appendingPathComponent("incoming")
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    try Data("bad".utf8).write(to:temp)
    #expect(throws:(any Error).self) { try files.commit(tempURL:temp,item:libraryFixture()) }
    #expect(files.localURL(item:libraryFixture()) == nil)
}
@Test func libraryOriginalIsReusedAfterRestartAndDeletionRemovesIt() throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let data=Data("abc".utf8), hash=SHA256.hash(data:Data("abc".utf8)).map { String(format:"%02x",$0) }.joined()
    let item=LibraryItem(id:"att_safe",kind:"file",name:"report.txt",mime:"text/plain",bytes:3,sha256:hash,resourceVersion:hash,createdAt:"",revision:1,availability:"available",textStatus:"ready",botIDs:[],sources:[])
    let files=LibraryFileStore(root:root)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let temp=root.appendingPathComponent("incoming");try data.write(to:temp)
    let url=try files.commit(tempURL:temp,item:item)
    #expect(try Data(contentsOf:url) == data)
    let reopened=LibraryFileStore(root:root)
    #expect(reopened.localURL(item:item) != nil)
    try reopened.remove(item:item)
    #expect(files.localURL(item:item) == nil)
}
