// swift-tools-version: 6.0
import PackageDescription

// Pure QR logic (encode, render, decode) with no UI dependency, so `swift test` covers it on its own.
let package = Package(
    name: "QRBarKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "QRBarKit", targets: ["QRBarKit"]),
    ],
    targets: [
        .target(name: "QRBarKit"),
        .testTarget(name: "QRBarKitTests", dependencies: ["QRBarKit"]),
    ]
)
