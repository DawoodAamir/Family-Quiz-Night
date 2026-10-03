// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "FamilyQuizCore", platforms: [.macOS(.v15)],
  products: [.library(name: "FamilyQuizCore", targets: ["FamilyQuizCore"])],
  targets: [
    .target(name: "FamilyQuizCore", path: "Sources/Core"),
    .testTarget(name: "FamilyQuizCoreTests", dependencies: ["FamilyQuizCore"], path: "Tests/Core"),
  ])
