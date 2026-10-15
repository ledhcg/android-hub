// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AndroidHub",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AdbKit", targets: ["AdbKit"]),
        .library(name: "EmulatorKit", targets: ["EmulatorKit"]),
        .library(name: "ScrcpyKit", targets: ["ScrcpyKit"]),
        .executable(name: "adbctl", targets: ["adbctl"]),
        .executable(name: "AndroidHub", targets: ["AndroidHub"]),
    ],
    targets: [
        // Talks to the adb server directly over its socket protocol (no `adb` subprocess per call).
        .target(name: "AdbKit"),
        // Command-line companion, modelled on Apple's `devicectl`.
        .executableTarget(name: "adbctl", dependencies: ["AdbKit", "EmulatorKit", "ScrcpyKit"]),
        // The macOS app: sidebar / canvas / inspector, modelled on Xcode 27's Device Hub.
        // Swift 5 language mode: AppKit/AVFoundation interop (video thread → layer) is not yet Sendable-clean.
        .executableTarget(
            name: "AndroidHub", dependencies: ["AdbKit", "EmulatorKit", "ScrcpyKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        // Android Virtual Device management (the counterpart of Device Hub's simulator management).
        .target(name: "EmulatorKit", dependencies: ["AdbKit"]),
        // Screen mirroring + input injection: a native client for the (pinned) scrcpy-server protocol.
        .target(
            name: "ScrcpyKit", dependencies: ["AdbKit"],
            resources: [.copy("Resources/scrcpy-server-3.3.4.jar"), .copy("Resources/SCRCPY-LICENSE.txt")]),
        .testTarget(name: "AdbKitTests", dependencies: ["AdbKit"]),
        .testTarget(name: "ScrcpyKitTests", dependencies: ["ScrcpyKit"]),
        .testTarget(name: "EmulatorKitTests", dependencies: ["EmulatorKit", "AdbKit"]),
    ]
)
