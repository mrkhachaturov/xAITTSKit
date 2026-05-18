// swift-tools-version: 6.2
//
// xAITTSKit — Streaming xAI Grok TTS client for Apple platforms.
//
// Mirrors the API surface of OpenAITTSKit and YandexTTSKit so it slots into
// the OpenClaw iOS Talk Mode picker without further abstraction.
//

import PackageDescription

let package = Package(
    name: "xAITTSKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "xAITTSKit", targets: ["xAITTSKit"])
    ],
    targets: [
        .target(name: "xAITTSKit", path: "Sources/xAITTSKit"),
        .testTarget(name: "xAITTSKitTests", dependencies: ["xAITTSKit"], path: "Tests/xAITTSKitTests")
    ],
    swiftLanguageModes: [.v6]
)
