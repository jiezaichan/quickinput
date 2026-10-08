import Cocoa
import UniformTypeIdentifiers

// MARK: - 导入导出
//
// 文件格式就是 snippets.json 本身（片段数组），导出的文件也能直接拿去当数据文件用。

enum Transfer {
	static func exportSnippets() {
		NSApp.activate(ignoringOtherApps: true)
		let panel = NSSavePanel()
		panel.allowedContentTypes = [.json]
		let f = DateFormatter()
		f.dateFormat = "yyyyMMdd"
		panel.nameFieldStringValue = "速填片段-\(f.string(from: Date())).json"
		guard panel.runModal() == .OK, let url = panel.url else { return }
		do {
			guard let data = Store.shared.encoded() else { throw CocoaError(.fileWriteUnknown) }
			try data.write(to: url)
		} catch {
			alert("导出失败", error.localizedDescription)
		}
	}

	/// 返回 true 表示片段已改动，调用方负责存盘并刷新
	static func importSnippets() -> Bool {
		NSApp.activate(ignoringOtherApps: true)
		let panel = NSOpenPanel()
		panel.allowedContentTypes = [.json]
		panel.allowsMultipleSelection = false
		guard panel.runModal() == .OK, let url = panel.url else { return false }

		let list: [Snippet]
		do {
			list = try Store.decode(Data(contentsOf: url))
		} catch {
			alert("导入失败", "不是速填导出的片段文件。\n\(error.localizedDescription)")
			return false
		}
		guard !list.isEmpty else {
			alert("导入失败", "文件里没有片段。")
			return false
		}

		let ask = NSAlert()
		ask.messageText = "导入 \(list.count) 条片段"
		ask.informativeText = "合并：同一条片段（id 相同）用文件里的覆盖，其余追加。\n替换全部：清空现有片段，只保留文件里的。"
		ask.addButton(withTitle: "合并")
		ask.addButton(withTitle: "替换全部")
		ask.addButton(withTitle: "取消")
		switch ask.runModal() {
		case .alertFirstButtonReturn:
			let r = Store.shared.merge(list)
			alert("导入完成", "新增 \(r.added) 条，覆盖 \(r.replaced) 条。")
		case .alertSecondButtonReturn:
			Store.shared.snippets = []
			_ = Store.shared.merge(list)
		default:
			return false
		}
		return true
	}

	private static func alert(_ title: String, _ message: String) {
		let a = NSAlert()
		a.messageText = title
		a.informativeText = message
		a.runModal()
	}
}
