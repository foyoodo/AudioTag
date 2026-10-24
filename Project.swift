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
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "CFBundleDocumentTypes": [
          [
            "CFBundleTypeName": "Audio File",
            "CFBundleTypeRole": "Editor",
            "LSHandlerRank": "Alternate",
            "LSItemContentTypes": ["public.audio"],
          ]
        ],
        // Sparkle 2 (sandboxed): installer XPC is required; the downloader XPC is
        // used instead of com.apple.security.network.client on the app itself.
        "SUFeedURL": "$(SPARKLE_FEED_URL)",
        "SUPublicEDKey": "$(SPARKLE_PUBLIC_ED_KEY)",
        "SUEnableInstallerLauncherService": true,
        "SUEnableDownloaderService": true,
      ]),
      buildableFolders: [
        "AudioTag/Sources",
        "AudioTag/Resources",
      ],
      // Sandboxed, AudioTag reaches only the files and folders the user gives it, and keeps
      // them as security-scoped bookmarks to reach them after a relaunch.
      // Mach-lookup exceptions are Sparkle installer status/progress ports; codesign does
      // not expand $(PRODUCT_BUNDLE_IDENTIFIER), so the bundle ID is written out.
      entitlements: .dictionary([
        "com.apple.security.app-sandbox": true,
        "com.apple.security.files.user-selected.read-write": true,
        "com.apple.security.files.bookmarks.app-scope": true,
        "com.apple.security.temporary-exception.mach-lookup.global-name": .array([
          "com.foyoodo.AudioTag-spks",
          "com.foyoodo.AudioTag-spki",
        ]),
      ]),
      dependencies: [
        .external(name: "TagLib"),
        .external(name: "Sparkle"),
      ],
      settings: .settings(base: [
        "SWIFT_VERSION": "6.0",
        // MARKETING_VERSION is the user-facing version and must match a v* git tag.
        // CURRENT_PROJECT_VERSION is CFBundleVersion, which Sparkle uses to decide
        // whether an update is newer. Increase it by 1 on every release (1, 2, 3, …).
        "MARKETING_VERSION": "0.1.1",
        "CURRENT_PROJECT_VERSION": "2",
        "SPARKLE_FEED_URL":
          "https://github.com/foyoodo/AudioTag/releases/latest/download/appcast.xml",
        // Base64 EdDSA public key from Sparkle's generate_keys. Empty is allowed on
        // PRs and main; a v* tag build fails unless this is set, and the release
        // job fails unless SPARKLE_ED_PRIVATE_KEY matches it.
        "SPARKLE_PUBLIC_ED_KEY": "",
      ])
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
