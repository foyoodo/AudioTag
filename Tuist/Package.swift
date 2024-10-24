// swift-tools-version: 5.10
import PackageDescription

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "AudioTag",
    dependencies: [
        .package(url: "https://github.com/OtoFlow/TagLib-Swift.git", branch: "main")
    ]
)
