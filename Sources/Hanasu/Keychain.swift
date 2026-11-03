import Foundation
import Security

enum KeychainError: LocalizedError {
    /// 項目はあるが読めない（アプリの署名が変わった、確認のダイアログで拒否した、など）
    case accessDenied(OSStatus)
    case unexpected(OSStatus)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "キーチェーンの API キーを読めませんでした。アプリの署名が変わった（作り直した・別の版に替えた）ときに起きます。設定 →「AI」でキーを入れ直してください"
        case .unexpected(let status):
            "キーチェーンを使えませんでした（\(status)）"
        }
    }
}

// 要件: REQ-COM-021
// 設計判断: DEC-COM-002, DEC-COM-048
/// API キー（Gemini・Claude）をログインキーチェーンに保存する。
///
/// 項目のアクセス制御（ACL）は、復号を Hanasu 自身だけに許し、ほかのアプリが読もうとしたときは
/// ログインのパスワードを求める確認を出させる（`SecKeychainPromptSelector.requirePassphase`）。
/// データ保護キーチェーン（`kSecUseDataProtectionKeychain`）と `SecAccessControl` は、
/// Apple Developer の Team ID と keychain-access-groups の entitlement がないと使えない（-34018）ので使わない。
/// 調べた結果は docs/design/security.md の 1 章。
enum Keychain {
    static let defaultService = "dev.mactypeless.Hanasu"

    enum Item: String, CaseIterable {
        case geminiAPIKey = "gemini-api-key"
        case claudeAPIKey = "claude-api-key"

        var label: String {
            switch self {
            case .geminiAPIKey: "Hanasu: Gemini API キー"
            case .claudeAPIKey: "Hanasu: Claude API キー"
            }
        }
    }

    private static func baseQuery(_ item: Item, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
        ]
    }

    // 設計判断: DEC-COM-049
    /// キーを読む（使うときに毎回読み、呼び出し側でも長く持たない）。項目がなければ nil
    static func load(_ item: Item, service: String = defaultService) throws -> String? {
        var query = baseQuery(item, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
            return key
        case errSecItemNotFound:
            return nil
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed, errSecNoAccessForItem:
            throw KeychainError.accessDenied(status)
        default:
            throw KeychainError.unexpected(status)
        }
    }

    /// 項目があるか（中身は読まない。属性だけなので、確認のダイアログは出ない）
    static func exists(_ item: Item, service: String = defaultService) -> Bool {
        attributes(item, service: service) != nil
    }

    // 設計判断: DEC-COM-049
    /// 設定画面に出す、保存したキーの末尾 4 文字（保存のときに属性に書いておく。中身は読まない）
    static func hint(_ item: Item, service: String = defaultService) -> String? {
        attributes(item, service: service)?[kSecAttrComment as String] as? String
    }

    private static func attributes(_ item: Item, service: String) -> [String: Any]? {
        var query = baseQuery(item, service: service)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? [String: Any]
    }

    /// 保存する（前の項目は消して作り直す）。空の文字列なら消すだけ
    @discardableResult
    static func save(_ item: Item, key rawKey: String, service: String = defaultService) -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        delete(item, service: service)
        guard !key.isEmpty else { return true }
        var attrs = baseQuery(item, service: service)
        attrs[kSecValueData as String] = Data(key.utf8)
        attrs[kSecAttrLabel as String] = item.label
        attrs[kSecAttrComment as String] = key.count > 12 ? "…\(key.suffix(4))" : "保存済み"
        // macOS 26.6 で試すと、ACL の確認の出し方（prompt selector）は、保存のときにバイト順が入れ替わった
        // （requirePassphase の 0x0001 を渡すと 0x0100 で保存され、パスワードを求めない設定になる）。
        // 入れ替えた値で保存し、保存された項目を読み返して違っていれば、そのままの値で作り直す（OS が直ったとき）
        let wanted = SecKeychainPromptSelector.requirePassphase
        var status = errSecSuccess
        for prompt in [SecKeychainPromptSelector(rawValue: wanted.rawValue.byteSwapped), wanted] {
            delete(item, service: service)
            if let access = makeAccess(description: "Hanasu \(item.rawValue)", prompt: prompt) {
                attrs[kSecAttrAccess as String] = access
            }
            status = SecItemAdd(attrs as CFDictionary, nil)
            guard status == errSecSuccess else { break }
            if storedDecryptPrompt(item, service: service)?.contains(wanted) == true { break }
        }
        if status != errSecSuccess {
            appLog.error("keychain save failed: \(status, privacy: .public)")
        } else if storedDecryptPrompt(item, service: service)?.contains(wanted) != true {
            appLog.error("keychain: require-passphrase is not set on the saved item")
        }
        return status == errSecSuccess
    }

    @discardableResult
    static func delete(_ item: Item, service: String = defaultService) -> Bool {
        let status = SecItemDelete(baseQuery(item, service: service) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // 設計判断: DEC-COM-048
    /// 復号（読み出し）を許すアプリを Hanasu 自身だけにし、ほかのアプリにはパスワードの入力を求める ACL。
    /// SecAccess の API は非推奨だが、ファイル型のキーチェーンの ACL を決める手段はこれしかない。
    /// description（確認のダイアログに出る名前）は ASCII にする
    private static func makeAccess(description label: String, prompt: SecKeychainPromptSelector) -> SecAccess? {
        var selfApp: SecTrustedApplication?
        guard SecTrustedApplicationCreateFromPath(nil, &selfApp) == errSecSuccess, let selfApp else { return nil }
        var access: SecAccess?
        guard SecAccessCreate(label as CFString, [selfApp] as CFArray, &access) == errSecSuccess, let access else { return nil }
        for acl in (SecAccessCopyMatchingACLList(access, kSecACLAuthorizationDecrypt) as? [SecACL]) ?? [] {
            var apps: CFArray?
            var description: CFString?
            var current = SecKeychainPromptSelector()
            guard SecACLCopyContents(acl, &apps, &description, &current) == errSecSuccess else { continue }
            SecACLSetContents(acl, apps, description ?? label as CFString, prompt)
        }
        return access
    }

    /// ほかのアプリが読もうとしたときに、パスワードを求める設定で保存されているか（確かめ方の CLI 用）
    static func requiresPassphraseForOtherApps(_ item: Item, service: String = defaultService) -> Bool {
        storedDecryptPrompt(item, service: service)?.contains(.requirePassphase) == true
    }

    /// 保存された項目の、復号の ACL の確認の出し方（項目から読み返すと、実際に効いている値が返る）
    private static func storedDecryptPrompt(_ item: Item, service: String) -> SecKeychainPromptSelector? {
        guard let access = storedAccess(item, service: service) else { return nil }
        for acl in (SecAccessCopyMatchingACLList(access, kSecACLAuthorizationDecrypt) as? [SecACL]) ?? [] {
            var apps: CFArray?
            var description: CFString?
            var prompt = SecKeychainPromptSelector()
            if SecACLCopyContents(acl, &apps, &description, &prompt) == errSecSuccess { return prompt }
        }
        return nil
    }

    private static func storedAccess(_ item: Item, service: String) -> SecAccess? {
        var query = baseQuery(item, service: service)
        query[kSecReturnRef as String] = true
        var ref: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess, let ref,
              CFGetTypeID(ref) == SecKeychainItemGetTypeID() else { return nil }
        var access: SecAccess?
        guard SecKeychainItemCopyAccess(ref as! SecKeychainItem, &access) == errSecSuccess else { return nil }
        return access
    }

    // MARK: - 確かめ方（CLI の --keychain-selftest）

    /// 項目の ACL を読みやすい形にする（信頼するアプリ・確認の出し方・パーティション）。中身は読まない
    static func describeAccess(_ item: Item, service: String) -> [String] {
        guard let access = storedAccess(item, service: service) else { return ["（項目がないか、ACL を読めません）"] }
        var list: CFArray?
        SecAccessCopyACLList(access, &list)
        var lines: [String] = []
        for acl in (list as? [SecACL]) ?? [] {
            let authorizations = (SecACLCopyAuthorizations(acl) as? [String] ?? []).map { $0.replacingOccurrences(of: "ACLAuthorization", with: "") }
            var apps: CFArray?
            var description: CFString?
            var prompt = SecKeychainPromptSelector()
            SecACLCopyContents(acl, &apps, &description, &prompt)
            if authorizations.contains("PartitionID"), let partitions = partitionList(hex: description as String? ?? "") {
                lines.append("PartitionID: \(partitions.joined(separator: ", "))")
                continue
            }
            let appNames: String
            if let apps = apps as? [SecTrustedApplication] {
                appNames = apps.isEmpty ? "なし（どのアプリにも確認を出す）" : apps.map { app -> String in
                    var data: CFData?
                    SecTrustedApplicationCopyData(app, &data)
                    let path = String(decoding: (data as Data?) ?? Data(), as: UTF8.self)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                    return (path as NSString).lastPathComponent
                }.joined(separator: ", ")
            } else {
                appNames = "すべてのアプリ"
            }
            var line = "\(authorizations.joined(separator: "/")): \(appNames)"
            if prompt.contains(.requirePassphase) { line += "（ほかのアプリにはパスワードを求める）" }
            lines.append(line)
        }
        return lines
    }

    private static func partitionList(hex: String) -> [String]? {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex, let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) {
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: Data(bytes), format: nil) as? [String: Any] else { return nil }
        return plist["Partitions"] as? [String]
    }
}
