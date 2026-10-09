import Cocoa
import Carbon.HIToolbox

// MARK: - 系统授权框一键填密码
//
// 两种授权框：
// 1. SecurityAgent 进程弹的独立框（「xx 想要进行更改」、钥匙串访问等），会锁住键盘焦点；
// 2. 苹果自家 App 自己画的解锁 sheet（系统设置 → 用户与群组 等），属主是 App 本身，见 findAppAuthSheet。
// 授权框里焦点在密码框上，别的窗口抢不到焦点（已实测），所以不弹可交互的对话框，而是：
// 授权框出现期间临时把 ↩ 注册成全局热键（见 HotKeyCenter.armAuthReturn），旁边贴一条提示；
// 按 ↩（或点提示）→ 先注销热键，再把钥匙串里的密码打进密码框并回车。
// 每个授权框只接管一次 ↩：万一没通过，下一次 ↩ 照常交给授权框。
//
// 每秒查一次屏幕窗口列表（只读属主名和位置，不需要录屏权限；实测单次 0.37ms）。
// 没法改成事件驱动：NSWorkspace 收不到 SecurityAgent 的启动通知，弹窗关了它还会驻留一阵。
// 故意不做全自动填：那样任何程序弹授权框都会被自动放行，等于把这道关拆了。
// 已实测 CGEvent Unicode 键盘事件能打进 SecurityAgent 的密码框。

final class AuthAssist {
	static let shared = AuthAssist()

	private let hint = AuthHint()
	private var timer: Timer?
	/// 当前接管 ↩ 的授权框
	private var armedWindow: String?
	/// 已经接管过的授权框，不再接管
	private var usedWindow: String?

	func start() {
		timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
		timer?.tolerance = 0.3 // 允许系统合并唤醒，省电
	}

	private func tick() {
		guard AdminPassword.isSet, let (key, rect) = findSecurityAgentWindow() ?? findAppAuthSheet() else {
			// 框没了就忘掉：系统设置新开的解锁 sheet 的 AX 哈希可能和上一个相同
			usedWindow = nil
			disarm()
			return
		}
		guard key != usedWindow, key != armedWindow else { return }
		armedWindow = key
		HotKeyCenter.shared.armAuthReturn()
		hint.show(beside: rect)
	}

	/// ↩ 热键或点提示触发
	func fill() {
		guard armedWindow != nil, let password = AdminPassword.read() else { return }
		usedWindow = armedWindow
		disarm() // 先注销 ↩，后面补的回车才能落到授权框
		Typer.insert(password, pressEnter: true, hidLevel: true)
	}

	private func disarm() {
		armedWindow = nil
		HotKeyCenter.shared.disarmAuthReturn()
		if hint.isVisible { hint.orderOut(nil) }
	}

	/// SecurityAgent 弹的独立授权框：返回标识和 Cocoa 坐标下的位置
	private func findSecurityAgentWindow() -> (String, NSRect)? {
		let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
			as? [[String: Any]] ?? []
		guard let w = list.first(where: { ($0[kCGWindowOwnerName as String] as? String) == "SecurityAgent" }),
		      let number = w[kCGWindowNumber as String] as? Int,
		      let dict = w[kCGWindowBounds as String] as? NSDictionary,
		      let cg = CGRect(dictionaryRepresentation: dict)
		else { return nil }
		return ("sa-\(number)", AuthAssist.toCocoa(cg))
	}

	/// 苹果自家 App 里自己画的解锁框（如 系统设置 → 用户与群组 的「正在尝试解锁系统设置」，
	/// 属主是 系统设置 不是 SecurityAgent）：焦点在密码框上、密码框挂在 sheet 或对话框里。
	/// 只认 com.apple.* 且必须在 sheet / 对话框里，排除网页登录框（Safari 的网页密码框在普通窗口里）。
	/// 有密码框获得焦点时系统才开安全输入，先用它挡掉绝大多数时候的 AX 查询。
	private func findAppAuthSheet() -> (String, NSRect)? {
		guard IsSecureEventInputEnabled(),
		      let front = NSWorkspace.shared.frontmostApplication,
		      front.bundleIdentifier?.hasPrefix("com.apple.") == true
		else { return nil }
		let app = AXUIElementCreateApplication(front.processIdentifier)
		guard let focused = AuthAssist.ax(app, kAXFocusedUIElementAttribute).map({ $0 as! AXUIElement }),
		      AuthAssist.ax(focused, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole as String
		else { return nil }

		// 往上找装着密码框的 sheet / 对话框
		var node = focused
		while let parent = AuthAssist.ax(node, kAXParentAttribute).map({ $0 as! AXUIElement }) {
			node = parent
			let role = AuthAssist.ax(node, kAXRoleAttribute) as? String
			let sub = AuthAssist.ax(node, kAXSubroleAttribute) as? String
			let isContainer = role == kAXSheetRole as String
				|| sub == kAXDialogSubrole as String || sub == kAXSystemDialogSubrole as String
			if isContainer, let rect = AuthAssist.frame(of: node) {
				return ("app-\(front.processIdentifier)-\(CFHash(node))", AuthAssist.toCocoa(rect))
			}
			if role == kAXWindowRole as String { return nil }
		}
		return nil
	}

	private static func ax(_ e: AXUIElement, _ attr: String) -> CFTypeRef? {
		var v: CFTypeRef?
		return AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success ? v : nil
	}

	/// AX 坐标与 CG 一样，原点在主屏左上角
	private static func frame(of e: AXUIElement) -> CGRect? {
		guard let p = ax(e, kAXPositionAttribute), let s = ax(e, kAXSizeAttribute) else { return nil }
		var pos = CGPoint.zero
		var size = CGSize.zero
		AXValueGetValue(p as! AXValue, .cgPoint, &pos)
		AXValueGetValue(s as! AXValue, .cgSize, &size)
		return CGRect(origin: pos, size: size)
	}

	/// CG / AX 坐标原点在主屏左上角，Cocoa 在左下角
	private static func toCocoa(_ r: CGRect) -> NSRect {
		let mainHeight = NSScreen.screens.first?.frame.height ?? 0
		return NSRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)
	}
}

/// 贴在授权框旁的提示条：不抢焦点，点一下等同按 ↩
final class AuthHint: NSPanel {
	override var canBecomeKey: Bool { false }

	init() {
		super.init(contentRect: NSRect(x: 0, y: 0, width: 190, height: 36),
		           styleMask: [.nonactivatingPanel, .borderless],
		           backing: .buffered,
		           defer: true)
		level = .screenSaver // SecurityAgent 窗口在 1000 层（= screenSaver），同层才不会被压住
		isOpaque = false
		backgroundColor = .clear
		hasShadow = true
		hidesOnDeactivate = false
		isReleasedWhenClosed = false
		collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

		let bg = ClickView(frame: NSRect(x: 0, y: 0, width: 190, height: 36))
		bg.material = .hudWindow
		bg.state = .active
		bg.wantsLayer = true
		bg.layer?.cornerRadius = 10
		bg.onClick = { AuthAssist.shared.fill() }
		contentView = bg

		let label = NSTextField(labelWithString: "🔑 按 ↩ 自动填入密码")
		label.font = .systemFont(ofSize: 13, weight: .medium)
		label.alignment = .center
		label.frame = NSRect(x: 8, y: 9, width: 174, height: 18)
		bg.addSubview(label)
	}

	/// 贴在授权框右侧顶端对齐，右边放不下就放左侧
	func show(beside rect: NSRect) {
		let gap: CGFloat = 12
		var x = rect.maxX + gap
		let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
		if let vf = screen?.visibleFrame, x + frame.width > vf.maxX { x = rect.minX - gap - frame.width }
		setFrameOrigin(NSPoint(x: x, y: rect.maxY - frame.height))
		orderFrontRegardless()
	}
}

private final class ClickView: NSVisualEffectView {
	var onClick: (() -> Void)?
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
	override func mouseDown(with event: NSEvent) { onClick?() }
}
