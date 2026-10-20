import Cocoa

// MARK: - 设置窗口

final class SettingsWC: NSWindowController, NSTableViewDataSource, NSTableViewDelegate,
                        NSTextFieldDelegate, NSTextViewDelegate {
	private let table = NSTableView()
	private let nameField = NSTextField()
	private let recorder = HotKeyRecorder(frame: .zero)
	private let textView = NSTextView()
	private let enterSwitch = NSSwitch()
	private let launchSwitch = NSSwitch()
	private let panelRecorder = HotKeyRecorder(frame: .zero)
	private let panelStatus = NSTextField(labelWithString: "")

	/// 卡片内左右留白
	private static let pad: CGFloat = 14

	convenience init() {
		let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
		                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
		                   backing: .buffered,
		                   defer: false)
		win.title = "速填 · 设置"
		win.contentMinSize = NSSize(width: 700, height: 500)
		win.center()
		self.init(window: win)
		buildUI()
		reloadFromStore()
	}

	// MARK: 界面
	//
	// 版式跟 shipbar 设置一致：左边片段列表，右边分组卡片（每项一行：左标题，右控件，行间细线）。

	private func buildUI() {
		guard let content = window?.contentView else { return }

		// —— 左：片段列表（inset 风格，每条两行 + 右侧快捷键）
		let scroll = NSScrollView()
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.borderType = .noBorder
		scroll.drawsBackground = false
		table.style = .inset
		table.headerView = nil
		table.rowHeight = 44
		table.backgroundColor = .clear
		table.dataSource = self
		table.delegate = self
		table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
		let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
		col.resizingMask = .autoresizingMask
		table.addTableColumn(col)
		scroll.documentView = table

		let listCard = Card()
		pin(scroll, in: listCard, inset: 1)

		// 列表下方：＋ / − 和导入导出
		let add = iconButton("plus", tip: "新增片段", action: #selector(addSnippet))
		let del = iconButton("minus", tip: "删除选中的片段", action: #selector(removeSnippet))
		let imp = smallButton("导入…", action: #selector(importSnippets))
		let exp = smallButton("导出…", action: #selector(exportSnippets))
		let listBar = hstack([add, del, NSView(), imp, exp], spacing: 4)

		let left = vstack([listCard, listBar], spacing: 8)
		listCard.setContentHuggingPriority(.init(1), for: .vertical)

		// —— 右：片段详情
		nameField.delegate = self
		nameField.bezelStyle = .roundedBezel
		nameField.placeholderString = "片段名称"
		nameField.translatesAutoresizingMaskIntoConstraints = false
		nameField.widthAnchor.constraint(equalToConstant: 260).isActive = true

		recorder.onChange = { [weak self] code, mods in
			guard let self = self, let row = self.selectedRow else { return }
			Store.shared.snippets[row].keyCode = code
			Store.shared.snippets[row].modifiers = mods
			self.applyChanges()
		}
		size(recorder, width: 260, height: 26)

		enterSwitch.target = self
		enterSwitch.action = #selector(toggleEnter)
		enterSwitch.controlSize = .small

		let snippetCard = group([
			formRow("名称", nil, nameField),
			formRow("快捷键", "点框录制 · esc 取消 · ⌫ 清除", recorder),
			formRow("输入后回车", "命令类片段打完字直接执行", enterSwitch),
		])

		let textScroll = NSScrollView()
		textScroll.hasVerticalScroller = true
		textScroll.autohidesScrollers = true
		textScroll.borderType = .noBorder
		textScroll.drawsBackground = false
		textView.drawsBackground = false
		textView.textContainerInset = NSSize(width: 8, height: 10)
		textView.minSize = NSSize(width: 0, height: 0)
		textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
		                          height: CGFloat.greatestFiniteMagnitude)
		textView.isVerticallyResizable = true
		textView.isHorizontallyResizable = false
		textView.autoresizingMask = [.width]
		textView.isRichText = false
		textView.isAutomaticQuoteSubstitutionEnabled = false
		textView.isAutomaticDashSubstitutionEnabled = false
		textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
		textView.delegate = self
		textView.textContainer?.containerSize = NSSize(width: 400,
		                                               height: CGFloat.greatestFiniteMagnitude)
		textView.textContainer?.widthTracksTextView = true
		textScroll.documentView = textView
		let textCard = Card()
		pin(textScroll, in: textCard, inset: 1)
		textCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true
		textCard.setContentHuggingPriority(.init(1), for: .vertical)

		// —— 右下：通用（本机设置，不随片段导入导出）
		launchSwitch.target = self
		launchSwitch.action = #selector(toggleLaunch)
		launchSwitch.controlSize = .small
		launchSwitch.state = LoginItem.enabled ? .on : .off

		panelRecorder.set(keyCode: PanelHotKey.keyCode, modifiers: PanelHotKey.modifiers)
		panelRecorder.onChange = { [weak self] code, mods in
			PanelHotKey.keyCode = code
			PanelHotKey.modifiers = mods
			self?.applyChanges()
		}
		size(panelRecorder, width: 200, height: 26)
		panelStatus.font = .systemFont(ofSize: 11.5, weight: .medium)
		panelStatus.textColor = .systemRed

		let generalCard = group([
			formRow("开机自动启动", nil, launchSwitch),
			formRow("搜索面板", "全局呼出，按名称搜片段", hstack([panelStatus, panelRecorder], spacing: 8)),
		])

		let right = vstack([
			sectionLabel("片段"), snippetCard,
			sectionLabel("内容"), textCard,
			sectionLabel("通用"), generalCard,
		], spacing: 8)
		for (v, gap) in [(snippetCard, 18.0), (textCard, 18.0)] as [(NSView, CGFloat)] {
			right.setCustomSpacing(gap, after: v)
		}

		left.translatesAutoresizingMaskIntoConstraints = false
		right.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(left)
		content.addSubview(right)
		NSLayoutConstraint.activate([
			left.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
			left.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
			left.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
			left.widthAnchor.constraint(equalToConstant: 250),

			right.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
			right.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
			right.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 20),
			right.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
		])
	}

	// MARK: 版式零件

	/// 分组卡片：一行一项，行间细线
	private func group(_ rows: [FormRow]) -> Card {
		for (i, r) in rows.enumerated() { r.drawsTopLine = i > 0 }
		let c = Card()
		pin(vstack(rows, spacing: 0), in: c, inset: 0)
		return c
	}

	/// 一行设置：左边标题（+ 灰色说明），右边控件
	private func formRow(_ title: String, _ subtitle: String?, _ control: NSView) -> FormRow {
		let t = NSTextField(labelWithString: title)
		t.font = .systemFont(ofSize: 13)
		var texts: [NSView] = [t]
		if let subtitle {
			let s = NSTextField(labelWithString: subtitle)
			s.font = .systemFont(ofSize: 11)
			s.textColor = .secondaryLabelColor
			s.lineBreakMode = .byTruncatingTail
			s.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
			texts.append(s)
		}
		let left = vstack(texts, spacing: 2)
		left.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		let row = FormRow()
		let line = hstack([left, NSView(), control], spacing: 12)
		line.translatesAutoresizingMaskIntoConstraints = false
		row.addSubview(line)
		let v: CGFloat = texts.count > 1 ? 8 : 10
		NSLayoutConstraint.activate([
			line.topAnchor.constraint(equalTo: row.topAnchor, constant: v),
			line.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -v),
			line.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Self.pad),
			line.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Self.pad),
			row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
		])
		return row
	}

	private func sectionLabel(_ text: String) -> NSView {
		let l = NSTextField(labelWithString: text)
		l.font = .systemFont(ofSize: 13, weight: .semibold)
		let box = NSView()
		l.translatesAutoresizingMaskIntoConstraints = false
		box.addSubview(l)
		NSLayoutConstraint.activate([
			l.topAnchor.constraint(equalTo: box.topAnchor),
			l.bottomAnchor.constraint(equalTo: box.bottomAnchor),
			l.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: Self.pad),
		])
		return box
	}

	private func iconButton(_ symbol: String, tip: String, action: Selector) -> NSButton {
		let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!,
		                 target: self, action: action)
		b.bezelStyle = .texturedRounded
		b.toolTip = tip
		size(b, width: 28, height: nil)
		return b
	}

	private func smallButton(_ title: String, action: Selector) -> NSButton {
		let b = NSButton(title: title, target: self, action: action)
		b.bezelStyle = .texturedRounded
		return b
	}

	private func hstack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
		let s = NSStackView(views: views)
		s.orientation = .horizontal
		s.alignment = .centerY
		s.spacing = spacing
		return s
	}

	/// 竖排且子视图拉满宽（NSStackView 的 .leading 对齐不会自动撑宽）
	private func vstack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
		let s = NSStackView(views: views)
		s.orientation = .vertical
		s.alignment = .leading
		s.spacing = spacing
		for v in views where !(v is NSTextField) {
			v.leadingAnchor.constraint(equalTo: s.leadingAnchor).isActive = true
			v.trailingAnchor.constraint(equalTo: s.trailingAnchor).isActive = true
		}
		return s
	}

	private func pin(_ inner: NSView, in outer: NSView, inset: CGFloat) {
		inner.translatesAutoresizingMaskIntoConstraints = false
		outer.translatesAutoresizingMaskIntoConstraints = false
		outer.addSubview(inner)
		NSLayoutConstraint.activate([
			inner.topAnchor.constraint(equalTo: outer.topAnchor, constant: inset),
			inner.bottomAnchor.constraint(equalTo: outer.bottomAnchor, constant: -inset),
			inner.leadingAnchor.constraint(equalTo: outer.leadingAnchor, constant: inset),
			inner.trailingAnchor.constraint(equalTo: outer.trailingAnchor, constant: -inset),
		])
	}

	private func size(_ v: NSView, width: CGFloat?, height: CGFloat?) {
		v.translatesAutoresizingMaskIntoConstraints = false
		if let width { v.widthAnchor.constraint(equalToConstant: width).isActive = true }
		if let height { v.heightAnchor.constraint(equalToConstant: height).isActive = true }
	}

	private var selectedRow: Int? {
		let r = table.selectedRow
		return (r >= 0 && r < Store.shared.snippets.count) ? r : nil
	}

	// MARK: 数据同步

	/// 片段被整体换掉（打开窗口、导入）后重画列表并选中第一条
	func reloadFromStore() {
		panelStatus.stringValue = HotKeyCenter.shared.panelFailed ? "被占用" : ""
		table.reloadData()
		table.selectRowIndexes(Store.shared.snippets.isEmpty ? [] : [0], byExtendingSelection: false)
		loadEditor()
	}

	private func loadEditor() {
		guard let row = selectedRow else {
			nameField.stringValue = ""
			nameField.isEnabled = false
			textView.string = ""
			textView.isEditable = false
			recorder.set(keyCode: nil, modifiers: 0)
			enterSwitch.state = .off
			enterSwitch.isEnabled = false
			return
		}
		let s = Store.shared.snippets[row]
		nameField.isEnabled = true
		textView.isEditable = true
		enterSwitch.isEnabled = true
		nameField.stringValue = s.name
		textView.string = s.text
		recorder.set(keyCode: s.keyCode, modifiers: s.modifiers)
		enterSwitch.state = s.pressEnter ? .on : .off
	}

	/// 存盘 + 重注册热键 + 刷新菜单与列表
	private func applyChanges() {
		Store.shared.save()
		HotKeyCenter.shared.reload()
		(NSApp.delegate as? AppDelegate)?.rebuildMenu()
		panelStatus.stringValue = HotKeyCenter.shared.panelFailed ? "被占用" : ""
		let selection = table.selectedRowIndexes
		table.reloadData()
		table.selectRowIndexes(selection, byExtendingSelection: false)
	}

	// MARK: 动作

	@objc private func addSnippet() {
		Store.shared.snippets.append(Snippet())
		applyChanges()
		let last = Store.shared.snippets.count - 1
		table.selectRowIndexes([last], byExtendingSelection: false)
		table.scrollRowToVisible(last)
		loadEditor()
		window?.makeFirstResponder(nameField)
	}

	@objc private func removeSnippet() {
		guard let row = selectedRow else { return }
		Store.shared.snippets.remove(at: row)
		applyChanges()
		let next = min(row, Store.shared.snippets.count - 1)
		if next >= 0 { table.selectRowIndexes([next], byExtendingSelection: false) }
		loadEditor()
	}

	@objc private func importSnippets() {
		if Transfer.importSnippets() { (NSApp.delegate as? AppDelegate)?.snippetsDidChange() }
	}

	@objc private func exportSnippets() {
		Transfer.exportSnippets()
	}

	@objc private func toggleEnter() {
		guard let row = selectedRow else { return }
		Store.shared.snippets[row].pressEnter = enterSwitch.state == .on
		applyChanges()
	}

	@objc private func toggleLaunch() {
		LoginItem.set(launchSwitch.state == .on)
		launchSwitch.state = LoginItem.enabled ? .on : .off
	}

	// MARK: NSTableView

	func numberOfRows(in tableView: NSTableView) -> Int { Store.shared.snippets.count }

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let s = Store.shared.snippets[row]

		// 一条两行：名称 + 内容预览；快捷键靠右
		let name = NSTextField(labelWithString: s.name.isEmpty ? "未命名" : s.name)
		name.font = .systemFont(ofSize: 13, weight: .medium)
		name.lineBreakMode = .byTruncatingTail

		let preview = NSTextField(labelWithString:
			s.text.replacingOccurrences(of: "\n", with: " ⏎ ") + (s.pressEnter ? "  ↩" : ""))
		preview.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
		preview.textColor = .secondaryLabelColor
		preview.lineBreakMode = .byTruncatingTail

		var keyText = Keys.describe(keyCode: s.keyCode, modifiers: s.modifiers)
		var keyColor = NSColor.secondaryLabelColor
		if HotKeyCenter.shared.failed.contains(s.id) {
			keyText += " 被占用"
			keyColor = .systemRed
		} else if s.keyCode == nil {
			keyColor = .tertiaryLabelColor
		}
		let key = NSTextField(labelWithString: keyText)
		key.font = .systemFont(ofSize: 11.5)
		key.textColor = keyColor
		key.setContentCompressionResistancePriority(.required, for: .horizontal)

		let top = hstack([name, NSView(), key], spacing: 6)
		name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		let col = vstack([top, preview], spacing: 2)
		preview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		preview.trailingAnchor.constraint(lessThanOrEqualTo: col.trailingAnchor).isActive = true

		let cell = NSTableCellView()
		col.translatesAutoresizingMaskIntoConstraints = false
		cell.addSubview(col)
		NSLayoutConstraint.activate([
			col.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
			col.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
			col.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
		])
		return cell
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		loadEditor()
	}

	// MARK: 编辑回写

	func controlTextDidChange(_ obj: Notification) {
		guard let row = selectedRow else { return }
		Store.shared.snippets[row].name = nameField.stringValue
		applyChanges()
	}

	func textDidChange(_ notification: Notification) {
		guard let row = selectedRow else { return }
		Store.shared.snippets[row].text = textView.string
		applyChanges()
	}
}

// MARK: - 画出来的小零件（颜色都在 draw 里取，深浅色切换才跟得上）

/// 圆角卡片
final class Card: NSView {
	override func draw(_ dirtyRect: NSRect) {
		let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
		NSColor.controlBackgroundColor.setFill()
		path.fill()
		NSColor.separatorColor.setStroke()
		path.lineWidth = 1
		path.stroke()
	}
}

/// 卡片里的一行：需要时在顶边画一条左右缩进的细线
final class FormRow: NSView {
	var drawsTopLine = false { didSet { needsDisplay = true } }

	override func draw(_ dirtyRect: NSRect) {
		guard drawsTopLine else { return }
		NSColor.separatorColor.setFill()
		NSRect(x: 14, y: isFlipped ? 0 : bounds.maxY - 1, width: bounds.width - 28, height: 1).fill()
	}
}
