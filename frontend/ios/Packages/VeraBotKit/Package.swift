// swift-tools-version: 6.0
// VeraBotKit：iOS App 的本地 Swift Package（SPM）。按职责拆成三个模块，App 按需 import。
// 第三方依赖请在 dependencies 中添加（例如 .package(url: "...", from: "1.0.0")），并加到对应 target。
import PackageDescription

let package = Package(
    name: "VeraBotKit",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v17), .macOS(.v14)],  // macOS 仅用于在 Mac 上跑 `swift test`
    products: [
        .library(name: "VeraBotCore", targets: ["VeraBotCore"]),
        .library(name: "VeraBotNetworking", targets: ["VeraBotNetworking"]),
        .library(name: "VeraBotTTS", targets: ["VeraBotTTS"]),
    ],
    dependencies: [],
    targets: [
        // 共享数据模型 + 设置 key（无 UI、无网络）
        .target(name: "VeraBotCore"),
        // REST + SSE 客户端（VeraBotAPI 协议 + APIClient 实现）
        .target(name: "VeraBotNetworking", dependencies: ["VeraBotCore"]),
        // 语音播放（TTSEngine 协议 + 本机 / 云端引擎 + SpeechPlayer）
        .target(name: "VeraBotTTS", dependencies: ["VeraBotCore"]),
        .testTarget(name: "VeraBotKitTests", dependencies: ["VeraBotCore", "VeraBotNetworking", "VeraBotTTS"]),
    ]
)
