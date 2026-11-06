// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RadarKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RadarKit", targets: ["RadarKit"]),
        .executable(name: "mrradar", targets: ["mrradar"]),
    ],
    targets: [
        .target(name: "RadarKit"),
        .executableTarget(name: "mrradar", dependencies: ["RadarKit"]),
        .testTarget(name: "RadarKitTests", dependencies: ["RadarKit"]),
    ]
)
