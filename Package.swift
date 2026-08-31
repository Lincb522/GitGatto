// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "GitGatto",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GitGatto", targets: ["GitGatto"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
        .package(url: "https://github.com/Alamofire/Alamofire", exact: "5.12.0")
    ],
    targets: [
        .executableTarget(
            name: "GitGatto",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Alamofire", package: "Alamofire")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "GitGattoTests",
            dependencies: ["GitGatto"]
        )
    ]
)
