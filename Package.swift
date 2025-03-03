// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "MusicPlayer",
    platforms: [
        .macOS(.v10_10),
        .iOS(.v10),
    ],
    products: [
        .library(name: "MusicPlayer", targets: ["MusicPlayer"]),
        .library(name: "LXMusicPlayer", targets: ["LXMusicPlayer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/MxIris-LyricsX-Project/CXShim", .branchItem("master")),
        .package(url: "https://github.com/MxIris-LyricsX-Project/CXExtensions", .branchItem("master")),
        .package(url: "https://github.com/PrivateFrameworks/ProtocolBuffer", .upToNextMinor(from: "0.1.0")),
    ],
    targets: [
        .target(
            name: "MusicPlayer",
            dependencies: [
                "CXShim",
                "CXExtensions",
                .target(name: "LXMusicPlayer", condition: .when(platforms: [.macOS])),
                .target(name: "MediaRemotePrivate", condition: .when(platforms: [.macOS, .iOS])),
                .target(name: "playerctl", condition: .when(platforms: [.linux])),
            ], cSettings: [
                .define("TARGET_OS_MAC", to: "1", .when(platforms: [.macOS, .iOS])),
                .define("TARGET_OS_IPHONE", to: "1", .when(platforms: [.iOS])),
            ]),
        .target(
            name: "LXMusicPlayer",
            cSettings: [
                .define("TARGET_OS_MAC", to: "1", .when(platforms: [.macOS, .iOS])),
                .define("TARGET_OS_IPHONE", to: "1", .when(platforms: [.iOS])),
                .headerSearchPath("private"),
                .headerSearchPath("BridgingHeader"),
            ]),
        .target(
            name: "MediaRemotePrivate",
            dependencies: [
                .product(name: "PrivateProtocolBuffer", package: "ProtocolBuffer"),
            ],
            cSettings: [
                .define("TARGET_OS_MAC", to: "1", .when(platforms: [.macOS, .iOS])),
                .define("TARGET_OS_IPHONE", to: "1", .when(platforms: [.iOS])),
            ]),
        .systemLibrary(name: "playerctl", pkgConfig: "playerctl"),
    ]
)

enum CombineImplementation {
    
    case combine
    case combineX
    case openCombine
    
    static var `default`: CombineImplementation {
        return .combineX
    }
    
    init?(_ description: String) {
        let desc = description.lowercased().filter { $0.isLetter }
        switch desc {
        case "combine":     self = .combine
        case "combinex":    self = .combineX
        case "opencombine": self = .openCombine
        default:            return nil
        }
    }
}

extension ProcessInfo {

    var combineImplementation: CombineImplementation {
        return environment["CX_COMBINE_IMPLEMENTATION"].flatMap(CombineImplementation.init) ?? .default
    }
    
    var enableSpotifyiOS: Bool {
        return environment["LX_ENABLE_SPOTIFYIOS"] != nil
    }
}

import Foundation

let info = ProcessInfo.processInfo

if info.combineImplementation == .combine {
    package.platforms = [.macOS(.v10_15), .iOS(.v13)]
}

// This breaks macOS build
// error: While building for macOS, no library for this platform was found in 'SpotifyiOS.xcframework'.
if info.enableSpotifyiOS {
    package.dependencies += [
        .package(url: "https://github.com/ddddxxx/SpotifyiOSWrapper", from: "1.2.2"),
    ]
    package.targets.first { $0.name == "MusicPlayer" }!.dependencies += [
        .product(name: "SpotifyiOSWrapper", package: "SpotifyiOSWrapper", condition: .when(platforms: [.iOS]))
    ]
}
