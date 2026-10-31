// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DropShelf",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DropShelf", targets: ["DropShelf"])
    ],
    targets: [
        .executableTarget(
            name: "DropShelf",
            path: "Sources/DropShelf",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("QuickLookUI"),
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "DropShelfTests",
            dependencies: ["DropShelf"],
            path: "Tests/DropShelfTests"
        )
    ]
)
