// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shepherdr",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShepherdrCore", targets: ["ShepherdrCore"]),
        .library(name: "ShepherdrTerminalUI", targets: ["ShepherdrTerminalUI"]),
        .executable(name: "shepherdr-probe", targets: ["ShepherdrProbe"]),
        .executable(name: "shepherdr", targets: ["ShepherdrApp"])
    ],
    dependencies: [
        // AppKit renderer: no Metal toolchain, binary framework, or build plugin required.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.10.1")
    ],
    targets: [
        .target(name: "ShepherdrCore"),
        .target(name: "ShepherdrTerminalUI",
                dependencies: ["ShepherdrCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
                resources: [.copy("Resources/SwiftTerm-LICENSE"), .copy("Resources/Fonts")]),
        .executableTarget(name: "ShepherdrProbe", dependencies: ["ShepherdrCore"]),
        .executableTarget(name: "ShepherdrApp", dependencies: ["ShepherdrCore", "ShepherdrTerminalUI"], path: "App",
                         exclude: ["Assets.xcassets"]), // The Xcode app target compiles the icon catalog.
        .testTarget(name: "ShepherdrCoreTests", dependencies: ["ShepherdrCore"],
                    resources: [.copy("Fixtures")])
    ]
)
