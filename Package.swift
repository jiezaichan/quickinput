// swift-tools-version:5.9
import PackageDescription

let package = Package(
	name: "QuickInput",
	platforms: [.macOS(.v13)],
	targets: [
		.executableTarget(name: "QuickInput", path: "Sources/QuickInput"),
	]
)
