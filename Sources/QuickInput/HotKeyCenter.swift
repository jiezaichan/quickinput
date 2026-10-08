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

	func reload() {
		installHandlerIfNeeded()
		for ref in refs { UnregisterEventHotKey(ref) }
		refs.removeAll()
		idToSnippet.removeAll()
		failed.removeAll()
		panelFailed = false

		// 面板先注册：与片段撞键时片段显示「被占用」
		if let keyCode = PanelHotKey.keyCode {
			panelFailed = !register(keyCode: keyCode, modifiers: PanelHotKey.modifiers, id: panelID)
		}
		for snippet in Store.shared.snippets {
			guard let keyCode = snippet.keyCode else { continue }
			if register(keyCode: keyCode, modifiers: snippet.modifiers, id: nextID) {
				idToSnippet[nextID] = snippet.id
				nextID += 1
			} else {
				failed.insert(snippet.id)
			}
		}
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

	func handle(id: UInt32) {
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
