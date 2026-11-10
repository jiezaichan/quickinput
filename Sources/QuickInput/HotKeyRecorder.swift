import Cocoa

// MARK: - 快捷键录制控件

final class HotKeyRecorder: NSView {
	var onChange: ((UInt32?, UInt32) -> Void)?

	private let label = NSTextField(labelWithString: "未设置")
	private var monitor: Any?
	private var closeObserver: NSObjectProtocol?
	private var keyCode: UInt32?
	private var modifiers: UInt32 = 0
	private var recording = false { didSet { refresh() } }

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		label.alignment = .center
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)
		NSLayoutConstraint.activate([
			label.centerXAnchor.constraint(equalTo: centerXAnchor),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
		refresh()
	}

	required init?(coder: NSCoder) { fatalError() }

	func set(keyCode: UInt32?, modifiers: UInt32) {
		self.keyCode = keyCode
		self.modifiers = modifiers
		refresh()
	}

	private func refresh() {
		label.stringValue = recording ? "按下组合键或侧键…（esc 取消，⌫ 清除）"
		                              : Keys.describe(keyCode: keyCode, modifiers: modifiers)
		label.textColor = recording ? .secondaryLabelColor : .labelColor
		needsDisplay = true
	}

	/// 底色和边框在 draw 里画：系统动态色要在绘制时才按当前外观解析。
	/// 以前在 init 里取 .cgColor 塞给 layer，那时还没拿到窗口外观，浅色模式下会解析成黑底。
	override func draw(_ dirtyRect: NSRect) {
		let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
		NSColor.textBackgroundColor.setFill()
		path.fill()
		(recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
		path.lineWidth = 1
		path.stroke()
	}

	override func mouseDown(with event: NSEvent) {
		recording ? stopRecording() : startRecording()
	}

	private func startRecording() {
		recording = true
		// 录制期间放行全局侧键，免得按下已绑定的侧键又触发一遍动作
		HotKeyCenter.shared.mouseTapSuspended = true
		// 直接关掉设置窗口也要恢复，不能让侧键一直处于放行状态
		if let w = window {
			closeObserver = NotificationCenter.default.addObserver(
				forName: NSWindow.willCloseNotification, object: w, queue: .main
			) { [weak self] _ in self?.stopRecording() }
		}
		monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .otherMouseDown]) { [weak self] ev in
			guard let self = self else { return ev }

			if ev.type == .otherMouseDown {
				// 只收侧键（buttonNumber 3 / 4），中键、右键照常交给窗口
				let button = Int64(ev.buttonNumber)
				guard button >= 3 else { return ev }
				let code = Keys.mouseKey(button)
				let m = Keys.carbonModifiers(from: ev.modifierFlags.intersection(.deviceIndependentFlagsMask))
				self.keyCode = code
				self.modifiers = m
				self.stopRecording()
				self.onChange?(code, m)
				return nil
			}

			guard ev.type == .keyDown else { return nil }

			let code = UInt32(ev.keyCode)
			if code == 53 {                       // esc 取消
				self.stopRecording()
				return nil
			}
			if code == 51 {                       // ⌫ 清除绑定
				self.keyCode = nil
				self.modifiers = 0
				self.stopRecording()
				self.onChange?(nil, 0)
				return nil
			}

			let m = Keys.carbonModifiers(from: ev.modifierFlags.intersection(.deviceIndependentFlagsMask))
			// 无修饰键的普通字符不能当全局热键，会把整个系统的该字母吃掉
			if m == 0 && !Keys.fKeys.contains(code) {
				NSSound.beep()
				return nil
			}

			self.keyCode = code
			self.modifiers = m
			self.stopRecording()
			self.onChange?(code, m)
			return nil
		}
	}

	private func stopRecording() {
		if let m = monitor { NSEvent.removeMonitor(m) }
		monitor = nil
		if let o = closeObserver { NotificationCenter.default.removeObserver(o) }
		closeObserver = nil
		recording = false
		HotKeyCenter.shared.mouseTapSuspended = false
	}
}
