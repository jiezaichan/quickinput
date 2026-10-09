import Cocoa
import ApplicationServices

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
	private var statusItem: NSStatusItem!
	private var settingsWC: SettingsWC?

	func applicationDidFinishLaunching(_ notification: Notification) {
		NSApp.setActivationPolicy(.accessory)

		Store.shared.load()
		HotKeyCenter.shared.reload()
		AuthAssist.shared.start()

		statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		if let button = statusItem.button {
			button.image = NSImage(systemSymbolName: "text.insert", accessibilityDescription: "速填")
			button.image?.isTemplate = true
		}
		rebuildMenu()

		// 首次运行弹辅助功能授权框；没权限时热键能注册但发不出按键
		let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
		_ = AXIsProcessTrustedWithOptions(opts)
	}

	func rebuildMenu() {
		let menu = NSMenu()

		if Store.shared.snippets.isEmpty {
			let empty = NSMenuItem(title: "（还没有片段）", action: nil, keyEquivalent: "")
			empty.isEnabled = false
			menu.addItem(empty)
		}
		for (i, s) in Store.shared.snippets.enumerated() {
			let hint = Keys.describe(keyCode: s.keyCode, modifiers: s.modifiers)
			let item = NSMenuItem(title: "\(s.name)    \(hint)",
			                      action: #selector(insertSnippet(_:)),
			                      keyEquivalent: "")
			item.target = self
			item.tag = i
			menu.addItem(item)
		}

		menu.addItem(.separator())

		let trusted = AXIsProcessTrusted()
		let perm = NSMenuItem(title: trusted ? "辅助功能权限：已授权" : "⚠️ 辅助功能权限：未授权（点此前往）",
		                      action: #selector(openAccessibilitySettings),
		                      keyEquivalent: "")
		perm.target = self
		menu.addItem(perm)

		let pwd = NSMenuItem(title: AdminPassword.isSet ? "管理员密码：已设置（授权框旁一键填入）" : "管理员密码：未设置（点此设置）",
		                     action: #selector(editAdminPassword),
		                     keyEquivalent: "")
		pwd.target = self
		menu.addItem(pwd)

		let panelHint = PanelHotKey.keyCode == nil ? "" : "    " + Keys.describe(keyCode: PanelHotKey.keyCode, modifiers: PanelHotKey.modifiers)
		let search = NSMenuItem(title: "搜索片段…" + panelHint, action: #selector(openSearch), keyEquivalent: "")
		search.target = self
		menu.addItem(search)

		let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
		settings.target = self
		menu.addItem(settings)

		let importItem = NSMenuItem(title: "导入片段…", action: #selector(importSnippets), keyEquivalent: "")
		importItem.target = self
		menu.addItem(importItem)

		let exportItem = NSMenuItem(title: "导出片段…", action: #selector(exportSnippets), keyEquivalent: "")
		exportItem.target = self
		menu.addItem(exportItem)

		menu.addItem(.separator())

		let quit = NSMenuItem(title: "退出速填", action: #selector(quit), keyEquivalent: "q")
		quit.target = self
		menu.addItem(quit)

		statusItem.menu = menu
	}

	/// 片段被整体换掉（导入）后：存盘、重注册热键、刷新菜单和设置窗口
	func snippetsDidChange() {
		Store.shared.save()
		HotKeyCenter.shared.reload()
		rebuildMenu()
		settingsWC?.reloadFromStore()
	}

	@objc private func insertSnippet(_ sender: NSMenuItem) {
		let i = sender.tag
		guard i >= 0, i < Store.shared.snippets.count else { return }
		let snippet = Store.shared.snippets[i]
		// 等菜单收起、焦点回到原来的 App 再发按键
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { Typer.insert(snippet) }
	}

	@objc private func openSearch() {
		// 等菜单收起再弹面板
		DispatchQueue.main.async { SearchPanel.shared.show() }
	}

	@objc private func openSettings() {
		if settingsWC == nil { settingsWC = SettingsWC() }
		NSApp.activate(ignoringOtherApps: true)
		settingsWC?.showWindow(nil)
		settingsWC?.window?.makeKeyAndOrderFront(nil)
		rebuildMenu()
	}

	@objc private func importSnippets() {
		if Transfer.importSnippets() { snippetsDidChange() }
	}

	@objc private func exportSnippets() {
		Transfer.exportSnippets()
	}

	@objc private func editAdminPassword() {
		let alert = NSAlert()
		alert.messageText = "管理员密码"
		alert.informativeText = "存进登录钥匙串，不随片段导出。系统授权框弹出时旁边会出现「填入密码」按钮，点一下自动输入并回车。"
		let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
		field.placeholderString = "本机登录密码"
		alert.accessoryView = field
		alert.addButton(withTitle: "保存")
		alert.addButton(withTitle: "取消")
		if AdminPassword.isSet { alert.addButton(withTitle: "清除已存密码") }
		alert.window.initialFirstResponder = field
		NSApp.activate(ignoringOtherApps: true)

		switch alert.runModal() {
		case .alertFirstButtonReturn:
			let pw = field.stringValue
			guard AdminPassword.verify(pw) else {
				let err = NSAlert()
				err.messageText = "密码不对"
				err.informativeText = "没有保存。请输入当前用户的登录密码。"
				err.runModal()
				return
			}
			_ = AdminPassword.save(pw)
		case .alertThirdButtonReturn:
			AdminPassword.clear()
		default:
			return
		}
		rebuildMenu()
	}

	@objc private func openAccessibilitySettings() {
		let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
		NSWorkspace.shared.open(url)
	}

	@objc private func quit() {
		NSApp.terminate(nil)
	}
}
