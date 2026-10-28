// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WaybillRouter",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        // Projekt xtool musi mieć dokładnie jeden produkt typu library = główna aplikacja.
        .library(
            name: "WaybillRouter",
            targets: ["WaybillRouter"]
        ),
    ],
    targets: [
        .target(
            name: "WaybillRouter",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
