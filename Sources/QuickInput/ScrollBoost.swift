import Cocoa

// MARK: - 鼠标滚轮加速
//
// 全局 CGEventTap 拦滚动事件，原事件放行后再补发「倍率 - 1」份副本，相当于滚了 N 次。
// 不放大单个事件的滚动量：微信、终端（Claude Code 等 TUI 收到的是一次一条鼠标上报）
// 按事件次数滚，不看数值大小，放大数值对它们无效。副本打上 eventSourceUserData 标记，
// 回到 tap 时直接放行，不会回灌。只处理非精确滚动：鼠标滚轮是 line-based，触控板两指
// 滚动和 Magic Mouse 是精确滚动（scrollWheelEventIsContinuous = 1），保持系统原速。
//
// 两种触发各一个开关：全局常驻加速；按住左侧 Ctrl 时临时加速（右侧 Ctrl 不算）。
// 左右 Control 的通用修饰键标志不区分，所以另外听 flagsChanged（单按修饰键只发这个，
// 不发 keyDown / keyUp），按 keyCode（59 左、62 右）和设备相关标志位记各自是否按着。
//
// 需要辅助功能权限；没权限时 tap 建不出来，设置窗口里显示「需要辅助功能权限」。

final class ScrollBoost {
	static let shared = ScrollBoost()
	/// 本机设置，存在 UserDefaults，不随片段导入导出
	private static let d = UserDefaults.standard

	// MARK: - 设置

	/// 所有鼠标滚轮滚动都按倍率加速
	var alwaysOn: Bool {
		get { Self.d.bool(forKey: "scrollAlwaysOn") }
		set { Self.d.set(newValue, forKey: "scrollAlwaysOn"); refresh() }
	}

	/// 按住左侧 Ctrl 滚动时临时加速（默认开）
	var withLeftCtrl: Bool {
		get {
			guard Self.d.object(forKey: "scrollWithLeftCtrl") != nil else { return true }
			return Self.d.bool(forKey: "scrollWithLeftCtrl")
		}
		set { Self.d.set(newValue, forKey: "scrollWithLeftCtrl"); refresh() }
	}

	/// 放大倍率 1–15，默认 3；按四舍五入后的整数补发
	var factor: Double {
		get {
			guard Self.d.object(forKey: "scrollFactor") != nil else { return 3 }
			return Self.clamp(Self.d.double(forKey: "scrollFactor"))
		}
		set { Self.d.set(Self.clamp(newValue), forKey: "scrollFactor") }
	}

	private static func clamp(_ v: Double) -> Double { min(max(v, 1), 15) }

	/// 有没有任一触发开着
	var active: Bool { alwaysOn || withLeftCtrl }

	// MARK: - 状态

	/// tap 建不出来（没辅助功能权限）
	private(set) var unavailable = false

	private var tap: CFMachPort?
	private var source: CFRunLoopSource?
	private var leftCtrlDown = false
	private var rightCtrlDown = false

	// MARK: - 安装 / 卸载

	/// 设置变化后调用：两个开关都关就拆掉 tap，不留着白拦事件
	func refresh() {
		active ? installIfNeeded() : uninstall()
	}

	private func installIfNeeded() {
		guard tap == nil else { return }
		let mask: CGEventMask = (1 << CGEventType.scrollWheel.rawValue)
			| (1 << CGEventType.flagsChanged.rawValue)
		// 与 Mos 一致：annotated session tap 的尾部，事件可改、改完放行
		guard let tap = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap,
		                                  place: .tailAppendEventTap,
		                                  options: .defaultTap,
		                                  eventsOfInterest: mask,
		                                  callback: ScrollBoost.callback,
		                                  userInfo: nil) else {
			unavailable = true
			return
		}
		self.tap = tap
		let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
		self.source = source
		CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
		CGEvent.tapEnable(tap: tap, enable: true)
		unavailable = false
	}

	private func uninstall() {
		if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
		if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
		source = nil
		tap = nil
		leftCtrlDown = false
		rightCtrlDown = false
		unavailable = false
	}

	// MARK: - 事件处理

	private static let callback: CGEventTapCallBack = { _, type, event, _ in
		ScrollBoost.shared.handle(type: type, event: event)
		return Unmanaged.passUnretained(event)
	}

	private func handle(type: CGEventType, event: CGEvent) {
		switch type {
		case .tapDisabledByTimeout, .tapDisabledByUserInput:
			// 回调太慢被系统停掉时自己拉起来
			if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
		case .flagsChanged:
			trackCtrl(event)
		case .scrollWheel:
			boostIfNeeded(event)
		default:
			break
		}
	}

	/// IOKit 的 NX_DEVICELCTLKEYMASK / NX_DEVICERCTLKEYMASK
	private static let leftCtrlBit: UInt64 = 0x0000_0001
	private static let rightCtrlBit: UInt64 = 0x0000_2000

	private func trackCtrl(_ event: CGEvent) {
		let raw = event.flags.rawValue
		switch event.getIntegerValueField(.keyboardEventKeycode) {
		case 59: leftCtrlDown = raw & Self.leftCtrlBit != 0
		case 62: rightCtrlDown = raw & Self.rightCtrlBit != 0
		default: break
		}
	}

	/// 补发副本的标记（"QIBS"），回到 tap 时据此放行
	private static let copyMarker: Int64 = 0x5149_4253
	/// 副本间隔：连着发会被 App 合并成一个事件，按次数滚的 App 就又只滚一次
	private static let copyInterval = 0.008

	private func boostIfNeeded(_ event: CGEvent) {
		let byCtrl = withLeftCtrl && leftCtrlDown && !rightCtrlDown
		// 自己补发的副本：只按需去掉 Ctrl（系统投递时可能按当前键盘状态补回），不再复制
		if event.getIntegerValueField(.eventSourceUserData) == Self.copyMarker {
			if byCtrl && !alwaysOn { stripLeftCtrl(event) }
			return
		}
		let copies = Int(factor.rounded()) - 1
		guard copies > 0 else { return }
		// Ctrl 没按着就把左右都当松开：切窗口丢了 flagsChanged 也不会卡在按下
		if !event.flags.contains(.maskControl) {
			leftCtrlDown = false
			rightCtrlDown = false
			guard alwaysOn else { return }
		}
		guard alwaysOn || byCtrl else { return }
		// 触控板 / Magic Mouse 的精确滚动不动
		guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return }

		// 左 Ctrl 只是加速开关，不透传给 App：带着 Ctrl 的滚轮在终端里会变成 Ctrl+滚轮上报
		// 被 TUI 忽略，微信等也不当普通滚动处理。一直加速时用户按 Ctrl 可能另有用途（缩放），不动
		if byCtrl && !alwaysOn { stripLeftCtrl(event) }

		guard let copy = event.copy() else { return }
		copy.setIntegerValueField(.eventSourceUserData, value: Self.copyMarker)
		for k in 1...copies {
			DispatchQueue.main.asyncAfter(deadline: .now() + Self.copyInterval * Double(k)) {
				copy.copy()?.post(tap: .cgSessionEventTap)
			}
		}
	}

	private func stripLeftCtrl(_ event: CGEvent) {
		event.flags = CGEventFlags(rawValue: event.flags.rawValue & ~Self.leftCtrlBit).subtracting(.maskControl)
	}
}
