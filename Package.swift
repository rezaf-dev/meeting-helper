// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MeetingHelper",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "MeetingHelper", targets: ["MeetingHelper"])],
    targets: [
        .target(name: "MeetingCore"),
        .executableTarget(name: "MeetingHelper", dependencies: ["MeetingCore"]),
        .testTarget(name: "MeetingCoreTests", dependencies: ["MeetingCore"])
    ],
    swiftLanguageModes: [.v5]
)
