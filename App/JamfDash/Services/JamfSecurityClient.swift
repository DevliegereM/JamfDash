import Foundation
import OSLog

actor JamfSecurityClient {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "JamfSecurityClient")
    private static let baseURL = URL(string: "https://api.wandera.com")!

    private let session: URLSession
    private let applicationID: String
    private let applicationSecret: String

    private var cachedToken: String?
    private var tokenExpiry: Date = .distantPast

    init(credentials: JSCCredentials) {
        self.applicationID     = credentials.applicationID
        self.applicationSecret = credentials.applicationSecret
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    func fetchAllDevices() async throws -> [JSCDevice] {
        var all: [JSCDevice] = []
        var page = 0
        let pageSize = 100
        Self.logger.info("Fetching all JSC devices")
        while true {
            let response = try await fetchDevicePage(page: page, pageSize: pageSize)
            all.append(contentsOf: response.userDeviceList)
            Self.logger.debug("Fetched page \(page): \(response.userDeviceList.count, privacy: .public) devices")
            if response.userDeviceList.count < pageSize { break }
            page += 1
        }
        Self.logger.info("JSC fetch complete — \(all.count, privacy: .public) devices total")
        return all
    }

    /// Validates credentials by fetching a single device. Throws on auth failure.
    func validateCredentials() async throws {
        _ = try await validToken()
        Self.logger.info("JSC credentials validated successfully")
    }

    // MARK: - Private

    /// Maximum number of attempts for a single page when the API keeps answering 429.
    private static let maxRateLimitAttempts = 5
    /// Upper bound for a server-suggested retry delay, so a bogus header can't stall a refresh.
    private static let maxRetryDelayMs = 30_000

    private func fetchDevicePage(page: Int, pageSize: Int) async throws -> JSCDeviceListResponse {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("/risk/v2/devices"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "page",     value: "\(page)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)")
        ]
        guard let url = components.url else { throw JSCError.invalidResponse }

        var rateLimitAttempts = 0
        var didRefreshAfter401 = false
        while true {
            let token = try await validToken()
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw JSCError.invalidResponse }

            switch http.statusCode {
            case 200...299:
                return try JSONDecoder().decode(JSCDeviceListResponse.self, from: data)

            case 401 where !didRefreshAfter401:
                // Token revoked or expired early — drop it and retry once with a fresh one.
                Self.logger.warning("JSC returned 401 — refreshing token and retrying once")
                invalidateToken()
                didRefreshAfter401 = true

            case 429:
                rateLimitAttempts += 1
                guard rateLimitAttempts < Self.maxRateLimitAttempts else {
                    Self.logger.error("JSC still rate limited after \(rateLimitAttempts, privacy: .public) attempts — giving up")
                    throw JSCError.rateLimited
                }
                let suggested = Int(http.value(forHTTPHeaderField: "X-Rate-Limit-Retry-After-Milliseconds") ?? "") ?? 2000
                let retryMs = min(max(suggested, 500), Self.maxRetryDelayMs)
                Self.logger.warning("JSC rate limited — retry \(rateLimitAttempts, privacy: .public)/\(Self.maxRateLimitAttempts - 1, privacy: .public) after \(retryMs, privacy: .public)ms")
                try await Task.sleep(nanoseconds: UInt64(retryMs) * 1_000_000)

            default:
                if http.statusCode == 401 { invalidateToken() }
                Self.logger.error("JSC device fetch failed: HTTP \(http.statusCode, privacy: .public)")
                throw JSCError.httpError(http.statusCode)
            }
        }
    }

    private func invalidateToken() {
        cachedToken = nil
        tokenExpiry = .distantPast
    }

    private func validToken() async throws -> String {
        if let t = cachedToken, Date() < tokenExpiry { return t }
        return try await refreshToken()
    }

    private func refreshToken() async throws -> String {
        let credentials = "\(applicationID):\(applicationSecret)"
        guard let credData = credentials.data(using: .utf8) else {
            throw JSCError.invalidCredentials
        }
        let base64 = credData.base64EncodedString()

        var request = URLRequest(url: Self.baseURL.appendingPathComponent("/v1/login"))
        request.httpMethod = "POST"
        request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")

        Self.logger.info("Refreshing JSC auth token")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw JSCError.invalidResponse }

        guard http.statusCode == 200 else {
            Self.logger.error("JSC auth failed: HTTP \(http.statusCode, privacy: .public)")
            throw JSCError.authFailed(http.statusCode)
        }

        let loginResponse = try JSONDecoder().decode(JSCLoginResponseInternal.self, from: data)
        cachedToken  = loginResponse.token
        tokenExpiry  = Date().addingTimeInterval(14 * 60) // 14 min — API expires at 15 min
        Self.logger.info("JSC token acquired, expires in 14 min")
        return loginResponse.token
    }
}

private struct JSCLoginResponseInternal: Decodable {
    let token: String
}
