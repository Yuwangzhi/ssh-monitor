// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SSHMonitor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SSHMonitor", targets: ["SSHMonitor"])],
    targets: [
        .target(name: "SSHMonitorCore"),
        .executableTarget(name: "SSHMonitor", dependencies: ["SSHMonitorCore"]),
        .testTarget(name: "SSHMonitorCoreTests", dependencies: ["SSHMonitorCore"])
    ]
)
