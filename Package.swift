// swift-tools-version: 5.9
import PackageDescription
import Foundation

// The original source installer intentionally stays self-contained. Release DMGs
// enable Sparkle and embed its framework in build_dmg.sh.
let includesUpdater = ProcessInfo.processInfo.environment["SEEUSAGE_ENABLE_SPARKLE"] == "1"
let updaterPackages: [Package.Dependency] = includesUpdater
    ? [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")] : []
let updaterDependencies: [Target.Dependency] = includesUpdater
    ? [.product(name: "Sparkle", package: "Sparkle")] : []

let package = Package(
    name: "SeeUsage",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SeeUsage", targets: ["SeeUsage"])
    ],
    dependencies: updaterPackages,
    targets: [
        .executableTarget(
            name: "SeeUsage",
            dependencies: updaterDependencies,
            path: "Sources/SeeUsage",
            resources: [.copy("Resources/Companion")],
            swiftSettings: includesUpdater ? [.define("ENABLE_SPARKLE")] : [],
            linkerSettings: includesUpdater ? [.unsafeFlags([
                "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"
            ])] : []
        ),
        .testTarget(
            name: "SeeUsageTests",
            dependencies: ["SeeUsage"],
            path: "Tests/SeeUsageTests"
        )
    ]
)
