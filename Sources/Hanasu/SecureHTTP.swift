import Foundation

// 要件: REQ-COM-022
// 設計判断: DEC-COM-044
/// AI の API（Gemini・Claude）とトークンの取得に使う通信。
/// - HTTPS だけを使う（http の URL は送る前に断る）。証明書の検証は OS の既定のまま（外さない）
/// - リダイレクトには従わない。キーの入ったヘッダー（x-api-key / x-goog-api-key / Authorization）を、ほかのホストへ送らないため
/// - キャッシュとクッキーを使わない（応答の本文＝整えた文章や議事録をディスクに残さない）
enum SecureHTTP {
    enum Failure: LocalizedError {
        case insecureURL
        case redirected(status: Int)

        var errorDescription: String? {
            switch self {
            case .insecureURL: tr("HTTPS ではない宛先には送りません")
            case .redirected(let status): tr("API の応答がリダイレクト（%@）だったため、従わずに止めました", "\(status)")
            }
        }
    }

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }()

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard request.url?.scheme?.lowercased() == "https" else { throw Failure.insecureURL }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, (300..<400).contains(http.statusCode) {
            throw Failure.redirected(status: http.statusCode)
        }
        return (data, response)
    }

    private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            nil  // リダイレクトの応答をそのまま返させる（上の data(for:) でエラーにする）
        }
    }
}
