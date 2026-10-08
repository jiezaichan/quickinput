import Foundation
import Carbon.HIToolbox

// MARK: - 模型

struct Snippet: Codable {
	var id = UUID()
	var name = "新片段"
	var text = ""
	var keyCode: UInt32? = nil
	var modifiers: UInt32 = 0
	/// 打完字再按一下回车（命令类片段直接执行）
	var pressEnter = false
}

/// 写在 extension 里以保留成员初始化器；缺字段时取默认值，手写的导入文件也能读
extension Snippet {
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
		name = try c.decodeIfPresent(String.self, forKey: .name) ?? "新片段"
		text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
		keyCode = try c.decodeIfPresent(UInt32.self, forKey: .keyCode)
		modifiers = try c.decodeIfPresent(UInt32.self, forKey: .modifiers) ?? 0
		pressEnter = try c.decodeIfPresent(Bool.self, forKey: .pressEnter) ?? false
	}
}

// MARK: - 存储

final class Store {
	static let shared = Store()
	var snippets: [Snippet] = []

	/// 数据目录沿用 1.0 的「速填」，升级不丢片段。以后做 iCloud 同步只需改这里
	private let dir: URL = FileManager.default
		.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
		.appendingPathComponent("速填", isDirectory: true)
	private var file: URL { dir.appendingPathComponent("snippets.json") }

	func load() {
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		if let data = try? Data(contentsOf: file),
		   let list = try? Store.decode(data) {
			snippets = list
		} else {
			snippets = Store.defaults
			save()
		}
	}

	/// 首次运行的预置片段（Claude Code 常用命令，⌃⌥⌘ + 键）
	static var defaults: [Snippet] {
		let mods = UInt32(controlKey | optionKey | cmdKey)
		return [
			Snippet(name: "压缩上下文", text: "/compact", keyCode: UInt32(kVK_ANSI_C), modifiers: mods),
			Snippet(name: "清除", text: "/clear", keyCode: UInt32(kVK_ANSI_V), modifiers: mods),
			Snippet(name: "加载上下文", text: "/resume", keyCode: UInt32(kVK_ANSI_R), modifiers: mods),
		]
	}

	func save() {
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		if let data = encoded() { try? data.write(to: file) }
	}

	/// 存盘与导出共用同一格式
	func encoded() -> Data? {
		let enc = JSONEncoder()
		enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
		return try? enc.encode(snippets)
	}

	static func decode(_ data: Data) throws -> [Snippet] {
		try JSONDecoder().decode([Snippet].self, from: data)
	}

	/// id 相同的覆盖原位置，新 id 追加到末尾
	func merge(_ list: [Snippet]) -> (added: Int, replaced: Int) {
		var added = 0, replaced = 0
		for s in list {
			if let i = snippets.firstIndex(where: { $0.id == s.id }) {
				snippets[i] = s
				replaced += 1
			} else {
				snippets.append(s)
				added += 1
			}
		}
		return (added, replaced)
	}
}
