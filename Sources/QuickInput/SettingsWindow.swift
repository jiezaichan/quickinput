import Cocoa

// MARK: - 设置窗口

final class SettingsWC: NSWindowController, NSTableViewDataSource, NSTableViewDelegate,
                        NSTextFieldDelegate, NSTextViewDelegate {
	private let table = NSTableView()
	private let nameField = NSTextField()
	private let recorder = HotKeyRecorder(frame: .zero)
	private let textView = NSTextView()
	private let enterCheck = NSButton(checkboxWithTitle: "输入后回车", target: nil, action: nil)
	private let launchCheck = NSButton(checkboxWithTitle: "开机自动启动", target: nil, action: nil)
	private let panelRecorder = HotKeyRecorder(frame: .zero)
	private let panelStatus = NSTextField(labelWithString: "")

	convenience init() {
		let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 540),
		                   styleMask: [.titled, .closable, .miniaturizable],
		                   backing: .buffered,
		                   defer: false)
		win.title = "速填 · 设置"
		win.center()
		self.init(window: win)
		buildUI()
		reloadFromStore()
	}

	private func buildUI() {
		guard let content = window?.contentView else { return }

		// —— 片段列表
		let scroll = NSScrollView(frame: NSRect(x: 20, y: 300, width: 540, height: 220))
		scroll.hasVerticalScroller = true
		scroll.borderType = .bezelBorder
		table.rowHeight = 22
		table.usesAlternatingRowBackgroundColors = true
		table.dataSource = self
		table.delegate = self
		for (key, title, width) in [("name", "名称", 140.0), ("key", "快捷键", 140.0), ("text", "内容", 250.0)] {
			let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
			col.title = title
			col.width = width
			table.addTableColumn(col)
		}
		scroll.documentView = table
		content.addSubview(scroll)

		// —— 增删按钮（左）与导入导出（右）
		for (title, action, x) in [("＋ 新增", #selector(addSnippet), 20.0),
		                           ("－ 删除", #selector(removeSnippet), 110.0),
		                           ("导入…", #selector(importSnippets), 386.0),
		                           ("导出…", #selector(exportSnippets), 476.0)] {
			let btn = NSButton(title: title, target: self, action: action)
			btn.frame = NSRect(x: x, y: 266, width: 84, height: 26)
			btn.bezelStyle = .rounded
			content.addSubview(btn)
		}

		// —— 编辑区
		content.addSubview(makeLabel("名称", y: 230))
		nameField.frame = NSRect(x: 90, y: 227, width: 470, height: 24)
		nameField.delegate = self
		content.addSubview(nameField)

		content.addSubview(makeLabel("快捷键", y: 193))
		recorder.frame = NSRect(x: 90, y: 189, width: 260, height: 26)
		recorder.onChange = { [weak self] code, mods in
			guard let self = self, let row = self.selectedRow else { return }
			Store.shared.snippets[row].keyCode = code
			Store.shared.snippets[row].modifiers = mods
			self.applyChanges()
		}
		content.addSubview(recorder)

		enterCheck.frame = NSRect(x: 366, y: 192, width: 160, height: 20)
		enterCheck.target = self
		enterCheck.action = #selector(toggleEnter)
		content.addSubview(enterCheck)

		content.addSubview(makeLabel("内容", y: 152))
		let textScroll = NSScrollView(frame: NSRect(x: 90, y: 56, width: 470, height: 112))
		textScroll.hasVerticalScroller = true
		textScroll.borderType = .bezelBorder
		textView.minSize = NSSize(width: 0, height: 0)
		textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
		                          height: CGFloat.greatestFiniteMagnitude)
		textView.isVerticallyResizable = true
		textView.isHorizontallyResizable = false
		textView.autoresizingMask = [.width]
		textView.isRichText = false
		textView.isAutomaticQuoteSubstitutionEnabled = false
		textView.isAutomaticDashSubstitutionEnabled = false
		textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
		textView.delegate = self
		textView.textContainer?.containerSize = NSSize(width: 470,
		                                               height: CGFloat.greatestFiniteMagnitude)
		textView.textContainer?.widthTracksTextView = true
		textScroll.documentView = textView
		content.addSubview(textScroll)

		// —— 开机自启
		launchCheck.frame = NSRect(x: 20, y: 18, width: 200, height: 20)
		launchCheck.target = self
		launchCheck.action = #selector(toggleLaunch)
		launchCheck.state = LoginItem.enabled ? .on : .off
		content.addSubview(launchCheck)

		// —— 搜索面板快捷键（本机设置，不随片段导入导出）
		let panelLabel = makeLabel("搜索面板", y: 19)
		panelLabel.frame.origin.x = 226
		content.addSubview(panelLabel)
		panelRecorder.frame = NSRect(x: 296, y: 15, width: 190, height: 26)
		panelRecorder.set(keyCode: PanelHotKey.keyCode, modifiers: PanelHotKey.modifiers)
		panelRecorder.onChange = { [weak self] code, mods in
			PanelHotKey.keyCode = code
			PanelHotKey.modifiers = mods
			self?.applyChanges()
		}
		content.addSubview(panelRecorder)
		panelStatus.frame = NSRect(x: 492, y: 19, width: 70, height: 18)
		panelStatus.textColor = .systemRed
		content.addSubview(panelStatus)
	}

	private func makeLabel(_ text: String, y: CGFloat) -> NSTextField {
		let l = NSTextField(labelWithString: text)
		l.frame = NSRect(x: 20, y: y, width: 64, height: 18)
		l.alignment = .right
		l.textColor = .secondaryLabelColor
		return l
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
			enterCheck.state = .off
			enterCheck.isEnabled = false
			return
		}
		let s = Store.shared.snippets[row]
		nameField.isEnabled = true
		textView.isEditable = true
		enterCheck.isEnabled = true
		nameField.stringValue = s.name
		textView.string = s.text
		recorder.set(keyCode: s.keyCode, modifiers: s.modifiers)
		enterCheck.state = s.pressEnter ? .on : .off
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
		Store.shared.snippets[row].pressEnter = enterCheck.state == .on
		applyChanges()
	}

	@objc private func toggleLaunch() {
		LoginItem.set(launchCheck.state == .on)
		launchCheck.state = LoginItem.enabled ? .on : .off
	}

	// MARK: NSTableView

	func numberOfRows(in tableView: NSTableView) -> Int { Store.shared.snippets.count }

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let s = Store.shared.snippets[row]
		var text = ""
		var color = NSColor.labelColor

		switch tableColumn?.identifier.rawValue {
		case "name":
			text = s.name
		case "key":
			text = Keys.describe(keyCode: s.keyCode, modifiers: s.modifiers)
			if HotKeyCenter.shared.failed.contains(s.id) {
				text += "（被占用）"
				color = .systemRed
			} else if s.keyCode == nil {
				color = .secondaryLabelColor
			}
		default:
			text = s.text.replacingOccurrences(of: "\n", with: " ⏎ ") + (s.pressEnter ? "  ↩" : "")
			color = .secondaryLabelColor
		}

		let cell = NSTableCellView()
		let tf = NSTextField(labelWithString: text)
		tf.textColor = color
		tf.lineBreakMode = .byTruncatingTail
		tf.translatesAutoresizingMaskIntoConstraints = false
		cell.addSubview(tf)
		NSLayoutConstraint.activate([
			tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
			tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
			tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
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
