import XCTest
@testable import VeraBot

final class LibraryDownloadIntegrationTests: XCTestCase {
    func testAutomaticSessionCannotUseCellularWhileManualCan() {
        let automatic=LibraryDownloadCoordinator.configuration(identifier:"library.test.auto",manual:false)
        let manual=LibraryDownloadCoordinator.configuration(identifier:"library.test.manual",manual:true)
        XCTAssertFalse(automatic.allowsCellularAccess)
        XCTAssertFalse(automatic.allowsExpensiveNetworkAccess)
        XCTAssertFalse(automatic.allowsConstrainedNetworkAccess)
        XCTAssertTrue(manual.allowsCellularAccess)
        XCTAssertNil(manual.identifier, "A manual tap must not wait for the background download service")
        XCTAssertFalse(manual.waitsForConnectivity)
        XCTAssertNotNil(automatic.identifier)
    }
}
