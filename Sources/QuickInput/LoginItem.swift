import Foundation

// MARK: - 开机自启

enum LoginItem {
	/// 与 Info.plist 的 CFBundleIdentifier、build.sh 的 LABEL 保持一致
	static let label = "com.jiezaichan.quickinput"

	static var plistURL: URL {
		FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("LaunchAgents", isDirectory: true)
			.appendingPathComponent("\(label).plist")
	}

	static var enabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

	static func set(_ on: Bool) {
		if on {
			guard let exe = Bundle.main.executablePath else { return }
			let dict: [String: Any] = [
				"Label": label,
				"ProgramArguments": [exe],
				"RunAtLoad": true,
				"KeepAlive": false,
				"ProcessType": "Interactive",
			]
			try? FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
			                                         withIntermediateDirectories: true)
			if let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) {
				try? data.write(to: plistURL)
			}
			launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
		} else {
			launchctl(["bootout", "gui/\(getuid())/\(label)"])
			try? FileManager.default.removeItem(at: plistURL)
		}
	}

	private static func launchctl(_ args: [String]) {
		let p = Process()
		p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
		p.arguments = args
		p.standardOutput = FileHandle.nullDevice
		p.standardError = FileHandle.nullDevice
		try? p.run()
		p.waitUntilExit()
	}
}
