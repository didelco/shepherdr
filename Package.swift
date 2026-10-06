// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shepherdr",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShepherdrCore", targets: ["ShepherdrCore"]),
        .library(name: "ShepherdrTerminalUI", targets: ["ShepherdrTerminalUI"]),
        .library(name: "ShepherdrDictation", targets: ["ShepherdrDictation"]),
        .executable(name: "shepherdr-probe", targets: ["ShepherdrProbe"]),
        .executable(name: "shepherdr", targets: ["ShepherdrApp"])
    ],
    dependencies: [
        // AppKit renderer: no Metal toolchain, binary framework, or build plugin required.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.10.1"),
        // On-device speech to text (NVIDIA Parakeet TDT v3): the engine and version theam/scribe uses,
        // so both share one downloaded model.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.13.4")
    ],
    targets: [
        .target(name: "ShepherdrCore"),
        .target(name: "ShepherdrTerminalUI",
                dependencies: ["ShepherdrCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
                resources: [.copy("Resources/SwiftTerm-LICENSE"), .copy("Resources/Fonts")]),
        .target(name: "ShepherdrDictation",
                dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
                resources: [.copy("Resources/FluidAudio-LICENSE")]),
        .executableTarget(name: "ShepherdrProbe", dependencies: ["ShepherdrCore"]),
        .executableTarget(name: "ShepherdrApp", dependencies: ["ShepherdrCore", "ShepherdrTerminalUI", "ShepherdrDictation"], path: "App",
                         exclude: ["Assets.xcassets"]), // The Xcode app target compiles the icon catalog.
        .testTarget(name: "ShepherdrCoreTests", dependencies: ["ShepherdrCore"],
                    resources: [.copy("Fixtures")])
    ]
)
