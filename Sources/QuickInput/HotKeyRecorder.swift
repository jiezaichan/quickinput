import Cocoa

// MARK: - 快捷键录制控件

final class HotKeyRecorder: NSView {
	var onChange: ((UInt32?, UInt32) -> Void)?

	private let label = NSTextField(labelWithString: "未设置")
	private var monitor: Any?
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
		label.stringValue = recording ? "按下组合键…（esc 取消，⌫ 清除）"
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
		monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] ev in
			guard let self = self else { return ev }
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
		recording = false
	}
}
