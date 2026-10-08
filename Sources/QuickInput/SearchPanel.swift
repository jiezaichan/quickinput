import Cocoa

// MARK: - 搜索面板
//
// 一个总快捷键呼出，打字筛选、↑↓ 选择、↩ 输入、esc 关闭。片段多了以后不必每条都占一个快捷键。
// 用 nonactivatingPanel：面板能接收键盘，但不把原来的 App 挤到后台，
// 关掉面板后焦点自然回到原来的光标处，再发按键。

final class SearchPanel: NSPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
	static let shared = SearchPanel()

	private let field = NSTextField()
	private let table = NSTableView()
	private var results: [Snippet] = []
	private var previousApp: NSRunningApplication?

	override var canBecomeKey: Bool { true }

	private init() {
		super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 340),
		           styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
		           backing: .buffered,
		           defer: true)
		titleVisibility = .hidden
		titlebarAppearsTransparent = true
		for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
			standardWindowButton(b)?.isHidden = true
		}
		isMovableByWindowBackground = true
		level = .floating
		hidesOnDeactivate = false
		isReleasedWhenClosed = false
		collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
		delegate = self
		buildUI()
	}

	private func buildUI() {
		let bg = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 560, height: 340))
		bg.material = .menu
		bg.state = .active
		contentView = bg

		field.frame = NSRect(x: 18, y: 290, width: 524, height: 30)
		field.font = .systemFont(ofSize: 18)
		field.placeholderString = "搜索片段（↑↓ 选择，↩ 输入，esc 关闭）"
		field.isBordered = false
		field.drawsBackground = false
		field.focusRingType = .none
		field.delegate = self
		bg.addSubview(field)

		let line = NSBox(frame: NSRect(x: 0, y: 278, width: 560, height: 1))
		line.boxType = .separator
		bg.addSubview(line)

		let scroll = NSScrollView(frame: NSRect(x: 8, y: 8, width: 544, height: 266))
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = false
		table.headerView = nil
		table.backgroundColor = .clear
		table.rowHeight = 28
		table.intercellSpacing = NSSize(width: 0, height: 2)
		table.dataSource = self
		table.delegate = self
		table.target = self
		table.doubleAction = #selector(doubleClicked)
		for (key, width) in [("name", 150.0), ("key", 100.0), ("text", 280.0)] {
			let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
			col.width = width
			table.addTableColumn(col)
		}
		scroll.documentView = table
		bg.addSubview(scroll)
	}

	// MARK: 显示与关闭

	func toggle() {
		isVisible ? dismiss() : show()
	}

	func show() {
		previousApp = NSWorkspace.shared.frontmostApplication
		field.stringValue = ""
		filter()
		// 出现在鼠标所在屏幕的偏上位置
		let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
		if let vf = screen?.visibleFrame {
			setFrameOrigin(NSPoint(x: vf.midX - frame.width / 2, y: vf.minY + vf.height * 0.62 - frame.height / 2))
		}
		orderFrontRegardless()
		makeKey()
		makeFirstResponder(field)
	}

	private func dismiss() {
		orderOut(nil)
		if let p = previousApp, p != NSRunningApplication.current, !p.isActive { p.activate() }
	}

	func windowDidResignKey(_ notification: Notification) {
		if isVisible { orderOut(nil) }
	}

	// MARK: 筛选与选择

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
		table.reloadData()
		if !results.isEmpty {
			table.selectRowIndexes([0], byExtendingSelection: false)
			table.scrollRowToVisible(0)
		}
	}

	private func move(_ delta: Int) {
		guard !results.isEmpty else { return }
		let row = max(0, min(results.count - 1, table.selectedRow + delta))
		table.selectRowIndexes([row], byExtendingSelection: false)
		table.scrollRowToVisible(row)
	}

	private func commit(row: Int) {
		guard row >= 0, row < results.count else { return }
		let snippet = results[row]
		dismiss()
		// 等焦点回到原来的 App
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { Typer.insert(snippet) }
	}

	@objc private func doubleClicked() {
		commit(row: table.clickedRow)
	}

	// MARK: 搜索框

	func controlTextDidChange(_ obj: Notification) {
		filter()
	}

	func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		switch selector {
		case #selector(NSResponder.moveUp(_:)): move(-1)
		case #selector(NSResponder.moveDown(_:)): move(1)
		case #selector(NSResponder.insertNewline(_:)): commit(row: table.selectedRow)
		case #selector(NSResponder.cancelOperation(_:)): dismiss()
		default: return false
		}
		return true
	}

	// MARK: NSTableView

	func numberOfRows(in tableView: NSTableView) -> Int { results.count }

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let s = results[row]
		var text = ""
		var color = NSColor.labelColor
		var font = NSFont.systemFont(ofSize: 14)

		switch tableColumn?.identifier.rawValue {
		case "name":
			text = s.name
			font = .systemFont(ofSize: 14, weight: .medium)
		case "key":
			text = s.keyCode == nil ? "" : Keys.describe(keyCode: s.keyCode, modifiers: s.modifiers)
			color = .secondaryLabelColor
			font = .systemFont(ofSize: 12)
		default:
			text = s.text.replacingOccurrences(of: "\n", with: " ⏎ ") + (s.pressEnter ? "  ↩" : "")
			color = .secondaryLabelColor
			font = .monospacedSystemFont(ofSize: 12, weight: .regular)
		}

		let cell = NSTableCellView()
		let tf = NSTextField(labelWithString: text)
		tf.textColor = color
		tf.font = font
		tf.lineBreakMode = .byTruncatingTail
		tf.translatesAutoresizingMaskIntoConstraints = false
		cell.addSubview(tf)
		NSLayoutConstraint.activate([
			tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
			tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
			tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
		])
		return cell
	}
}
