// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Hanasu",
    platforms: [.macOS(.v26)],
    dependencies: [
        // 会議の記録の話者分離（pyannote を CoreML 化したもの。Apache-2.0）
        // traits: [] で、使わないテキスト正規化のビルド済みバイナリ（NemoTextProcessing）を外す
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: []),
        // 文字起こしのエンジン「Whisper」（CoreML 版の Whisper。MIT）。使うのは WhisperKit の製品だけで、
        // 依存は同じパッケージの ArgmaxCore だけ（swift-argument-parser は CLI 用で、Hanasu には入らない）
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1"),
    ],
    targets: [
        .executableTarget(
            name: "Hanasu",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/Hanasu",
            // 設計判断: DEC-COM-160
            // AI へのプロンプト（言語ごとの JSON。Windows 版も同じファイルを読む）
            resources: [
                .copy("Resources/Prompts"),
                // 要件: REQ-COM-060
                // 設計判断: DEC-COM-165
                // UI の文字列（String Catalog）。xcstringstool で変換せず、起動後に JSON のまま読む
                .copy("Resources/Localizable.xcstrings"),
            ],
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
