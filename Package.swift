// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tape",
    platforms: [.macOS(.v13)],
    products: [.library(name: "TapeEngine", targets: ["TapeEngine"])],
    targets: [
        .target(name: "TapeEngine", path: "Sources/Engine"),
        .target(name: "TapeRuntime", dependencies: ["TapeEngine"], path: "Sources",
                exclude: ["Engine", "Services", "App/Main.swift", "App/TabOverlay.swift", "App/SettingsView.swift", "App/OnboardingView.swift", "App/SearchField.swift", "App/SystemStyle.swift"],
                sources: ["App/TapeController.swift", "App/TapeSettings.swift", "Platform"]),
        .testTarget(name: "TapeEngineTests", dependencies: ["TapeEngine", "TapeRuntime"], path: "Tests")
    ]
)
