import Foundation

public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct HTTPError: Error, Equatable {
    public let statusCode: Int

    public init(statusCode: Int) {
        self.statusCode = statusCode
    }
}

public final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {
    private let session: URLSession
    private let limiter: RateLimiter
    private let maxRetries: Int
    private let backoff: [Double]
    private let timeout: TimeInterval
    private let sleep: @Sendable (Double) async -> Void
    private let transport: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?

    public init(
        session: URLSession = .shared,
        limiter: RateLimiter = RateLimiter(ratePerSecond: 5),
        maxRetries: Int = 2,
        backoff: [Double] = [0.5, 1.0],
        timeout: TimeInterval = 10,
        sleep: @escaping @Sendable (Double) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        },
        transport: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil
    ) {
        self.session = session
        self.limiter = limiter
        self.maxRetries = max(0, maxRetries)
        self.backoff = backoff
        self.timeout = timeout
        self.sleep = sleep
        self.transport = transport
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var prepared = request
        prepared.setValue("Koma/0.2 (iOS)", forHTTPHeaderField: "User-Agent")
        prepared.timeoutInterval = timeout

        var attempt = 0
        while true {
            try Task.checkCancellation()
            await limiter.acquire()

            let failure: Error
            do {
                let (data, response) = try await perform(prepared)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                if (200..<300).contains(http.statusCode) {
                    return (data, http)
                }
                let error = HTTPError(statusCode: http.statusCode)
                if !Self.isRetryable(status: http.statusCode) {
                    throw error
                }
                failure = error
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as HTTPError where !Self.isRetryable(status: error.statusCode) {
                throw error
            } catch {
                if Task.isCancelled { throw CancellationError() }
                failure = error
            }

            guard attempt < maxRetries else { throw failure }
            let delay = backoff.isEmpty ? 0 : backoff[min(attempt, backoff.count - 1)]
            attempt += 1
            await sleep(delay)
        }
    }

    private static func isRetryable(status: Int) -> Bool {
        status == 429 || (500...599).contains(status)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        if let transport {
            return try await transport(request)
        }
        return try await session.data(for: request)
    }
}
