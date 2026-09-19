// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "FreeSpeakLlama",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [.library(name: "FreeSpeakLlama", targets: ["llama"])],
  targets: [
    .binaryTarget(
      name: "llama",
      url:
        "https://github.com/ggml-org/llama.cpp/releases/download/b9000/llama-b9000-xcframework.zip",
      checksum: "bb1e87e44543dd22dd9a9b344d529c3146e3f6a0364bef0570c407d5d69a3b0c"
    )
  ]
)
