import Foundation
import Carbon.HIToolbox

// MARK: - 全局热键

private func hotKeyCallback(_ next: EventHandlerCallRef?,
                            _ event: EventRef?,
                            _ userData: UnsafeMutableRawPointer?) -> OSStatus {
	var hkID = EventHotKeyID()
	let status = GetEventParameter(event,
	                               EventParamName(kEventParamDirectObject),
	                               EventParamType(typeEventHotKeyID),
	                               nil,
	                               MemoryLayout<EventHotKeyID>.size,
	                               nil,
	                               &hkID)
	if status == noErr { HotKeyCenter.shared.handle(id: hkID.id) }
	return noErr
}

/// 呼出搜索面板的快捷键。属于本机设置，存 UserDefaults，不随片段导入导出
enum PanelHotKey {
	private static let d = UserDefaults.standard

	/// 未设置过时默认 ⌃⌥⌘空格；清除绑定存 -1
	static var keyCode: UInt32? {
		get {
			guard d.object(forKey: "panelKeyCode") != nil else { return UInt32(kVK_Space) }
			let v = d.integer(forKey: "panelKeyCode")
			return v < 0 ? nil : UInt32(v)
		}
		set { d.set(newValue.map { Int($0) } ?? -1, forKey: "panelKeyCode") }
	}

	static var modifiers: UInt32 {
		get {
			guard d.object(forKey: "panelModifiers") != nil else { return UInt32(controlKey | optionKey | cmdKey) }
			return UInt32(d.integer(forKey: "panelModifiers"))
		}
		set { d.set(Int(newValue), forKey: "panelModifiers") }
	}
}

final class HotKeyCenter {
	static let shared = HotKeyCenter()

	/// 注册失败（快捷键被别的 App 或面板快捷键占用）的片段
	private(set) var failed: Set<UUID> = []
	private(set) var panelFailed = false

	/// 片段的热键 id 从 1 递增，0 留给搜索面板
	private let panelID: UInt32 = 0
	private var refs: [EventHotKeyRef] = []
	private var idToSnippet: [UInt32: UUID] = [:]
	private var handlerInstalled = false
	private var nextID: UInt32 = 1

	// MARK: 鼠标侧键
	//
	// Carbon 只能注册键盘热键，侧键改由 CGEventTap 拦 otherMouseDown（和 ScrollBoost 同一套机制）。
	// 命中时返回 nil 吃掉事件，绑定后浏览器不再同时后退/前进；没绑定或修饰键不符就原样放行。

	private var mouseToID: [Int64: UInt32] = [:]
	private var mouseModifiers: [Int64: CGEventFlags] = [:]
	private var mouseTap: CFMachPort?
	private var mouseSource: CFRunLoopSource?
	private var lastMouseFire: TimeInterval = 0

	/// 录制快捷键期间临时放行，免得按下已绑定的侧键又触发一遍动作
	var mouseTapSuspended = false

	/// tap 建不出来（没辅助功能权限）
	private(set) var mouseUnavailable = false

	func reload() {
		installHandlerIfNeeded()
		for ref in refs { UnregisterEventHotKey(ref) }
		refs.removeAll()
		idToSnippet.removeAll()
		failed.removeAll()
		panelFailed = false
		mouseToID.removeAll()
		mouseModifiers.removeAll()

		// 面板先注册：与片段撞键时片段显示「被占用」
		if let keyCode = PanelHotKey.keyCode {
			panelFailed = !registerAny(keyCode: keyCode, modifiers: PanelHotKey.modifiers, id: panelID)
		}
		for snippet in Store.shared.snippets {
			guard let keyCode = snippet.keyCode else { continue }
			if registerAny(keyCode: keyCode, modifiers: snippet.modifiers, id: nextID) {
				idToSnippet[nextID] = snippet.id
				nextID += 1
			} else {
				failed.insert(snippet.id)
			}
		}
		refreshMouseTap()
	}

	private func registerAny(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> Bool {
		Keys.isMouseKey(keyCode)
			? registerMouse(keyCode: keyCode, modifiers: modifiers, id: id)
			: register(keyCode: keyCode, modifiers: modifiers, id: id)
	}

	/// 鼠标键不向系统注册，只记进映射表；同一个键先到先得（面板优先）
	private func registerMouse(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> Bool {
		let button = Int64(keyCode - Keys.mouseKeyBase)
		guard mouseToID[button] == nil else { return false }
		mouseToID[button] = id
		mouseModifiers[button] = Keys.eventFlags(from: modifiers)
		return true
	}

	private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> Bool {
		var ref: EventHotKeyRef?
		let hkID = EventHotKeyID(signature: OSType(0x5354_464C), id: id)
		let status = RegisterEventHotKey(keyCode,
		                                 modifiers,
		                                 hkID,
		                                 GetApplicationEventTarget(),
		                                 0,
		                                 &ref)
		guard status == noErr, let ref = ref else { return false }
		refs.append(ref)
		return true
	}

	// MARK: 鼠标侧键的 tap

	private func refreshMouseTap() {
		if mouseToID.isEmpty {
			uninstallMouseTap()
		} else {
			installMouseTapIfNeeded()
		}
	}

	private func installMouseTapIfNeeded() {
		guard mouseTap == nil else { return }
		let mask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
		guard let tap = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap,
		                                  place: .tailAppendEventTap,
		                                  options: .defaultTap,
		                                  eventsOfInterest: mask,
		                                  callback: HotKeyCenter.mouseCallback,
		                                  userInfo: nil) else {
			mouseUnavailable = true
			return
		}
		mouseTap = tap
		let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
		mouseSource = source
		CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
		CGEvent.tapEnable(tap: tap, enable: true)
		mouseUnavailable = false
	}

	private func uninstallMouseTap() {
		if let source = mouseSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
		if let tap = mouseTap { CGEvent.tapEnable(tap: tap, enable: false) }
		mouseSource = nil
		mouseTap = nil
		mouseUnavailable = false
	}

	private static let mouseCallback: CGEventTapCallBack = { _, type, event, _ in
		HotKeyCenter.shared.handleMouse(type: type, event: event)
	}

	private func handleMouse(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
		switch type {
		case .tapDisabledByTimeout, .tapDisabledByUserInput:
			if let tap = mouseTap { CGEvent.tapEnable(tap: tap, enable: true) }
			return Unmanaged.passUnretained(event)
		case .otherMouseDown:
			break
		default:
			return Unmanaged.passUnretained(event)
		}

		let button = event.getIntegerValueField(.mouseEventButtonNumber)
		guard let id = mouseToID[button] else { return Unmanaged.passUnretained(event) }
		let need = mouseModifiers[button] ?? []
		let have = event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
		guard !mouseTapSuspended, have == need else { return Unmanaged.passUnretained(event) }

		// 按住侧键可能被重复上报，0.25s 内只触发一次
		let now = ProcessInfo.processInfo.systemUptime
		guard now - lastMouseFire > 0.25 else { return nil }
		lastMouseFire = now

		DispatchQueue.main.async { self.handle(id: id) }
		return nil
	}

	// MARK: 授权框回车
	//
	// 授权框会锁住键盘焦点，别的窗口拿不到 ↩；但全局热键照样能收到（已实测）。
	// 所以只在授权框出现期间把裸 ↩ 注册成热键，用完立刻注销，平时的回车不受影响。
	// 单独存一个 ref，不进 refs，免得 reload() 把它注销掉。

	private let authReturnID = UInt32.max
	private var authReturnRef: EventHotKeyRef?

	func armAuthReturn() {
		guard authReturnRef == nil else { return }
		installHandlerIfNeeded()
		var ref: EventHotKeyRef?
		let hkID = EventHotKeyID(signature: OSType(0x5354_464C), id: authReturnID)
		if RegisterEventHotKey(UInt32(kVK_Return), 0, hkID, GetApplicationEventTarget(), 0, &ref) == noErr {
			authReturnRef = ref
		}
	}

	func disarmAuthReturn() {
		guard let ref = authReturnRef else { return }
		UnregisterEventHotKey(ref)
		authReturnRef = nil
	}

	func handle(id: UInt32) {
		if id == authReturnID {
			AuthAssist.shared.fill()
			return
		}
		if id == panelID {
			SearchPanel.shared.toggle()
			return
		}
		guard let sid = idToSnippet[id],
		      let snippet = Store.shared.snippets.first(where: { $0.id == sid }) else { return }
		Typer.insert(snippet)
	}

	private func installHandlerIfNeeded() {
		guard !handlerInstalled else { return }
		handlerInstalled = true
		var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
		                         eventKind: UInt32(kEventHotKeyPressed))
		InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &spec, nil, nil)
	}
}
