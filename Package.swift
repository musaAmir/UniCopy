// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "UniCopy", platforms: [.macOS(.v14)], targets: [
    .target(name: "UniCopyCore"),
    .executableTarget(name: "UniCopy", dependencies: ["UniCopyCore"]), .executableTarget(name: "UniCopyOCR", dependencies: ["UniCopyCore"]),
    .testTarget(name: "UniCopyCoreTests", dependencies: ["UniCopyCore"])
])
