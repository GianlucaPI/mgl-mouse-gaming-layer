// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MGL",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MGLCore", targets: ["MGLCore"]),
        .executable(name: "mgl-probe", targets: ["mgl-probe"]),
        .executable(name: "mgl", targets: ["mgl"]),
    ],
    targets: [
        .target(
            name: "MGLCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .executableTarget(name: "mgl-probe", dependencies: ["MGLCore"]),
        .executableTarget(name: "mgl", dependencies: ["MGLCore"]),
        .testTarget(name: "MGLCoreTests", dependencies: ["MGLCore"]),
    ]
)
