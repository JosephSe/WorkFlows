// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WorkFlows",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "WorkFlows", path: "Sources/WorkFlows")
    ]
)
