import Foundation
import Testing
@testable import IslandRelay

/// Relais failure traces (issue #157): one line, yet complete enough to tell
/// "Local Network denied" from "Totem unreachable" from "timed out".
struct RelayTraceTests {
    @Test("A transport error is traced on one line with its domain, code, underlying errors and network path")
    func errorTraceIsCompleteOnOneLine() {
        let underlying = NSError(domain: "kCFErrorDomainCFNetwork", code: -1004, userInfo: [
            "_NSURLErrorNWPathKey": "unsatisfied (Local network prohibited), interface: en0",
        ])
        let error = NSError(domain: NSURLErrorDomain, code: -1004, userInfo: [
            NSLocalizedDescriptionKey: "Could not connect to the server.",
            NSUnderlyingErrorKey: underlying,
            "_NSURLErrorNWPathKey": "unsatisfied (Local network prohibited), interface: en0",
        ])

        let trace = TotemRelay.trace(of: error)

        #expect(!trace.contains("\n"))
        #expect(trace.contains("NSURLErrorDomain -1004"))
        #expect(trace.contains("Could not connect to the server."))
        #expect(trace.contains("kCFErrorDomainCFNetwork -1004"))
        #expect(trace.contains("unsatisfied (Local network prohibited)"))
    }
}
