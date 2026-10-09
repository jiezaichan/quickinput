import Foundation
import CoreGraphics
import Carbon.HIToolbox

// MARK: - 输入

enum Typer {
	/// 触发瞬间用户多半还按着修饰键，直接发事件会被叠加成组合键。
	/// 这里先等修饰键全部抬起（最多等 600ms）再发。
	/// hidLevel：从 HID 层发事件。系统设置等 App 的密码框开着安全输入时只收 HID 层事件，
	/// 会话层（默认）发的会被丢掉（已实测）；SecurityAgent 两层都收。普通片段仍走会话层
	static func insert(_ text: String, pressEnter: Bool = false, hidLevel: Bool = false) {
		guard !text.isEmpty else { return }
		waitForModifiersRelease(attempt: 0) {
			post(text, hidLevel: hidLevel)
			// 隔 200ms 再回车：等目标 App（尤其终端、输入法）吃完文字，免得回车抢在前面
			if pressEnter { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { postReturn(hidLevel: hidLevel) } }
		}
	}

	static func insert(_ snippet: Snippet) {
		insert(snippet.text, pressEnter: snippet.pressEnter)
	}

	private static func waitForModifiersRelease(attempt: Int, then done: @escaping () -> Void) {
		let watched: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
		let current = CGEventSource.flagsState(.combinedSessionState)
		if current.intersection(watched).isEmpty || attempt >= 20 {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: done)
		} else {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
				waitForModifiersRelease(attempt: attempt + 1, then: done)
			}
		}
	}

	private static func source(hidLevel: Bool) -> CGEventSource? {
		CGEventSource(stateID: hidLevel ? .hidSystemState : .combinedSessionState)
	}

	private static func tap(hidLevel: Bool) -> CGEventTapLocation {
		hidLevel ? .cghidEventTap : .cgAnnotatedSessionEventTap
	}

	private static func post(_ text: String, hidLevel: Bool) {
		guard let src = source(hidLevel: hidLevel) else { return }
		let units = Array(text.utf16)
		// HID 层逐字发（与实测打得进去的方式一致），会话层每批 16 个
		let chunk = hidLevel ? 1 : 16
		var i = 0
		while i < units.count {
			let end = min(i + chunk, units.count)
			var buf = Array(units[i ..< end])
			for isDown in [true, false] {
				guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: isDown) else { continue }
				e.flags = []
				e.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: &buf)
				e.post(tap: tap(hidLevel: hidLevel))
			}
			i = end
			if i < units.count { usleep(hidLevel ? 10000 : 1500) }
		}
	}

	private static func postReturn(hidLevel: Bool) {
		guard let src = source(hidLevel: hidLevel) else { return }
		for isDown in [true, false] {
			guard let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Return), keyDown: isDown) else { continue }
			e.flags = []
			e.post(tap: tap(hidLevel: hidLevel))
		}
	}
}
