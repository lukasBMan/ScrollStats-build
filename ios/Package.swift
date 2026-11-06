// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ScrollStatsCore", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "ScrollStatsCore", targets: ["ScrollStatsCore"])], targets: [.target(name: "ScrollStatsCore"), .testTarget(name: "ScrollStatsCoreTests", dependencies: ["ScrollStatsCore"])])
