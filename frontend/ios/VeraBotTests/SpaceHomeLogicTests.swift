import XCTest
@testable import VeraBot

final class SpaceHomeLogicTests: XCTestCase {
    func testActivityPriorityTravelOverTaskOverIdle() {
        XCTAssertEqual(
            SpaceHomeLogic.activity(travelingCity: "京都", hasActiveTask: true),
            .traveling(city: "京都")
        )
        XCTAssertEqual(
            SpaceHomeLogic.activity(travelingCity: nil, hasActiveTask: true),
            .onTask
        )
        XCTAssertEqual(
            SpaceHomeLogic.activity(travelingCity: nil, hasActiveTask: false),
            .idle
        )
    }

    func testActivityLabels() {
        XCTAssertEqual(SpaceBotActivity.traveling(city: "巴黎").label, "旅行中 · 巴黎")
        XCTAssertEqual(SpaceBotActivity.onTask.label, "正在执行任务")
        XCTAssertEqual(SpaceBotActivity.idle.label, "空闲")
    }

    func testContinuePrefersTripThenTask() {
        XCTAssertEqual(
            SpaceHomeLogic.continueKind(hasActiveTrip: true, hasActiveTask: true),
            .trip
        )
        XCTAssertEqual(
            SpaceHomeLogic.continueKind(hasActiveTrip: false, hasActiveTask: true),
            .task
        )
        XCTAssertNil(SpaceHomeLogic.continueKind(hasActiveTrip: false, hasActiveTask: false))
    }

    func testActiveBotTaskStatuses() {
        XCTAssertTrue(SpaceHomeLogic.isActiveBotTask(statusKey: "pending", needsUser: false))
        XCTAssertTrue(SpaceHomeLogic.isActiveBotTask(statusKey: "running", needsUser: false))
        XCTAssertTrue(SpaceHomeLogic.isActiveBotTask(statusKey: "needs_user", needsUser: false))
        XCTAssertTrue(SpaceHomeLogic.isActiveBotTask(statusKey: "done", needsUser: true))
        XCTAssertFalse(SpaceHomeLogic.isActiveBotTask(statusKey: "done", needsUser: false))
        XCTAssertFalse(SpaceHomeLogic.isActiveBotTask(statusKey: "failed", needsUser: false))
        XCTAssertFalse(SpaceHomeLogic.isActiveBotTask(statusKey: nil, needsUser: false))
    }
}
