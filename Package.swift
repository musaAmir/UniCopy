// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "UniCopy", platforms: [.macOS(.v14)], dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0")
], targets: [
    .target(name: "UniCopyCore"),
    // build.sh copies Sparkle.framework into Contents/Frameworks.
    .executableTarget(name: "UniCopy", dependencies: ["UniCopyCore", .product(name: "Sparkle", package: "Sparkle")],
                      linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
    .executableTarget(name: "UniCopyOCR", dependencies: ["UniCopyCore"]),
    .testTarget(name: "UniCopyCoreTests", dependencies: ["UniCopyCore"])
])
