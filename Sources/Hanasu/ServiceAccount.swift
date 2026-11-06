import Foundation
import Security

enum ServiceAccountError: LocalizedError {
    case fileNotFound(String)
    case invalidJSON
    case invalidPrivateKey
    case signingFailed(String)
    case tokenRequestFailed(status: Int, message: String)
    case untrustedTokenURI(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): tr("サービスアカウントの JSON が見つかりません: %@", "\(path)")
        case .invalidJSON: tr("サービスアカウントの JSON を読み取れません")
        case .invalidPrivateKey: tr("サービスアカウントの秘密鍵を読み取れません")
        case .signingFailed(let message): tr("アクセストークン用の署名に失敗しました: %@", "\(message)")
        case .tokenRequestFailed(let status, let message): tr("アクセストークンの取得に失敗しました（%@）: %@", "\(status)", "\(message)")
        case .untrustedTokenURI(let uri): tr("サービスアカウントの token_uri（%@）が Google のトークンの窓口（oauth2.googleapis.com）ではないため、使いません", "\(uri)")
        }
    }
}

// 設計判断: DEC-COM-003
/// Google Cloud のサービスアカウント鍵（JSON）。
struct ServiceAccountCredentials: Decodable {
    let projectID: String
    let clientEmail: String
    let privateKey: String
    let tokenURI: String

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case clientEmail = "client_email"
        case privateKey = "private_key"
        case tokenURI = "token_uri"
    }

    static func load(path: String) throws -> ServiceAccountCredentials {
        let expanded = (path as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: expanded) else {
            throw ServiceAccountError.fileNotFound(path)
        }
        do {
            return try JSONDecoder().decode(ServiceAccountCredentials.self, from: data)
        } catch {
            throw ServiceAccountError.invalidJSON
        }
    }
}

// 設計判断: DEC-COM-003
/// サービスアカウント鍵で署名した JWT を OAuth のアクセストークンに交換し、期限まで使い回す。
actor ServiceAccountTokenProvider {
    static let shared = ServiceAccountTokenProvider()

    private static let scope = "https://www.googleapis.com/auth/cloud-platform"
    private var cache: [String: (token: String, expiresAt: Date)] = [:]

    func accessToken(for credentials: ServiceAccountCredentials) async throws -> String {
        if let cached = cache[credentials.clientEmail], cached.expiresAt.timeIntervalSinceNow > 60 {
            return cached.token
        }
        let assertion = try Self.makeJWT(credentials)

        // 設計判断: DEC-COM-053
        // token_uri は鍵ファイルに書いてある値だが、署名した JWT を送る先なので Google のトークンの窓口に限る
        guard let tokenURL = URL(string: credentials.tokenURI), Self.isTrustedTokenURL(tokenURL) else {
            throw ServiceAccountError.untrustedTokenURI(credentials.tokenURI)
        }
        var request = URLRequest(url: tokenURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(
            "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=\(assertion)".utf8)

        // 設計判断: DEC-COM-044
        let (data, response) = try await SecureHTTP.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let token = try? JSONDecoder().decode(TokenResponse.self, from: data)
        else {
            throw ServiceAccountError.tokenRequestFailed(
                status: status, message: String(data: data, encoding: .utf8) ?? "")
        }
        cache[credentials.clientEmail] = (token.access_token, Date().addingTimeInterval(TimeInterval(token.expires_in)))
        return token.access_token
    }

    // 設計判断: DEC-COM-053
    static func isTrustedTokenURL(_ url: URL) -> Bool {
        // 古い鍵ファイルは https://accounts.google.com/o/oauth2/token を書いている
        url.scheme == "https" && ["oauth2.googleapis.com", "accounts.google.com"].contains(url.host ?? "")
            && url.port == nil && url.user == nil
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int
    }

    // MARK: - JWT (RS256)

    private static func makeJWT(_ credentials: ServiceAccountCredentials) throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let header = #"{"alg":"RS256","typ":"JWT"}"#
        let claims: [String: Any] = [
            "iss": credentials.clientEmail,
            "scope": scope,
            "aud": credentials.tokenURI,
            "iat": now,
            "exp": now + 3600,
        ]
        let claimsData = try JSONSerialization.data(withJSONObject: claims)
        let signingInput = base64URL(Data(header.utf8)) + "." + base64URL(claimsData)

        let key = try privateKey(fromPEM: credentials.privateKey)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key, .rsaSignatureMessagePKCS1v15SHA256, Data(signingInput.utf8) as CFData, &error) as Data?
        else {
            let message = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw ServiceAccountError.signingFailed(message)
        }
        return signingInput + "." + base64URL(signature)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// PEM（PKCS#8 の "BEGIN PRIVATE KEY"）から SecKey を作る。
    /// Security.framework は PKCS#1 の RSA 鍵しか受け付けないので、PKCS#8 の外側を外す。
    private static func privateKey(fromPEM pem: String) throws -> SecKey {
        let base64 = pem.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let der = Data(base64Encoded: base64) else { throw ServiceAccountError.invalidPrivateKey }
        let pkcs1 = pem.contains("BEGIN RSA PRIVATE KEY") ? der : try unwrapPKCS8(der)

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil) else {
            throw ServiceAccountError.invalidPrivateKey
        }
        return key
    }

    /// PrivateKeyInfo ::= SEQUENCE { version INTEGER, algorithm SEQUENCE, privateKey OCTET STRING }
    private static func unwrapPKCS8(_ der: Data) throws -> Data {
        var reader = DERReader(bytes: [UInt8](der))
        guard let outer = reader.read(tag: 0x30) else { throw ServiceAccountError.invalidPrivateKey }
        var inner = DERReader(bytes: outer)
        guard inner.read(tag: 0x02) != nil,  // version
              inner.read(tag: 0x30) != nil,  // algorithm
              let octets = inner.read(tag: 0x04)
        else { throw ServiceAccountError.invalidPrivateKey }
        return Data(octets)
    }

    private struct DERReader {
        let bytes: [UInt8]
        var offset = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        mutating func read(tag: UInt8) -> [UInt8]? {
            guard offset + 2 <= bytes.count, bytes[offset] == tag else { return nil }
            offset += 1
            var length = Int(bytes[offset])
            offset += 1
            if length & 0x80 != 0 {
                let count = length & 0x7F
                guard count <= 4, offset + count <= bytes.count else { return nil }
                length = bytes[offset..<offset + count].reduce(0) { $0 << 8 | Int($1) }
                offset += count
            }
            guard offset + length <= bytes.count else { return nil }
            defer { offset += length }
            return Array(bytes[offset..<offset + length])
        }
    }
}
