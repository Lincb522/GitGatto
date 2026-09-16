// swift-tools-version: 6.1
import PackageDescription

let package = Package(name: "GitGattoRemote", platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "GitGattoRemote", targets: ["GitGattoRemote"])],
    targets: [.target(name: "GitGattoRemote"),
              .testTarget(name: "GitGattoRemoteTests", dependencies: ["GitGattoRemote"])])
