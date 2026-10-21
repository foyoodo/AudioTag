//
//  FileNode.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import Foundation

/// What the track list shows.
enum TrackSource: Hashable {
  /// The files of every folder in the sidebar.
  case allFiles
  /// The files edited and not saved, wherever they are.
  case edited
  /// The files opened on their own, rather than in a folder.
  case openedFiles
  case folder(URL)

  var title: String {
    switch self {
    case .allFiles: "All Files"
    case .edited: "Edited"
    case .openedFiles: "Opened Files"
    case .folder(let url): FileManager.default.displayName(atPath: url.path)
    }
  }
}

/// A folder in the sidebar, or a file in one: what's in a folder, its subfolders and the audio
/// and video files TagLib reads, is listed when first asked for.
@MainActor
final class FileNode {
  let url: URL
  let isDirectory: Bool
  /// False for a folder in the sidebar that can't be reached.
  let isAvailable: Bool
  /// The folder it's in, which a folder of the sidebar's own is in none of.
  private(set) weak var parent: FileNode?
  private var loadedChildren: [FileNode]?

  init(url: URL, isDirectory: Bool, isAvailable: Bool = true, parent: FileNode? = nil) {
    self.url = url
    self.isDirectory = isDirectory
    self.isAvailable = isAvailable
    self.parent = parent
  }

  /// Whether it's one of the folders the user gave, which can be removed from the sidebar, but
  /// not renamed, moved or trashed.
  var isRoot: Bool { parent == nil }

  /// Whether it holds a video, rather than only audio, as Matroska and M4V files do.
  var isVideo: Bool {
    ["m4v", "mkv", "webm"].contains(url.pathExtension.lowercased())
  }

  /// Its subfolders, then its files, by name.
  var children: [FileNode] {
    if let loadedChildren { return loadedChildren }
    let children = list(reusing: [:])
    loadedChildren = children
    return children
  }

  /// Its children, where they've been listed, without listing them.
  var listedChildren: [FileNode]? { loadedChildren }

  /// Lists its children afresh, if they've been listed, keeping the nodes of those still there,
  /// with what's been listed of them.
  func reload() {
    guard let loadedChildren else { return }
    self.loadedChildren = list(
      reusing: Dictionary(
        loadedChildren.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first }))
  }

  private func list(reusing existing: [URL: FileNode]) -> [FileNode] {
    guard isDirectory, isAvailable else { return [] }
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]
    let contents =
      (try? FileManager.default.contentsOfDirectory(
        at: url, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles)) ?? []
    return
      contents
      .compactMap { url -> (url: URL, isDirectory: Bool)? in
        let values = try? url.resourceValues(forKeys: keys)
        if values?.isDirectory == true, values?.isPackage != true { return (url, true) }
        return Library.fileExtensions.contains(url.pathExtension.lowercased()) ? (url, false) : nil
      }
      .sorted { lhs, rhs in
        lhs.isDirectory != rhs.isDirectory
          ? lhs.isDirectory
          : lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent)
            == .orderedAscending
      }
      .map { url, isDirectory in
        let url = url.standardizedFileURL
        if let node = existing[url], node.isDirectory == isDirectory { return node }
        return FileNode(url: url, isDirectory: isDirectory, parent: self)
      }
  }
}
