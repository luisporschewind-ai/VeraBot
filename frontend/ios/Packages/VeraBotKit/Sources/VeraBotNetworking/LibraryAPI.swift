import Foundation
import VeraBotCore

public protocol LibraryAPI: Sendable {
    func libraryPage(cursor: String?) async throws -> LibraryPage
    func librarySearch(query: String, botID: Int?) async throws -> [LibraryItem]
    func libraryItem(id: String) async throws -> LibraryItem
    func libraryUpload(data: Data, filename: String, mime: String, botID: Int?, requestKey: String) async throws -> LibraryItem
    func libraryLink(id: String, botID: Int) async throws
    func libraryUnlink(id: String, botID: Int) async throws
    func libraryDelete(id: String) async throws
}
public extension LibraryAPI {
    func librarySearch(query: String, botID: Int?) async throws -> [LibraryItem] { throw URLError(.unsupportedURL) }
    func libraryItem(id: String) async throws -> LibraryItem { throw URLError(.unsupportedURL) }
    func libraryUpload(data: Data, filename: String, mime: String, botID: Int?, requestKey: String) async throws -> LibraryItem { throw URLError(.unsupportedURL) }
    func libraryLink(id: String, botID: Int) async throws { throw URLError(.unsupportedURL) }
    func libraryUnlink(id: String, botID: Int) async throws { throw URLError(.unsupportedURL) }
    func libraryDelete(id: String) async throws { throw URLError(.unsupportedURL) }
}
