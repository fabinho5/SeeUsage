import XCTest
@testable import SeeUsage

final class ReleaseAvailabilityCheckerTests: XCTestCase {
    private let feed = URL(string: "https://github.com/example/SeeUsage/releases/latest/download/appcast.xml")!

    func testAvailableFeedUsesSparkleWithoutQueryingUnsignedReleaseMetadata() async throws {
        let http = StubHTTP(statuses: [200])
        let result = try await checker(http).check()
        XCTAssertEqual(result, .feedAvailable)
        let requests = await http.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.httpMethod, "HEAD")
    }

    func testServerWithoutHEADSupportStillUsesSignedSparkleFeed() async throws {
        let result = try await checker(StubHTTP(statuses: [405])).check()
        XCTAssertEqual(result, .feedAvailable)
    }

    func testMissingFeedAndNoReleasesIsNormalEmptyState() async throws {
        let http = StubHTTP(statuses: [404, 404])
        let result = try await checker(http).check()
        XCTAssertEqual(result, .notPublished)
        let requests = await http.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["HEAD", "GET"])
        XCTAssertEqual(requests.last?.url?.absoluteString, "https://api.github.com/repos/example/SeeUsage/releases/latest")
    }

    func testMissingFeedWithSameOrOlderReleaseIsUpToDate() async throws {
        for tag in ["v1.1.0", "v1.1.1", "1.0.9"] {
            let result = try await checker(StubHTTP(statuses: [404, 200], tag: tag)).check()
            XCTAssertEqual(result, .upToDate, tag)
        }
    }

    func testNewerReleaseWithoutFeedOffersManualReleaseOnly() async throws {
        let result = try await checker(StubHTTP(statuses: [404, 200], tag: "v1.2.0")).check()
        XCTAssertEqual(result, .manualRelease(version: "1.2.0", url: URL(string: "https://github.com/example/SeeUsage/releases/tag/v1.2.0")!))
    }

    func testVersionComparisonIsNumericAndPrereleasesAreExcluded() async throws {
        let result = try await checker(StubHTTP(statuses: [404, 200], tag: "v1.10.0"), version: "1.9.0").check()
        XCTAssertEqual(result, .manualRelease(version: "1.10.0", url: URL(string: "https://github.com/example/SeeUsage/releases/tag/v1.10.0")!))
        let prerelease = try await checker(StubHTTP(statuses: [404, 200], tag: "v2.0.0-beta", prerelease: true)).check()
        XCTAssertEqual(prerelease, .notPublished)
    }

    func testNetworkServerAndMalformedReleaseErrorsAreNotReportedAsUpToDate() async throws {
        for http in [StubHTTP(statuses: [503]), StubHTTP(statuses: [404, 403]),
                     StubHTTP(statuses: [404, 200], tag: "invalid"), StubHTTP(statuses: [], offline: true)] {
            do {
                _ = try await checker(http).check()
                XCTFail("Failed checks must not claim the app is up to date")
            } catch {}
        }
    }

    private func checker(_ http: StubHTTP, version: String = "1.1.1") -> ReleaseAvailabilityChecker {
        ReleaseAvailabilityChecker(feedURL: feed, repository: "example/SeeUsage", currentVersion: version,
                                   load: { try await http.load($0) })
    }
}

private actor StubHTTP {
    var requests: [URLRequest] = []
    let statuses: [Int]
    let tag: String
    let prerelease: Bool
    let offline: Bool
    init(statuses: [Int], tag: String = "v1.1.0", prerelease: Bool = false, offline: Bool = false) {
        self.statuses = statuses
        self.tag = tag
        self.prerelease = prerelease
        self.offline = offline
    }
    func load(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        if offline { throw URLError(.notConnectedToInternet) }
        guard requests.count < statuses.count else { throw URLError(.badServerResponse) }
        let status = statuses[requests.count]
        requests.append(request)
        let data = try JSONSerialization.data(withJSONObject: ["tag_name": tag, "draft": false, "prerelease": prerelease])
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}
