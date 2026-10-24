// swift-tools-version: 6.0
import PackageDescription

#if TUIST
  import struct ProjectDescription.PackageSettings

  let packageSettings = PackageSettings(
    productTypes: [:]
  )
#endif

let package = Package(
  name: "AudioTag",
  dependencies: [
    .package(path: "../Frameworks/TagLib-Swift"),
    // Keep this exact version in sync with SPARKLE_TOOLS_VERSION in
    // scripts/ci-generate-appcast.sh (generate_appcast / generate_keys).
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
  ]
)
