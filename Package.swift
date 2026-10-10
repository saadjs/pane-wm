// swift-tools-version: 6.2
import PackageDescription

// The app itself is the Xcode target described in project.yml; this package holds its testable core.
let package = Package(
    name: "PaneCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PaneCore", targets: ["PaneCore"])],
    targets: [
        .target(name: "PaneCore"),
        .testTarget(name: "PaneCoreTests", dependencies: ["PaneCore"]),
    ],
    swiftLanguageModes: [.v6]
)
