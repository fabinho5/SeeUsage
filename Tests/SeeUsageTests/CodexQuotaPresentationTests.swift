import XCTest
@testable import SeeUsage

final class CodexQuotaPresentationTests: XCTestCase {
    func testMainPairPrecedesReserveEvenWhenReserveHasSameOrShorterDuration() {
        let session = window("session", duration: 300, scope: "codex")
        let weekly = window("weekly", duration: 10_080, scope: "codex")
        let reserve = window("reserve", duration: 10_080, scope: "base_model_inference")
        let reserveShort = window("reserve-short", duration: 300, scope: "base_model_inference")
        let input = [reserve, weekly, reserveShort, session]
        XCTAssertEqual(CodexQuotaPresentation.ordered(input).map(\.id), ["session", "weekly", "reserve-short", "reserve"])
        XCTAssertEqual(Set(input), Set(CodexQuotaPresentation.ordered(input)))
    }

    func testLegacyMainScopeAndUnknownBucketsKeepTheirIdentity() {
        let weekly = window("weekly", duration: 10_080, scope: nil)
        let session = window("session", duration: 300, scope: nil)
        let extra = window("extra", duration: 300, scope: "other-model")
        XCTAssertEqual(CodexQuotaPresentation.ordered([extra, weekly, session]).map(\.id), ["session", "weekly", "extra"])
        XCTAssertFalse(CodexQuotaPresentation.isReserve(extra))
    }

    func testParserKeepsMainWeeklyBeforeGPTReserve() {
        let json = """
        {"id":2,"result":{"rateLimitsByLimitId":{"base_model_inference":{"primary":{"usedPercent":0,"windowDurationMins":10080}},"codex":{"primary":{"usedPercent":3,"windowDurationMins":300},"secondary":{"usedPercent":13,"windowDurationMins":10080}}}}}
        """
        let result = CodexClient.parse(output: Data(json.utf8), profileID: UUID())
        XCTAssertNil(result.error)
        XCTAssertEqual(result.windows.map(\.scope), ["codex", "codex", "base_model_inference"])
        XCTAssertEqual(result.windows.map(\.remainingPercent), [97, 87, 100])
        XCTAssertEqual(result.windows.map(\.durationMinutes), [300, 10_080, 10_080])
    }

    private func window(_ id: String, duration: Int, scope: String?) -> UsageWindow {
        UsageWindow(id: id, label: "quota", remainingPercent: 80, durationMinutes: duration, scope: scope)
    }
}
