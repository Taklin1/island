import Foundation

/// Fetches the latest published release tag (issue #91, ADR-0010). Seam in
/// the `TerminalResponder.live` shape: a closure-property struct the app
/// wires with `.live` (GitHub `releases/latest`, public API, no auth — the
/// repo is public, ADR-0010 prerequisite), while the agentic FP injects a
/// served fixture by building an `UpdateFetcher` over another URL. The JSON
/// parsing is a pure function tested against the captured real responses.
public struct UpdateFetcher: Sendable {
    /// `GET releases/latest`: the latest non-draft, non-prerelease Release.
    /// 404 while no Release has ever been published (real state captured
    /// 2026-07-20) — mapped to nil like every other failure.
    public static let releasesLatestURLString =
        "https://api.github.com/repos/Taklin1/island/releases/latest"

    /// Returns the raw `tag_name` (e.g. `"v0.1.25"`) or nil on any failure.
    /// Nil is always silent: the gate maps it to `.unknown`.
    public var fetchLatestTag: @Sendable () async -> String?

    public init(fetchLatestTag: @escaping @Sendable () async -> String?) {
        self.fetchLatestTag = fetchLatestTag
    }

    public static let live = UpdateFetcher {
        await fetchTag(fromURLString: releasesLatestURLString)
    }

    /// Shared mechanics for `.live` and the FP feed override: GET the URL,
    /// tolerate every failure (offline, timeout, non-200, bad JSON) as nil.
    public static func fetchTag(fromURLString urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            // file:// feeds (FP fixtures) have no HTTPURLResponse — only gate
            // on the status code when there is one.
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return nil
            }
            return parseTag(fromReleasesLatestJSON: data)
        } catch {
            return nil
        }
    }

    /// Pure: reads `tag_name` out of a `releases/latest` body. The 404 body
    /// (`{"message": "Not Found", …}`) has no `tag_name`, so it is nil by the
    /// same path as truncated or unexpected JSON.
    public static func parseTag(fromReleasesLatestJSON data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
            let release = object as? [String: Any],
            let tag = release["tag_name"] as? String,
            !tag.isEmpty
        else { return nil }
        return tag
    }
}
