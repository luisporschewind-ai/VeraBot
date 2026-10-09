import XCTest
@testable import VeraBotNetworking

final class RememberedLoginTests: XCTestCase {
    func testCredentialsPersistReplaceAndRemainServerScoped() throws {
        let service = "com.verabot.tests.login.\(UUID().uuidString)"
        let store = RememberedLoginStore(service: service)
        defer { store.remove(server: "https://one.example/api"); store.remove(server: "https://two.example/api") }
        XCTAssertTrue(store.save(.init(identifier: "first@example.com", password: "first-secret", isPhone: false), server: "https://one.example/api/"))
        let reopened = RememberedLoginStore(service: service)
        XCTAssertEqual(reopened.load(server: "https://one.example/api")?.identifier, "first@example.com")
        XCTAssertEqual(reopened.load(server: "https://one.example/api")?.password, "first-secret")
        XCTAssertNil(reopened.load(server: "https://two.example/api"))
        XCTAssertTrue(store.save(.init(identifier: "+8613800000000", password: "replacement", isPhone: true), server: "https://one.example/api"))
        XCTAssertEqual(reopened.load(server: "https://one.example/api")?.password, "replacement")
        XCTAssertEqual(reopened.load(server: "https://one.example/api")?.isPhone, true)
        XCTAssertTrue(store.remove(server: "https://one.example/api"))
        XCTAssertNil(reopened.load(server: "https://one.example/api"))
    }
}
