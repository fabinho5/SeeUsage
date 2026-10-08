import Foundation

enum AppUpdateAvailability: Equatable {
    case feedAvailable
    case upToDate
    case notPublished
    case manualRelease(version: String, url: URL)
}

/// A missing appcast is expected before the first updater-enabled release.
/// GitHub metadata may explain that state, but never authorizes installation:
/// Sparkle still verifies the signed feed and archive for every in-app update.
struct ReleaseAvailabilityChecker {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    let feedURL: URL
    let repository: String
    let currentVersion: String
    let load: Loader

    init(feedURL: URL, repository: String, currentVersion: String, load: @escaping Loader = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CheckError.invalidResponse }
        return (data, response)
    }) {
        self.feedURL = feedURL
        self.repository = repository
        self.currentVersion = currentVersion
        self.load = load
    }

    func check() async throws -> AppUpdateAvailability {
        var request = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "HEAD"
        let (_, response) = try await load(request)
        if (200..<300).contains(response.statusCode) || response.statusCode == 405 {
            return .feedAvailable
        }
        guard response.statusCode == 404 else { throw CheckError.httpStatus(response.statusCode) }

        let apiURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        request = URLRequest(url: apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, releaseResponse) = try await load(request)
        if releaseResponse.statusCode == 404 { return .notPublished }
        guard releaseResponse.statusCode == 200 else { throw CheckError.httpStatus(releaseResponse.statusCode) }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.draft, !release.prerelease else { return .notPublished }
        let latestVersion = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        let latest = try Self.versionComponents(latestVersion)
        let current = try Self.versionComponents(currentVersion)
        guard current.lexicographicallyPrecedes(latest) else { return .upToDate }
        guard let url = URL(string: "https://github.com/\(repository)/releases/tag/\(release.tagName)") else {
            throw CheckError.invalidResponse
        }
        return .manualRelease(version: latestVersion, url: url)
    }

    private static func versionComponents(_ version: String) throws -> [Int] {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw CheckError.invalidResponse }
        return try parts.map { part in
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else {
                throw CheckError.invalidResponse
            }
            return number
        }
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", draft, prerelease
        }
    }

    enum CheckError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)
        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "The release information could not be read."
            case .httpStatus(let status): return "The update server returned HTTP \(status)."
            }
        }
    }
}
