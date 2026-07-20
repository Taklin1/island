import Foundation
import Testing
import IslandStore

/// `parseTag` against the real `releases/latest` responses — no network, no
/// invented schema (issue #91). Both fixtures were captured on 2026-07-20 from
/// `GET https://api.github.com/repos/Taklin1/island/releases/latest` (public
/// repo, no auth), minutes apart: first while the temporary FP #89 test
/// release existed, then the real 404 right after its deletion.
struct UpdateFetcherTests {
    @Test("parseTag reads tag_name from the real releases/latest body (capture 2026-07-20)")
    func parseTagReadsRealResponse() {
        // Trimmed excerpt of the real 200 response captured 2026-07-20
        // 21:17 UTC (release since deleted): the author object and the
        // assets/body/date fields are elided, every kept value is verbatim.
        let fixture = Data("""
        {
          "url": "https://api.github.com/repos/Taklin1/island/releases/356998020",
          "assets_url": "https://api.github.com/repos/Taklin1/island/releases/356998020/assets",
          "upload_url": "https://uploads.github.com/repos/Taklin1/island/releases/356998020/assets{?name,label}",
          "html_url": "https://github.com/Taklin1/island/releases/tag/v0.1.23-test89",
          "id": 356998020,
          "node_id": "RE_kwDOTdJVls4VR1uE",
          "tag_name": "v0.1.23-test89",
          "target_commitish": "epic/85-distribution-updates",
          "name": "TEST release FP #89 (temporary)",
          "draft": false,
          "immutable": false
        }
        """.utf8)

        #expect(UpdateFetcher.parseTag(fromReleasesLatestJSON: fixture) == "v0.1.23-test89")
    }

    @Test("parseTag on the real 404 body (no release published) is nil")
    func parseTagOnRealNotFoundBodyIsNil() {
        // Verbatim 404 body captured 2026-07-20 21:18 UTC, right after the
        // temporary test release was deleted — the repo's actual state until
        // the first real Release (#89 CI) ships.
        let fixture = Data("""
        {
          "message": "Not Found",
          "documentation_url": "https://docs.github.com/rest/releases/releases#get-the-latest-release",
          "status": "404"
        }
        """.utf8)

        #expect(UpdateFetcher.parseTag(fromReleasesLatestJSON: fixture) == nil)
    }

    @Test("parseTag on truncated or empty data is nil, never a crash")
    func parseTagOnGarbageIsNil() {
        #expect(UpdateFetcher.parseTag(fromReleasesLatestJSON: Data()) == nil)
        #expect(UpdateFetcher.parseTag(fromReleasesLatestJSON: Data("{\"tag_na".utf8)) == nil)
        #expect(UpdateFetcher.parseTag(fromReleasesLatestJSON: Data("{\"tag_name\": \"\"}".utf8)) == nil)
        #expect(UpdateFetcher.parseTag(fromReleasesLatestJSON: Data("[1, 2, 3]".utf8)) == nil)
    }
}
