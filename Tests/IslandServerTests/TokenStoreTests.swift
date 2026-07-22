import Foundation
import Testing
import IslandServer

struct TokenStoreTests {
    @Test("First load generates a token file with 0600 permissions, later loads reuse it")
    func generatesThenReusesToken() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-token-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try TokenStore.loadOrCreate(at: url)
        let second = try TokenStore.loadOrCreate(at: url)

        #expect(!first.isEmpty)
        #expect(first == second)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.int16Value
        #expect(permissions == 0o600)
    }

    @Test("An existing token file is read as-is, trimmed")
    func readsExistingToken() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-token-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try "  my-secret-token\n".write(to: url, atomically: true, encoding: .utf8)

        #expect(try TokenStore.loadOrCreate(at: url) == "my-secret-token")
    }
}
