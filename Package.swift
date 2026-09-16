// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Focusman",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Focusman", path: "Sources/Focusman"),
        .testTarget(name: "FocusmanTests", dependencies: ["Focusman"])
    ]
)
