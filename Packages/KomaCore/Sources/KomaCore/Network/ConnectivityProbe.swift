import Foundation

public struct ProbeResult: Equatable, Sendable {
    public var name: String
    public var latencyMs: Int?
    public var error: String?

    public init(name: String, latencyMs: Int?, error: String?) {
        self.name = name
        self.latencyMs = latencyMs
        self.error = error
    }
}

/// Measures reachability and latency of the API host and the image host.
public struct ConnectivityProbe {
    private let client: HTTPClient
    private let settings: NetworkSettings
    private let now: () -> Double

    public init(client: HTTPClient, settings: NetworkSettings, now: @escaping () -> Double) {
        self.client = client
        self.settings = settings
        self.now = now
    }

    public func run() async -> [ProbeResult] {
        let apiURL = settings.apiBaseURL.appendingPathComponent("ping")
        var uploads = settings.uploadsBaseURL.absoluteString
        if !uploads.hasSuffix("/") { uploads += "/" }
        let uploadsURL = URL(string: uploads) ?? settings.uploadsBaseURL
        return [
            await probe(name: "API", url: apiURL),
            await probe(name: "图片服务器", url: uploadsURL)
        ]
    }

    private func probe(name: String, url: URL) async -> ProbeResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        let start = now()
        do {
            _ = try await client.data(for: request)
            return ProbeResult(name: name, latencyMs: Self.millis(now() - start), error: nil)
        } catch is HTTPError {
            // The server answered (4xx etc.), so it is reachable.
            return ProbeResult(name: name, latencyMs: Self.millis(now() - start), error: nil)
        } catch {
            return ProbeResult(name: name, latencyMs: nil, error: Self.describe(error))
        }
    }

    private static func millis(_ seconds: Double) -> Int {
        Int((seconds * 1000).rounded())
    }

    private static func describe(_ error: Error) -> String {
        guard let urlError = error as? URLError else { return "失败" }
        switch urlError.code {
        case .timedOut:
            return "超时"
        case .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet:
            return "无法连接"
        default:
            return "失败"
        }
    }
}
