import Cocoa

// MARK: - 系统授权框一键填密码
//
// 系统授权框（「xx 想要进行更改」、钥匙串访问等）都由 SecurityAgent 进程弹出，并锁住键盘焦点，
// 别的窗口抢不到焦点（已实测），所以不弹可交互的对话框，而是：
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
	private var armedWindow: Int?
	/// 已经接管过的授权框，不再接管
	private var usedWindow: Int?

	func start() {
		timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
		timer?.tolerance = 0.3 // 允许系统合并唤醒，省电
	}

	private func tick() {
		guard AdminPassword.isSet, let (number, rect) = findAuthWindow() else {
			disarm()
			return
		}
		guard number != usedWindow, number != armedWindow else { return }
		armedWindow = number
		HotKeyCenter.shared.armAuthReturn()
		hint.show(beside: rect)
	}

	/// ↩ 热键或点提示触发
	func fill() {
		guard armedWindow != nil, let password = AdminPassword.read() else { return }
		usedWindow = armedWindow
		disarm() // 先注销 ↩，后面补的回车才能落到授权框
		Typer.insert(password, pressEnter: true)
	}

	private func disarm() {
		armedWindow = nil
		HotKeyCenter.shared.disarmAuthReturn()
		if hint.isVisible { hint.orderOut(nil) }
	}

	/// 返回 SecurityAgent 窗口的编号和 Cocoa 坐标下的位置
	private func findAuthWindow() -> (Int, NSRect)? {
		let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
			as? [[String: Any]] ?? []
		guard let w = list.first(where: { ($0[kCGWindowOwnerName as String] as? String) == "SecurityAgent" }),
		      let number = w[kCGWindowNumber as String] as? Int,
		      let dict = w[kCGWindowBounds as String] as? NSDictionary,
		      let cg = CGRect(dictionaryRepresentation: dict),
		      let mainHeight = NSScreen.screens.first?.frame.height
		else { return nil }
		// CG 窗口坐标原点在主屏左上角，Cocoa 在左下角
		return (number, NSRect(x: cg.minX, y: mainHeight - cg.maxY, width: cg.width, height: cg.height))
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
