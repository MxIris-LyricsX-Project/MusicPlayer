// swift-tools-version:5.3

import PackageDescription
import Foundation

extension Package.Dependency {
    enum LocalSearchPath {
        case package(path: String, isRelative: Bool, isEnabled: Bool)
    }

    static func package(local localSearchPaths: LocalSearchPath..., remote: Package.Dependency) -> Package.Dependency {
        for local in localSearchPaths {
            switch local {
            case .package(let path, let isRelative, let isEnabled):
                guard isEnabled else { continue }
                let url = if isRelative, let resolvedURL = URL(string: path, relativeTo: URL(fileURLWithPath: #filePath)) {
                    resolvedURL
                } else {
                    URL(fileURLWithPath: path)
                }

                if FileManager.default.fileExists(atPath: url.path) {
                    return .package(path: url.path)
                }
            }
        }
        return remote
    }
}

let package = Package(
    name: "MusicPlayer",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
    ],
    products: [
        .library(name: "MusicPlayer", targets: ["MusicPlayer"]),
        .library(name: "LXMusicPlayer", targets: ["LXMusicPlayer"]),
    ],
    dependencies: [
        .package(
            local: .package(
                path: "../mediaremote-adapter",
                isRelative: true,
                isEnabled: true
            ),
            remote: .package(
                url: "https://github.com/MxIris-LyricsX-Project/mediaremote-adapter",
                .branchItem("master")
            )
        ),
        
    ],
    targets: [
        .target(
            name: "MusicPlayer",
            dependencies: [
                .target(name: "LXMusicPlayer", condition: .when(platforms: [.macOS])),
                .target(name: "MediaRemotePrivate", condition: .when(platforms: [.macOS, .iOS])),
                .product(name: "MediaRemoteAdapter", package: "mediaremote-adapter"),
            ], cSettings: [
                .define("TARGET_OS_MAC", to: "1", .when(platforms: [.macOS, .iOS])),
                .define("TARGET_OS_IPHONE", to: "1", .when(platforms: [.iOS])),
            ]
        ),
        .target(
            name: "LXMusicPlayer",
            cSettings: [
                .define("TARGET_OS_MAC", to: "1", .when(platforms: [.macOS, .iOS])),
                .define("TARGET_OS_IPHONE", to: "1", .when(platforms: [.iOS])),
                .headerSearchPath("private"),
                .headerSearchPath("BridgingHeader"),
            ]
        ),
        .target(
            name: "MediaRemotePrivate",
            dependencies: [
            ],
            cSettings: [
                .define("TARGET_OS_MAC", to: "1", .when(platforms: [.macOS, .iOS])),
                .define("TARGET_OS_IPHONE", to: "1", .when(platforms: [.iOS])),
            ]
        ),
    ]
)
