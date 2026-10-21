// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ProofMate",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ProofMateCore", targets: ["ProofMateCore"]),
        .executable(name: "ProofMate", targets: ["ProofMate"]),
    ],
    targets: [
        .target(name: "ProofMateCore"),
        .executableTarget(
            name: "ProofMate",
            dependencies: ["ProofMateCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .testTarget(name: "ProofMateCoreTests", dependencies: ["ProofMateCore"]),
    ]
)
