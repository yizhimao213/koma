import XCTest
@testable import KomaCore

private final class ProbeClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let handler: @Sendable (URLRequest) throws -> Int

    init(handler: @escaping @Sendable (URLRequest) throws -> Int) { self.handler = handler }

    var requests: [URLRequest] { lock.withLock { recorded } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recorded.append(request) }
        let status = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(), response)
    }
}

private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double]
    init(_ values: [Double]) { self.values = values }
    func next() -> Double {
        lock.lock(); defer { lock.unlock() }
        return values.isEmpty ? 0 : values.removeFirst()
    }
}

final class ConnectivityProbeTests: XCTestCase {
    func testProbeReportsLatency() async {
        let client = ProbeClient { _ in 200 }
        let clock = FakeClock([0, 0.123, 1, 1.5])
        let probe = ConnectivityProbe(client: client, settings: .default, now: { clock.next() })
        let results = await probe.run()
        XCTAssertEqual(results, [
            ProbeResult(name: "API", latencyMs: 123, error: nil),
            ProbeResult(name: "图片服务器", latencyMs: 500, error: nil)
        ])
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, [
            "https://api.mangadex.org/ping",
            "https://uploads.mangadex.org/"
        ])
        XCTAssertEqual(client.requests.map(\.timeoutInterval), [8, 8])
    }

    func testProbeReportsError() async {
        let client = ProbeClient { _ in throw URLError(.timedOut) }
        let probe = ConnectivityProbe(client: client, settings: .default, now: { 0 })
        let results = await probe.run()
        XCTAssertEqual(results.map(\.latencyMs), [nil, nil])
        XCTAssertEqual(results.map(\.error), ["超时", "超时"])
    }

    func testProbeMapsConnectionErrors() async {
        let client = ProbeClient { _ in throw URLError(.cannotFindHost) }
        let results = await ConnectivityProbe(client: client, settings: .default, now: { 0 }).run()
        XCTAssertEqual(results.map(\.error), ["无法连接", "无法连接"])
        let other = ProbeClient { _ in throw URLError(.badServerResponse) }
        let others = await ConnectivityProbe(client: other, settings: .default, now: { 0 }).run()
        XCTAssertEqual(others.map(\.error), ["失败", "失败"])
    }

    func testProbeTreatsHTTPErrorAsReachable() async {
        let client = ProbeClient { _ in throw HTTPError(statusCode: 403) }
        let clock = FakeClock([0, 0.05, 1, 1.07])
        let results = await ConnectivityProbe(client: client, settings: .default, now: { clock.next() }).run()
        XCTAssertEqual(results.map(\.latencyMs), [50, 70])
        XCTAssertEqual(results.map(\.error), [nil, nil])
    }
}
