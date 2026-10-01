import Foundation
import Testing
@testable import VeraBotCore

// QUOTA-03：设置 › 用量 行右侧「已用 N%」。
// JSON 与后端 services/quota.py::compute_quota 的输出同形（键名由后端 MA-25 契约测试反向断言）。
private func quotaJSON(today: Int, quota: Int) -> Data {
    Data(##"""
    {"model":"deepseek-chat","daily_token_quota":\##(quota),
     "today":{"requests":3,"prompt_tokens":1,"completion_tokens":2,"total_tokens":\##(today)},
     "total":{"requests":9,"prompt_tokens":1,"completion_tokens":2,"total_tokens":99999},
     "per_bot":[],"daily":[{"date":"10-01","tokens":\##(today)}],"delegations":0,
     "transcribe":{"today":{"requests":0,"seconds":0,"chars":0},"total":{"requests":0,"seconds":0,"chars":0}}}
    """##.utf8)
}

private func decode(today: Int, quota: Int) throws -> Quota {
    try JSONDecoder().decode(Quota.self, from: quotaJSON(today: today, quota: quota))
}

@Test func quotaUsedPercentRoundsToInteger() throws {
    #expect(try decode(today: 74_000, quota: 200_000).usedPercent == 37)          // 37.0
    #expect(try decode(today: 74_999, quota: 200_000).usedPercent == 37)          // 37.4995
    #expect(try decode(today: 75_000, quota: 200_000).usedPercent == 38)          // 37.5 → 38
    #expect(try decode(today: 74_000, quota: 200_000).usedPercentText == "已用 37%")
}

@Test func quotaUsedPercentEdges() throws {
    #expect(try decode(today: 0, quota: 200_000).usedPercentText == "已用 0%")
    #expect(try decode(today: 200_000, quota: 200_000).usedPercent == 100)
    #expect(try decode(today: 500, quota: 400).usedPercent == 125)                // 超额如实显示，不截断
}

@Test func quotaWithoutValidLimitShowsNothing() throws {
    #expect(try decode(today: 100, quota: 0).usedPercent == nil)
    #expect(try decode(today: 100, quota: 0).usedPercentText == nil)
}

@Test func quotaUsesTotalTokensOfToday() throws {
    // 分子是 today.total_tokens，不是累计 total.total_tokens
    let q = try decode(today: 20_000, quota: 200_000)
    #expect(q.total.totalTokens == 99_999)
    #expect(q.usedPercent == 10)
}
