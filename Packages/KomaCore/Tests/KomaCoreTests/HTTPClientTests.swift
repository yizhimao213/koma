import XCTest
@testable import KomaCore

private final class TransportRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var sleepLog: [Double] = []
    private var results: [Result<Int, Error>]

    init(results: [Result<Int, Error>]) {
        self.results = results
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return requests.count
    }

    var firstRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return requests.first
    }

    var sleeps: [Double] {
        lock.lock(); defer { lock.unlock() }
        return sleepLog
    }

    func recordSleep(_ seconds: Double) {
        lock.lock(); defer { lock.unlock() }
        sleepLog.append(seconds)
    }

    func next(for request: URLRequest) throws -> (Data, URLResponse) {
        lock.lock()
        requests.append(request)
        let result = results.count > 1 ? results.removeFirst() : results[0]
        lock.unlock()
        switch result {
        case .failure(let error):
            throw error
        case .success(let status):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            return (Data("ok".utf8), response)
        }
    }
}

final class HTTPClientTests: XCTestCase {
    private let url = URL(string: "https://example.test/x")!

    private func makeClient(_ recorder: TransportRecorder) -> URLSessionHTTPClient {
        URLSessionHTTPClient(
            limiter: RateLimiter(ratePerSecond: 1000),
            sleep: { recorder.recordSleep($0) },
            transport: { try recorder.next(for: $0) }
        )
    }

    func testSetsUserAgentAndTimeout() async throws {
        let recorder = TransportRecorder(results: [.success(200)])
        let client = makeClient(recorder)
        _ = try await client.data(for: URLRequest(url: url))
        let request = try XCTUnwrap(recorder.firstRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Koma/0.2 (iOS)")
        XCTAssertEqual(request.timeoutInterval, 10)
    }

    func testRetriesOn503ThenSucceeds() async throws {
        let recorder = TransportRecorder(results: [.success(503), .success(503), .success(200)])
        let client = makeClient(recorder)
        let (_, response) = try await client.data(for: URLRequest(url: url))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(recorder.callCount, 3)
        XCTAssertEqual(recorder.sleeps, [0.5, 1.0])
    }

    func testGivesUpAfterRetries() async {
        let recorder = TransportRecorder(results: [.success(500)])
        let client = makeClient(recorder)
        do {
            _ = try await client.data(for: URLRequest(url: url))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? HTTPError, HTTPError(statusCode: 500))
        }
        XCTAssertEqual(recorder.callCount, 3)
    }

    func testRetriesOnURLError() async throws {
        let recorder = TransportRecorder(results: [.failure(URLError(.timedOut)), .success(200)])
        let client = makeClient(recorder)
        let (_, response) = try await client.data(for: URLRequest(url: url))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(recorder.callCount, 2)
    }

    func testDoesNotRetry404() async {
        let recorder = TransportRecorder(results: [.success(404)])
        let client = makeClient(recorder)
        do {
            _ = try await client.data(for: URLRequest(url: url))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? HTTPError, HTTPError(statusCode: 404))
        }
        XCTAssertEqual(recorder.callCount, 1)
    }
}
