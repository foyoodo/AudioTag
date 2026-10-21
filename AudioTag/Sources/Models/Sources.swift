//
//  Sources.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import Foundation

/// The folders and files the user gave AudioTag, which are all it can reach in its sandbox.
/// Each is kept as a security-scoped bookmark, so it can be reached again after a relaunch.
@MainActor
final class Sources {
  static let didChangeNotification = Notification.Name("SourcesDidChange")

  /// A folder or file given, and whether it can be reached.
  struct Entry: Equatable {
    let url: URL
    let isFolder: Bool
    /// False where its bookmark couldn't be resolved, as when it was moved to a volume
    /// that's gone, or is no longer readable.
    let isAvailable: Bool
    fileprivate let bookmark: Data?
  }

  private nonisolated static let defaultsKey = "Sources"

  private(set) var entries: [Entry] = [] {
    didSet {
      save()
      NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
  }

  nonisolated init() {}

  var folders: [Entry] { entries.filter(\.isFolder) }
  var files: [Entry] { entries.filter { !$0.isFolder } }

  /// Resolves the bookmarks kept, and starts reaching what they point to.
  func restore() {
    let saved = UserDefaults.standard.array(forKey: Self.defaultsKey) as? [[String: Any]] ?? []
    var entries: [Entry] = []
    for record in saved {
      guard let path = record["path"] as? String, let isFolder = record["isFolder"] as? Bool else {
        continue
      }
      let fallback = URL(filePath: path, directoryHint: isFolder ? .isDirectory : .notDirectory)
      guard let bookmark = record["bookmark"] as? Data else {
        entries.append(Entry(url: fallback, isFolder: isFolder, isAvailable: false, bookmark: nil))
        continue
      }
      var isStale = false
      guard
        let url = try? URL(
          resolvingBookmarkData: bookmark, options: .withSecurityScope,
          bookmarkDataIsStale: &isStale),
        url.startAccessingSecurityScopedResource()
          || FileManager.default.isReadableFile(atPath: url.path)
      else {
        entries.append(
          Entry(url: fallback, isFolder: isFolder, isAvailable: false, bookmark: bookmark))
        continue
      }
      let renewed = isStale ? Self.bookmark(for: url) ?? bookmark : bookmark
      entries.append(
        Entry(
          url: url.standardizedFileURL, isFolder: isFolder, isAvailable: true, bookmark: renewed))
    }
    self.entries = entries
  }

  /// The folder given that is `url` or holds it.
  func folder(containing url: URL) -> URL? {
    let path = url.standardizedFileURL.path
    return folders.first {
      $0.isAvailable && (path == $0.url.path || path.hasPrefix($0.url.path + "/"))
    }?.url
  }

  /// Keeps the folders and files the user just gave, which AudioTag can reach for now, to reach
  /// them later too. Those in a folder kept already are left out, as is what can't be kept.
  func add(_ urls: [URL]) {
    var entries = entries
    for url in urls.map(\.standardizedFileURL) {
      guard !entries.contains(where: { $0.url == url }),
        !entries.contains(where: {
          $0.isFolder && $0.isAvailable && url.path.hasPrefix($0.url.path + "/")
        })
      else { continue }
      let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
      guard let bookmark = Self.bookmark(for: url) else { continue }
      _ = url.startAccessingSecurityScopedResource()
      entries.append(Entry(url: url, isFolder: isFolder, isAvailable: true, bookmark: bookmark))
    }
    if entries != self.entries { self.entries = entries }
  }

  func remove(_ url: URL) {
    guard let entry = entries.first(where: { $0.url == url }) else { return }
    if entry.isAvailable { url.stopAccessingSecurityScopedResource() }
    entries.removeAll { $0.url == url }
  }

  private func save() {
    let records: [[String: Any]] = entries.map { entry in
      var record: [String: Any] = ["path": entry.url.path, "isFolder": entry.isFolder]
      record["bookmark"] = entry.bookmark
      return record
    }
    UserDefaults.standard.set(records, forKey: Self.defaultsKey)
  }

  private static func bookmark(for url: URL) -> Data? {
    try? url.bookmarkData(
      options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
  }
}
