// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Hanasu",
    platforms: [.macOS(.v26)],
    dependencies: [
        // 会議の記録の話者分離（pyannote を CoreML 化したもの。Apache-2.0）
        // traits: [] で、使わないテキスト正規化のビルド済みバイナリ（NemoTextProcessing）を外す
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: []),
    ],
    targets: [
        .executableTarget(
            name: "Hanasu",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/Hanasu",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
            ]
        ),
    ]
)
