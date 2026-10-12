import Foundation
import Testing
@testable import VeraBotCore

private func webTrace(name: String = "web_search", sources: String) throws -> ToolTrace {
    try JSONDecoder().decode(ToolTrace.self, from: Data("""
    {"id":"t1","name":"\(name)","args":{},"result":{"sources":\(sources)}}
    """.utf8))
}

@Test func webSourcesDecodeRealTraceAndPreferReadEvidence() throws {
    let search = try webTrace(sources: """
    [{"query_id":"q1","result_id":"1","citation_number":1,"title":"官方发布","url":"https://example.com/news",
    "publisher":"example.com","published_at":"2026-10-11","queried_at":"2026-10-11T12:00:00+00:00",
    "fetched_at":"2026-10-11T11:58:00+00:00","cache_hit":true,"content":"摘要"}]
    """)
    let read = try webTrace(name: "web_read_result", sources: """
    [{"query_id":"q1","result_id":"1","citation_number":1,"title":"官方发布","url":"https://example.com/news",
    "publisher":"example.com","published_at":"2026-10-11","queried_at":"2026-10-11T12:01:00+00:00",
    "fetched_at":"2026-10-11T12:01:00+00:00","cache_hit":false,"content":"正文"}]
    """)
    let sources = WebSource.sources(from: [search, read])
    #expect(sources.count == 1)
    #expect(sources.first?.title == "官方发布")
    #expect(sources.first?.publishedAt == "2026-10-11")
    #expect(sources.first?.queriedAt == "2026-10-11T12:01:00+00:00")
    #expect(sources.first?.cacheHit == false)
    #expect(sources.first?.citationNumber == 1)
}

@Test func webSourcesRejectUnsafeOrMalformedLinksAndOldTraces() throws {
    for link in ["javascript:alert(1)", "file:///etc/passwd", "https://localhost/a", "https://10.0.0.1/a",
                 "https://user:pass@example.com/a", "https://example.com:8080/a", "https://a.local/a"] {
        let trace = try webTrace(sources: """
        [{"query_id":"q","result_id":"1","title":"资料","url":"\(link)"}]
        """)
        #expect(WebSource.sources(from: [trace]).isEmpty)
    }
    let empty = try webTrace(sources: "[]")
    let weather = try webTrace(name: "get_weather", sources: """
    [{"query_id":"q","result_id":"1","title":"资料","url":"https://example.com"}]
    """)
    let old = try JSONDecoder().decode(ToolTrace.self, from: Data(#"{"id":"t","name":"get_weather","args":{},"result":{"source":"Open-Meteo"}}"#.utf8))
    #expect(WebSource.sources(from: [empty, weather, old]).isEmpty)
}

@Test func webSourcesKeepSeparateQueryIdentitiesAndOmitUnknownDates() throws {
    let trace = try webTrace(sources: """
    [{"query_id":"q1","result_id":"1","title":"资料","url":"https://example.com/a","published_at":null},
    {"query_id":"q2","result_id":"2","title":"资料2","url":"https://example.com/b"}]
    """)
    let sources = WebSource.sources(from: [trace])
    #expect(sources.count == 2)
    #expect(sources[0].publishedAt == nil)
    #expect(sources[0].id != sources[1].id)
}
