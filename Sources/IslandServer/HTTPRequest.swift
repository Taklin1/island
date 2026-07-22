import Foundation

/// Minimal HTTP/1.1 request representation — just enough for the local hook
/// endpoint. Not a general-purpose HTTP implementation on purpose.
struct HTTPRequest {
    let method: String
    /// Path without the query string, e.g. "/hooks/claude-code".
    let path: String
    /// Percent-decoded query parameters.
    let query: [String: String]
    /// Header fields, keys lowercased.
    let headers: [String: String]
    let body: Data

    /// Parses a buffered request. Returns `nil` while the request is still
    /// incomplete (headers or body not fully received yet).
    static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let headerText = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else {
            return nil
        }

        var lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        let method = String(requestLine[0])
        let target = String(requestLine[1])

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let contentLength = headers["content-length"].flatMap(Int.init) ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.count - bodyStart >= contentLength else { return nil }
        let body = data.subdata(in: bodyStart ..< bodyStart + contentLength)

        let components = URLComponents(string: target)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            query[item.name] = item.value
        }

        return HTTPRequest(
            method: method,
            path: components?.path ?? target,
            query: query,
            headers: headers,
            body: body
        )
    }
}
