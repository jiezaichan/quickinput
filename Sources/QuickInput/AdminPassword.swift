import Foundation
import Security
import OpenDirectory

// MARK: - 管理员密码
//
// 存登录钥匙串，不进 snippets.json，导出片段不会带出密码。
// 保存前先向系统校验，免得存了错密码、点了填入反而让授权框抖一下。
//
// 条目的访问控制做成「允许本机任何应用访问」：自签证书没有 Team ID，钥匙串只能按
// 二进制哈希（cdhash）认人，二进制一变（每次改代码重编译）就要输一次登录密码。
// 放开 ACL 后不再弹框。密码仍在 FileVault 加密的登录钥匙串里，任何应用都读得到——
// 这是为免弹框做的取舍。
// 启动时只查条目在不在（不取密码数据，不触发授权框），菜单里能直接显示有没有设置。

enum AdminPassword {
	private static let service = "com.jiezaichan.quickinput.admin-password"
	private static var account: String { NSUserName() }

	/// 授权框监听每秒要看一次，缓存起来不反复读钥匙串。
	/// 只查条目在不在、不取密码数据，查询属性不需要授权，启动时不会弹框。
	private(set) static var isSet: Bool = exists()

	private static func exists() -> Bool {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecMatchLimit as String: kSecMatchLimitOne,
		]
		return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
	}

	static func read() -> String? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
		]
		var out: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
		      let data = out as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}

	static func save(_ password: String) -> Bool {
		clear()
		// trustedApplications 传 nil = 允许本机任何应用访问，重编译后不再弹授权框
		var access: SecAccess?
		SecAccessCreate("速填 · 管理员密码" as CFString, nil, &access)
		var item: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecAttrLabel as String: "速填 · 管理员密码",
			kSecValueData as String: Data(password.utf8),
		]
		if let access { item[kSecAttrAccess as String] = access }
		isSet = SecItemAdd(item as CFDictionary, nil) == errSecSuccess
		return isSet
	}

	static func clear() {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
		]
		SecItemDelete(query as CFDictionary)
		isSet = false
	}

	/// 用本机目录服务校验当前用户的登录密码
	static func verify(_ password: String) -> Bool {
		guard let node = try? ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeLocalNodes)),
		      let record = try? node.record(withRecordType: kODRecordTypeUsers, name: account, attributes: nil)
		else { return false }
		return (try? record.verifyPassword(password)) != nil
	}
}
