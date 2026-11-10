import Cocoa

// MARK: - 搜索面板（圆盘）
//
// 一个总快捷键在鼠标处弹出圆盘：一圈切成 9 格，每格一个片段，从正上方顺时针排；中间是搜索框。
// 鼠标往哪个方向移就选中哪格（不用移到格子上，中心一圈是死区），单击输入；
// 打字筛选（名称命中优先、再匹配内容），数字键 1~9 直接输入对应格，←→↑↓ 转动选择、↩ 输入、Tab / 滚轮翻页、esc 关闭。
// 格位固定 9 个，片段不满时空着，同一个片段总在同一个方向，用熟了闭眼甩鼠标就行。
// 用 nonactivatingPanel：面板能接收键盘，但不把原来的 App 挤到后台，
// 关掉面板后焦点自然回到原来的光标处，再发按键。

final class SearchPanel: NSPanel, NSTextFieldDelegate, NSWindowDelegate {
	static let shared = SearchPanel()

	static let slots = 9
	static let size: CGFloat = 380
	static let outerR: CGFloat = 180
	static let innerR: CGFloat = 66

	private let field = NSTextField()
	private let ring = RingView()
	private var results: [Snippet] = []
	private var page = 0
	private var previousApp: NSRunningApplication?

	override var canBecomeKey: Bool { true }

	private init() {
		let s = SearchPanel.size
		super.init(contentRect: NSRect(x: 0, y: 0, width: s, height: s),
		           styleMask: [.nonactivatingPanel, .borderless],
		           backing: .buffered,
		           defer: true)
		isOpaque = false
		backgroundColor = .clear
		hasShadow = true
		level = .floating
		hidesOnDeactivate = false
		isReleasedWhenClosed = false
		acceptsMouseMovedEvents = true
		collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
		delegate = self
		buildUI()
	}

	private func buildUI() {
		let s = SearchPanel.size
		let root = NSView(frame: NSRect(x: 0, y: 0, width: s, height: s))
		contentView = root

		// 毛玻璃只留圆盘那一块，窗口阴影跟着圆走
		let bg = NSVisualEffectView(frame: root.bounds)
		bg.material = .popover
		bg.state = .active
		bg.maskImage = NSImage(size: root.bounds.size, flipped: false) { rect in
			let r = SearchPanel.outerR
			NSBezierPath(ovalIn: NSRect(x: rect.midX - r, y: rect.midY - r, width: r * 2, height: r * 2)).fill()
			return true
		}
		root.addSubview(bg)

		ring.frame = root.bounds
		ring.panel = self
		root.addSubview(ring)

		field.frame = NSRect(x: s / 2 - 52, y: s / 2 + 4, width: 104, height: 24)
		field.font = .systemFont(ofSize: 15)
		field.alignment = .center
		field.placeholderString = "搜索"
		field.isBordered = false
		field.drawsBackground = false
		field.focusRingType = .none
		field.delegate = self
		root.addSubview(field)
	}

	// MARK: 显示与关闭

	func toggle() {
		isVisible ? dismiss() : show()
	}

	func show() {
		previousApp = NSWorkspace.shared.frontmostApplication
		field.stringValue = ""
		filter()
		// 圆心对准鼠标；靠屏幕边缘时整体挪进可见区域
		let mouse = NSEvent.mouseLocation
		let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
		var origin = NSPoint(x: mouse.x - frame.width / 2, y: mouse.y - frame.height / 2)
		if let vf = screen?.visibleFrame {
			origin.x = max(vf.minX, min(vf.maxX - frame.width, origin.x))
			origin.y = max(vf.minY, min(vf.maxY - frame.height, origin.y))
		}
		setFrameOrigin(origin)
		alphaValue = 0
		orderFrontRegardless()
		makeKey()
		makeFirstResponder(field)
		invalidateShadow()
		NSAnimationContext.runAnimationGroup { ctx in
			ctx.duration = 0.12
			animator().alphaValue = 1
		}
	}

	/// 数字键 1~9 直接输入对应格；输入法正在选词（数字选候选）时不拦
	override func sendEvent(_ event: NSEvent) {
		if event.type == .keyDown,
		   event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
		   let n = Int(event.charactersIgnoringModifiers ?? ""), (1...SearchPanel.slots).contains(n),
		   (fieldEditor(false, for: field) as? NSTextView)?.hasMarkedText() != true {
			commit(slot: n - 1)
			return
		}
		super.sendEvent(event)
	}

	private func dismiss() {
		orderOut(nil)
		if let p = previousApp, p != NSRunningApplication.current, !p.isActive { p.activate() }
	}

	func windowDidResignKey(_ notification: Notification) {
		if isVisible { orderOut(nil) }
	}

	// MARK: 筛选、翻页与选择

	/// 当前页的 9 个格位，没片段的格为 nil
	var pageSnippets: [Snippet?] {
		let start = page * SearchPanel.slots
		return (0..<SearchPanel.slots).map { start + $0 < results.count ? results[start + $0] : nil }
	}

	var pageCount: Int { max(1, (results.count + SearchPanel.slots - 1) / SearchPanel.slots) }
	var currentPage: Int { page }
	var hasQuery: Bool { !field.stringValue.isEmpty }

	/// 名称命中排在内容命中前面，各自保持原顺序
	private func filter() {
		let q = field.stringValue.trimmingCharacters(in: .whitespaces)
		let all = Store.shared.snippets
		if q.isEmpty {
			results = all
		} else {
			let byName = all.filter { $0.name.localizedCaseInsensitiveContains(q) }
			let byText = all.filter { !$0.name.localizedCaseInsensitiveContains(q) && $0.text.localizedCaseInsensitiveContains(q) }
			results = byName + byText
		}
		page = 0
		ring.selected = results.isEmpty ? nil : 0
		ring.needsDisplay = true
	}

	func turnPage(_ delta: Int) {
		guard pageCount > 1 else { return }
		page = (page + delta + pageCount) % pageCount
		ring.selected = 0
		ring.needsDisplay = true
	}

	/// 顺 / 逆时针转到下一个有片段的格
	private func rotate(_ delta: Int) {
		let slots = pageSnippets
		guard slots.contains(where: { $0 != nil }) else { return }
		var i = ring.selected ?? (delta > 0 ? -1 : 0)
		repeat {
			i = (i + delta + SearchPanel.slots) % SearchPanel.slots
		} while slots[i] == nil
		ring.selected = i
		ring.needsDisplay = true
	}

	func commit(slot: Int?) {
		guard let slot, let snippet = pageSnippets[slot] else { return }
		dismiss()
		// 等焦点回到原来的 App
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { Typer.insert(snippet) }
	}

	// MARK: 搜索框

	func controlTextDidChange(_ obj: Notification) {
		filter()
	}

	func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		switch selector {
		case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveLeft(_:)): rotate(-1)
		case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveRight(_:)): rotate(1)
		case #selector(NSResponder.insertTab(_:)): turnPage(1)
		case #selector(NSResponder.insertBacktab(_:)): turnPage(-1)
		case #selector(NSResponder.insertNewline(_:)): commit(slot: ring.selected)
		case #selector(NSResponder.cancelOperation(_:)): dismiss()
		default: return false
		}
		return true
	}
}

// MARK: - 圆盘

private final class RingView: NSView {
	weak var panel: SearchPanel?
	var selected: Int?
	private var scrollAcc: CGFloat = 0

	private var center: NSPoint { NSPoint(x: bounds.midX, y: bounds.midY) }

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		trackingAreas.forEach(removeTrackingArea)
		addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
	}

	/// 格 i 的中心角（数学坐标系，度）：0 号在正上方，顺时针递增
	private func angle(of i: Int) -> CGFloat {
		90 - CGFloat(i) * 360 / CGFloat(SearchPanel.slots)
	}

	/// 按方向取格，中心死区内返回 nil
	private func slot(at p: NSPoint) -> Int? {
		let dx = p.x - center.x, dy = p.y - center.y
		guard hypot(dx, dy) > SearchPanel.innerR else { return nil }
		let deg = atan2(dy, dx) * 180 / .pi
		let step = 360 / CGFloat(SearchPanel.slots)
		let i = Int(((90 - deg) / step).rounded())
		return (i % SearchPanel.slots + SearchPanel.slots) % SearchPanel.slots
	}

	override func mouseMoved(with event: NSEvent) {
		let p = convert(event.locationInWindow, from: nil)
		guard let i = slot(at: p), panel?.pageSnippets[i] != nil, i != selected else { return }
		selected = i
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent) {
		let p = convert(event.locationInWindow, from: nil)
		// 圆外的角落点击当作关闭
		if hypot(p.x - center.x, p.y - center.y) > SearchPanel.outerR {
			window?.orderOut(nil)
			return
		}
		panel?.commit(slot: slot(at: p))
	}

	override func scrollWheel(with event: NSEvent) {
		scrollAcc += event.scrollingDeltaY
		let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 30 : 1
		if abs(scrollAcc) >= threshold {
			panel?.turnPage(scrollAcc > 0 ? -1 : 1)
			scrollAcc = 0
		}
	}

	private func point(_ angle: CGFloat, _ r: CGFloat) -> NSPoint {
		let rad = angle * .pi / 180
		return NSPoint(x: center.x + cos(rad) * r, y: center.y + sin(rad) * r)
	}

	/// 扇环；两侧按固定像素留缝，缝宽内外一致
	private func sectorPath(_ a: CGFloat, from r0: CGFloat, to r1: CGFloat, gap: CGFloat) -> NSBezierPath {
		let half = 180 / CGFloat(SearchPanel.slots)
		let d0 = asin(gap / 2 / r0) * 180 / .pi, d1 = asin(gap / 2 / r1) * 180 / .pi
		let path = NSBezierPath()
		path.appendArc(withCenter: center, radius: r1, startAngle: a + half - d1, endAngle: a - half + d1, clockwise: true)
		path.appendArc(withCenter: center, radius: r0, startAngle: a - half + d0, endAngle: a + half - d0, clockwise: false)
		path.close()
		return path
	}

	override func draw(_ dirtyRect: NSRect) {
		guard let panel else { return }
		let slots = panel.pageSnippets
		let c = center
		let outer = SearchPanel.outerR, inner = SearchPanel.innerR
		let accent = NSColor.controlAccentColor
		let r0 = inner + 6, r1 = outer - 6

		// 外缘一圈细高光，像玻璃边
		let rim = NSBezierPath(ovalIn: NSRect(x: c.x - outer + 0.5, y: c.y - outer + 0.5, width: outer * 2 - 1, height: outer * 2 - 1))
		rim.lineWidth = 1
		NSColor.white.withAlphaComponent(0.18).setStroke()
		rim.stroke()

		for i in 0..<SearchPanel.slots {
			let a = angle(of: i)
			let sector = sectorPath(a, from: r0, to: r1, gap: 4)
			let isSel = i == selected && slots[i] != nil

			if isSel {
				let g = NSGradient(starting: accent.blended(withFraction: 0.25, of: .white) ?? accent, ending: accent)
				g?.draw(in: sector, angle: a + 180)
			} else {
				NSColor.labelColor.withAlphaComponent(slots[i] == nil ? 0.03 : 0.07).setFill()
				sector.fill()
			}

			// 编号徽标，对应数字键 1~9
			let bp = point(a, r1 - 15)
			let badge = NSBezierPath(ovalIn: NSRect(x: bp.x - 8, y: bp.y - 8, width: 16, height: 16))
			(isSel ? NSColor.white.withAlphaComponent(0.28) : NSColor.labelColor.withAlphaComponent(slots[i] == nil ? 0.04 : 0.1)).setFill()
			badge.fill()
			let numAttrs: [NSAttributedString.Key: Any] = [
				.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
				.foregroundColor: isSel ? NSColor.white : NSColor.secondaryLabelColor.withAlphaComponent(slots[i] == nil ? 0.4 : 1),
			]
			let num = "\(i + 1)" as NSString
			let ns = num.size(withAttributes: numAttrs)
			num.draw(at: NSPoint(x: bp.x - ns.width / 2, y: bp.y - ns.height / 2), withAttributes: numAttrs)

			guard let s = slots[i] else { continue }
			let hint = s.keyCode == nil ? "" : Keys.describe(keyCode: s.keyCode, modifiers: s.modifiers)
			drawLabel(s.name, hint: hint, at: point(a, (r0 + r1) / 2 - 11), selected: isSel)
		}

		// 中心圆：搜索框在上半，选中片段的内容预览在下半
		let hubR = inner - 2
		let hub = NSBezierPath(ovalIn: NSRect(x: c.x - hubR, y: c.y - hubR, width: hubR * 2, height: hubR * 2))
		NSColor.controlBackgroundColor.withAlphaComponent(0.55).setFill()
		hub.fill()
		hub.lineWidth = 0.5
		NSColor.separatorColor.setStroke()
		hub.stroke()

		// 中心圆边上一段弧指向选中的格
		if let i = selected, slots[i] != nil {
			let a = angle(of: i)
			let arc = NSBezierPath()
			arc.appendArc(withCenter: c, radius: hubR - 1.5, startAngle: a - 16, endAngle: a + 16)
			arc.lineWidth = 3
			arc.lineCapStyle = .round
			accent.setStroke()
			arc.stroke()
		}

		var preview = ""
		if let i = selected, let s = slots[i] {
			preview = s.text.replacingOccurrences(of: "\n", with: " ⏎ ") + (s.pressEnter ? "  ↩" : "")
		} else if slots.allSatisfy({ $0 == nil }) {
			preview = panel.hasQuery ? "没有匹配的片段" : "还没有片段"
		}
		if panel.pageCount > 1 {
			preview += (preview.isEmpty ? "" : "\n") + "\(panel.currentPage + 1)/\(panel.pageCount)  Tab 翻页"
		}
		let para = NSMutableParagraphStyle()
		para.alignment = .center
		para.lineBreakMode = .byTruncatingTail
		let attrs: [NSAttributedString.Key: Any] = [
			.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
			.foregroundColor: NSColor.secondaryLabelColor,
			.paragraphStyle: para,
		]
		let box = NSRect(x: c.x - 46, y: c.y - 42, width: 92, height: 38)
		(preview as NSString).draw(in: box, withAttributes: attrs)
	}

	private func drawLabel(_ name: String, hint: String, at p: NSPoint, selected: Bool) {
		let para = NSMutableParagraphStyle()
		para.alignment = .center
		para.lineBreakMode = .byWordWrapping
		let nameAttrs: [NSAttributedString.Key: Any] = [
			.font: NSFont.systemFont(ofSize: 13, weight: .medium),
			.foregroundColor: selected ? NSColor.white : NSColor.labelColor,
			.paragraphStyle: para,
		]
		let hintAttrs: [NSAttributedString.Key: Any] = [
			.font: NSFont.systemFont(ofSize: 10),
			.foregroundColor: selected ? NSColor.white.withAlphaComponent(0.8) : NSColor.secondaryLabelColor,
			.paragraphStyle: para,
		]
		let w: CGFloat = 74
		let opts: NSString.DrawingOptions = [.usesLineFragmentOrigin]
		let nameH = min(34, ceil((name as NSString).boundingRect(with: NSSize(width: w, height: 1000), options: opts, attributes: nameAttrs).height))
		let hintH: CGFloat = hint.isEmpty ? 0 : 14
		let top = p.y + (nameH + hintH) / 2
		(name as NSString).draw(in: NSRect(x: p.x - w / 2, y: top - nameH, width: w, height: nameH), withAttributes: nameAttrs)
		if !hint.isEmpty {
			(hint as NSString).draw(in: NSRect(x: p.x - w / 2, y: top - nameH - hintH, width: w, height: hintH), withAttributes: hintAttrs)
		}
	}
}
