import Cocoa

// MARK: - 鼠标滚轮加速
//
// 全局 CGEventTap 拦滚动事件，原事件放行后再补发「倍率 - 1」份副本，相当于滚了 N 次。
// 不放大单个事件的滚动量：微信、终端（Claude Code 等 TUI 收到的是一次一条鼠标上报）
// 按事件次数滚，不看数值大小，放大数值对它们无效。副本打上 eventSourceUserData 标记，
// 回到 tap 时直接放行，不会回灌。只处理非精确滚动：鼠标滚轮是 line-based，触控板两指
// 滚动和 Magic Mouse 是精确滚动（scrollWheelEventIsContinuous = 1），保持系统原速。
//
// 两种触发：全局常驻加速开关；按住加速键时临时加速。加速键可选左 / 右侧的 Ctrl、Option、
// Cmd、Shift（只认选中那一侧，另一侧照常当修饰键用）。通用修饰键标志不分左右，所以另外听
// flagsChanged（单按修饰键只发这个，不发 keyDown / keyUp），按 keyCode 和设备相关标志位
// 记两侧各自是否按着。
//
// 需要辅助功能权限；没权限时 tap 建不出来，设置窗口里显示「需要辅助功能权限」。

/// 按住加速的修饰键；rawValue 存 UserDefaults
enum BoostKey: String, CaseIterable {
	case none, leftCtrl, rightCtrl, leftOption, rightOption, leftCmd, rightCmd, leftShift, rightShift

	var title: String {
		switch self {
		case .none: return "不用"
		case .leftCtrl: return "左 Ctrl"
		case .rightCtrl: return "右 Ctrl"
		case .leftOption: return "左 Option"
		case .rightOption: return "右 Option"
		case .leftCmd: return "左 Cmd"
		case .rightCmd: return "右 Cmd"
		case .leftShift: return "左 Shift"
		case .rightShift: return "右 Shift"
		}
	}

	/// 本侧 keyCode、本侧 / 另一侧设备标志位（IOKit NX_DEVICE*KEYMASK）、通用标志
	fileprivate typealias Spec = (keyCode: Int64, otherKeyCode: Int64, bit: UInt64, otherBit: UInt64, mask: CGEventFlags)
	fileprivate var spec: Spec? {
		switch self {
		case .none: return nil
		case .leftCtrl: return (59, 62, 0x0001, 0x2000, .maskControl)
		case .rightCtrl: return (62, 59, 0x2000, 0x0001, .maskControl)
		case .leftShift: return (56, 60, 0x0002, 0x0004, .maskShift)
		case .rightShift: return (60, 56, 0x0004, 0x0002, .maskShift)
		case .leftCmd: return (55, 54, 0x0008, 0x0010, .maskCommand)
		case .rightCmd: return (54, 55, 0x0010, 0x0008, .maskCommand)
		case .leftOption: return (58, 61, 0x0020, 0x0040, .maskAlternate)
		case .rightOption: return (61, 58, 0x0040, 0x0020, .maskAlternate)
		}
	}
}

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

	/// 按住哪个键滚动时临时加速（默认左 Ctrl）
	var boostKey: BoostKey {
		get { Self.d.string(forKey: "scrollBoostKey").flatMap(BoostKey.init) ?? .leftCtrl }
		set {
			Self.d.set(newValue.rawValue, forKey: "scrollBoostKey")
			keyDown = false
			otherKeyDown = false
			refresh()
		}
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
	var active: Bool { alwaysOn || boostKey != .none }

	// MARK: - 状态

	/// tap 建不出来（没辅助功能权限）
	private(set) var unavailable = false

	private var tap: CFMachPort?
	private var source: CFRunLoopSource?
	/// 加速键本侧 / 另一侧是否按着
	private var keyDown = false
	private var otherKeyDown = false

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
		keyDown = false
		otherKeyDown = false
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
			trackKey(event)
		case .scrollWheel:
			boostIfNeeded(event)
		default:
			break
		}
	}

	private func trackKey(_ event: CGEvent) {
		guard let s = boostKey.spec else { return }
		let raw = event.flags.rawValue
		switch event.getIntegerValueField(.keyboardEventKeycode) {
		case s.keyCode: keyDown = raw & s.bit != 0
		case s.otherKeyCode: otherKeyDown = raw & s.otherBit != 0
		default: break
		}
	}

	/// 补发副本的标记（"QIBS"），回到 tap 时据此放行
	private static let copyMarker: Int64 = 0x5149_4253
	/// 副本间隔：连着发会被 App 合并成一个事件，按次数滚的 App 就又只滚一次
	private static let copyInterval = 0.008

	private func boostIfNeeded(_ event: CGEvent) {
		let spec = boostKey.spec
		let byKey = spec != nil && keyDown && !otherKeyDown
		// 自己补发的副本：只按需去掉加速键（系统投递时可能按当前键盘状态补回），不再复制
		if event.getIntegerValueField(.eventSourceUserData) == Self.copyMarker {
			if byKey && !alwaysOn, let spec { strip(spec, from: event) }
			return
		}
		let copies = Int(factor.rounded()) - 1
		guard copies > 0 else { return }
		// 加速键那类修饰键没按着就把两侧都当松开：切窗口丢了 flagsChanged 也不会卡在按下
		if let spec, !event.flags.contains(spec.mask) {
			keyDown = false
			otherKeyDown = false
			guard alwaysOn else { return }
		}
		guard alwaysOn || byKey else { return }
		// 触控板 / Magic Mouse 的精确滚动不动
		guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return }

		// 加速键只是开关，不透传给 App：带着 Ctrl 的滚轮在终端里会变成 Ctrl+滚轮上报被 TUI 忽略，
		// Shift+滚轮会变横向滚动。一直加速时用户按修饰键可能另有用途（缩放），不动
		if byKey && !alwaysOn, let spec { strip(spec, from: event) }

		guard let copy = event.copy() else { return }
		copy.setIntegerValueField(.eventSourceUserData, value: Self.copyMarker)
		for k in 1...copies {
			DispatchQueue.main.asyncAfter(deadline: .now() + Self.copyInterval * Double(k)) {
				copy.copy()?.post(tap: .cgSessionEventTap)
			}
		}
	}

	/// 另一侧没按着才会走到这里，所以连通用标志一起去掉
	private func strip(_ spec: BoostKey.Spec, from event: CGEvent) {
		event.flags = CGEventFlags(rawValue: event.flags.rawValue & ~spec.bit).subtracting(spec.mask)
	}
}
