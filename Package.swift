// swift-tools-version:5.6
import PackageDescription

var globalConcurrencyFlags: [String] = [
  "-Xfrontend", "-disable-availability-checking", // TODO(distributed): remove this flag
]

let package = Package(
  name: "ClientServerRPC",
  platforms: [
    .macOS(.v12),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.40.0"),
    // 💧 A server-side Swift web framework.
    .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
    .package(url: "https://github.com/swift-server/async-http-client", from: "1.10.0"),
  ],
  targets: [
    .executableTarget(
      name: "Server",
      dependencies: [
        .product(name: "AsyncHTTPClient", package: "async-http-client"),
        .product(name: "Vapor", package: "vapor"),
        "ClientServerRPC",
      ],
      swiftSettings: [
        // Enable better optimizations when building in Release configuration. Despite the use of
        // the `.unsafeFlags` construct required by SwiftPM, this flag is recommended for Release
        // builds. See <https://github.com/swift-server/guides/blob/main/docs/building.md#building-for-production> for details.
        .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release)),
        .unsafeFlags(globalConcurrencyFlags),
      ]
    ),
    .executableTarget(
      name: "Client",
      dependencies: [
        "ClientServerRPC",
      ]
    ),
    .target(
      name: "ClientServerRPC",
      dependencies: [
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOFoundationCompat", package: "swift-nio"),
      ],
      swiftSettings: [
        // Enable better optimizations when building in Release configuration. Despite the use of
        // the `.unsafeFlags` construct required by SwiftPM, this flag is recommended for Release
        // builds. See <https://github.com/swift-server/guides/blob/main/docs/building.md#building-for-production> for details.
        .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release)),
        .unsafeFlags(globalConcurrencyFlags),
      ]
    ),
    .testTarget(name: "ServerTests", dependencies: [
      .target(name: "Server"),
      .product(name: "XCTVapor", package: "vapor"),
    ]),
  ]
)
