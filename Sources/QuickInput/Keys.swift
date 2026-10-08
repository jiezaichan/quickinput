import Cocoa
import Carbon.HIToolbox

// MARK: - 键名

enum Keys {
	static let fKeys: Set<UInt32> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

	static let names: [UInt32: String] = [
		0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
		34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
		12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
		16: "Y", 6: "Z",
		29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
		49: "空格", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 53: "esc",
		122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
		98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
		123: "←", 124: "→", 125: "↓", 126: "↑",
		115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
		27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'",
		43: ",", 47: ".", 44: "/", 50: "`", 42: "\\",
	]

	static func describe(keyCode: UInt32?, modifiers: UInt32) -> String {
		guard let kc = keyCode else { return "未设置" }
		var s = ""
		if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
		if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
		if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
		if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
		s += names[kc] ?? "键\(kc)"
		return s
	}

	static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
		var m: UInt32 = 0
		if flags.contains(.control) { m |= UInt32(controlKey) }
		if flags.contains(.option) { m |= UInt32(optionKey) }
		if flags.contains(.shift) { m |= UInt32(shiftKey) }
		if flags.contains(.command) { m |= UInt32(cmdKey) }
		return m
	}
}
