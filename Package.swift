// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Folio",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Folio", targets: ["FolioApp"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "FolioCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "FolioApp", dependencies: ["FolioCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "FolioCoreTests", dependencies: ["FolioCore"]),
        .testTarget(name: "FolioAppTests", dependencies: ["FolioApp", "FolioCore"], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
