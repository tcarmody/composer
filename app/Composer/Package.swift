// swift-tools-version: 6.0
import PackageDescription

// Command-line build of the Composer macOS app. `swift build` produces the
// bare executable; scripts/build-mac-app.sh wraps it into a signed .app bundle.
// The Xcode project (project.yml + xcodegen) still works and builds the same
// sources — keep the two in sync if you add source directories.
let package = Package(
    name: "Composer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Composer",
            path: "Composer",
            exclude: [
                "Info.plist",
                "Composer.entitlements",
                "Assets.xcassets",
            ],
            swiftSettings: [
                // Matches SWIFT_VERSION 5.10 in project.yml.
                .swiftLanguageMode(.v5),
                // Xcode turns this on by default; SwiftPM in v5 mode does not.
                // AskTranscriptView uses bare `/.../` regex literals.
                .enableUpcomingFeature("BareSlashRegexLiterals"),
            ]
        ),
        .testTarget(
            name: "ComposerTests",
            dependencies: ["Composer"],
            path: "Tests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .enableUpcomingFeature("BareSlashRegexLiterals"),
            ]
        ),
    ]
)
