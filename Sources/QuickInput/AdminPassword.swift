import Foundation
import Security
import OpenDirectory

// MARK: - 管理员密码
//
// 存登录钥匙串，不进 snippets.json，导出片段不会带出密码。
// 保存前先向系统校验，免得存了错密码、点了填入反而让授权框抖一下。
// 每次改代码重新编译后首次启动会弹「“速填”想要访问你的钥匙串」：签名要求是稳定的，但钥匙串条目的
// 分区列表对自签证书（无 Team ID）只能记 cdhash:<二进制哈希>，二进制一变就不认。
// 弹框期间速填卡住、授权框功能不生效；必须点「始终允许」（把新 cdhash 加进分区列表），只点「允许」下次启动还会问。
// 不改代码只重装（二进制不变）不会弹。不把条目放开成任意程序可读：那样谁都能静默拿到登录密码。
// 启动时就读（isSet 初始化），让这个框在刚装完时弹，而不是等到授权框出现时才弹。

enum AdminPassword {
	private static let service = "com.jiezaichan.quickinput.admin-password"
	private static var account: String { NSUserName() }

	/// 授权框监听每秒要看一次，缓存起来不反复读钥匙串
	private(set) static var isSet: Bool = read() != nil

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
		let item: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecAttrLabel as String: "速填 · 管理员密码",
			kSecValueData as String: Data(password.utf8),
		]
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
