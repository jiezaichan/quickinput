import Foundation
import ServiceManagement

// MARK: - 开机自启

/// 走系统「登录项」（SMAppService），在 系统设置 → 通用 → 登录项 里可见、可关。
/// 1.1 及以前是自己写 LaunchAgent plist（com.jiezaichan.quickinput），由 build.sh install 迁走。
enum LoginItem {
	static var enabled: Bool { SMAppService.mainApp.status == .enabled }

	static func set(_ on: Bool) {
		do {
			if on {
				try SMAppService.mainApp.register()
			} else {
				try SMAppService.mainApp.unregister()
			}
		} catch {
			NSLog("登录项\(on ? "注册" : "取消")失败：\(error)")
		}
		// 用户曾在系统设置里关掉过，register 后会停在待批准，只能让他去系统设置里打开
		if on && SMAppService.mainApp.status == .requiresApproval {
			SMAppService.openSystemSettingsLoginItems()
		}
	}
}
