// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "Camelot",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .library(name: "CamelotCore", targets: ["CamelotCore"]),
    .executable(name: "Camelot", targets: ["Camelot"]),
  ],
  targets: [
    .target(name: "CamelotCore"),
    .executableTarget(
      name: "Camelot",
      dependencies: ["CamelotCore"],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("ApplicationServices"),
        .linkedFramework("Carbon"),
        .linkedFramework("CoreGraphics"),
        .linkedFramework("SwiftUI"),
      ]
    ),
    .testTarget(
      name: "CamelotCoreTests",
      dependencies: ["CamelotCore", "Camelot"]
    ),
  ],
  swiftLanguageModes: [.v5]
)
