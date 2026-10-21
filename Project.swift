import ProjectDescription

let project = Project(
  name: "AudioTag",
  targets: [
    .target(
      name: "AudioTag",
      destinations: .macOS,
      product: .app,
      bundleId: "com.foyoodo.AudioTag",
      deploymentTargets: .macOS("14.0"),
      infoPlist: .extendingDefault(with: [
        // The interface is built in code.
        "NSMainStoryboardFile": "",
        "CFBundleDocumentTypes": [
          [
            "CFBundleTypeName": "Audio File",
            "CFBundleTypeRole": "Editor",
            "LSHandlerRank": "Alternate",
            "LSItemContentTypes": ["public.audio"],
          ]
        ],
      ]),
      buildableFolders: [
        "AudioTag/Sources",
        "AudioTag/Resources",
      ],
      // Sandboxed, AudioTag reaches only the files and folders the user gives it, and keeps
      // them as security-scoped bookmarks to reach them after a relaunch.
      entitlements: .dictionary([
        "com.apple.security.app-sandbox": true,
        "com.apple.security.files.user-selected.read-write": true,
        "com.apple.security.files.bookmarks.app-scope": true,
      ]),
      dependencies: [
        .external(name: "TagLib")
      ],
      settings: .settings(base: ["SWIFT_VERSION": "6.0"])
    ),
    .target(
      name: "AudioTagTests",
      destinations: .macOS,
      product: .unitTests,
      bundleId: "com.foyoodo.AudioTagTests",
      infoPlist: .default,
      buildableFolders: ["AudioTag/Tests"],
      dependencies: [.target(name: "AudioTag")],
      settings: .settings(base: ["SWIFT_VERSION": "6.0"])
    ),
  ]
)
