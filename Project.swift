import ProjectDescription

let project = Project(
    name: "AudioTag",
    targets: [
        .target(
            name: "AudioTag",
            destinations: .macOS,
            product: .app,
            bundleId: "com.foyoodo.AudioTag",
            infoPlist: .default,
            sources: ["AudioTag/Sources/**"],
            resources: ["AudioTag/Resources/**"],
            dependencies: [
                .external(name: "TagLib-Swift"),
            ]
        ),
        .target(
            name: "AudioTagTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.foyoodo.AudioTagTests",
            infoPlist: .default,
            sources: ["AudioTag/Tests/**"],
            resources: [],
            dependencies: [.target(name: "AudioTag")]
        ),
    ]
)
