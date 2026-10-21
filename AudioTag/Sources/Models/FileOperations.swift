//
//  FileOperations.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit

/// Renames, moves, makes and trashes the files and folders in the sidebar's folders, each of
/// which can be undone, the library's tracks following their files.
@MainActor
final class FileOperations {
  /// Posted after files or folders were moved, renamed, made or trashed, with the folders whose
  /// contents changed under `foldersKey`, and what moved where under `movesKey`.
  static let didChangeNotification = Notification.Name("FileOperationsDidChange")
  static let foldersKey = "folders"
  static let movesKey = "moves"

  private let library: Library

  nonisolated init(library: Library) {
    self.library = library
  }

  /// Renames the file or folder, returning where it is now.
  @discardableResult
  func rename(_ url: URL, to name: String, undoManager: UndoManager?) throws -> URL {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else {
      throw CocoaError(.fileWriteInvalidFileName, userInfo: [NSFilePathErrorKey: name])
    }
    let destination = url.deletingLastPathComponent().appending(path: name).standardizedFileURL
    guard destination != url else { return url }
    try move([(url, destination)], actionName: "Rename", undoManager: undoManager)
    return destination
  }

  /// Moves the files and folders into `folder`, returning where they are now.
  @discardableResult
  func move(_ urls: [URL], into folder: URL, undoManager: UndoManager?) throws -> [URL] {
    let moves = urls.map { ($0, folder.appending(path: $0.lastPathComponent).standardizedFileURL) }
      .filter { $0 != $1 }
    try move(
      moves, actionName: urls.count == 1 ? "Move" : "Move \(urls.count) Items",
      undoManager: undoManager)
    return moves.map(\.1)
  }

  /// Makes an untitled folder in `folder`, returning it.
  @discardableResult
  func makeFolder(in folder: URL, undoManager: UndoManager?) throws -> URL {
    var name = "untitled folder"
    var number = 2
    while FileManager.default.fileExists(atPath: folder.appending(path: name).path) {
      name = "untitled folder \(number)"
      number += 1
    }
    let url = folder.appending(path: name, directoryHint: .isDirectory).standardizedFileURL
    try make(url, undoManager: undoManager)
    return url
  }

  /// Moves the files and folders to the Trash, letting go of their tracks, edits and all.
  func trash(_ urls: [URL], undoManager: UndoManager?) throws {
    var trashed: [(from: URL, to: URL)] = []
    defer {
      if !trashed.isEmpty {
        library.forget(trashed.map(\.from))
        announce(folders: trashed.map { $0.from.deletingLastPathComponent() }, moves: [])
        // Undone, they're moved back out of the Trash.
        let restores = trashed.map { (from: $0.to, to: $0.from) }
        undoManager?.registerUndo(withTarget: self) { operations in
          try? operations.move(restores, actionName: "Move to Trash", undoManager: undoManager)
        }
        undoManager?.setActionName("Move to Trash")
      }
    }
    for url in urls {
      var trashedURL: NSURL?
      try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
      if let trashedURL { trashed.append((url, trashedURL as URL)) }
    }
  }

  /// Moves each `from` to its `to`, all or none of them.
  private func move(
    _ moves: [(from: URL, to: URL)], actionName: String, undoManager: UndoManager?
  ) throws {
    guard !moves.isEmpty else { return }
    var moved: [(from: URL, to: URL)] = []
    do {
      for (from, to) in moves {
        try FileManager.default.moveItem(at: from, to: to)
        moved.append((from, to))
      }
    } catch {
      for (from, to) in moved.reversed() { try? FileManager.default.moveItem(at: to, to: from) }
      throw error
    }
    library.filesDidMove(moved)
    announce(
      folders: moved.flatMap {
        [$0.from.deletingLastPathComponent(), $0.to.deletingLastPathComponent()]
      },
      moves: moved)
    let reversed = moved.reversed().map { (from: $0.to, to: $0.from) }
    undoManager?.registerUndo(withTarget: self) { operations in
      try? operations.move(reversed, actionName: actionName, undoManager: undoManager)
    }
    undoManager?.setActionName(actionName)
  }

  private func make(_ folder: URL, undoManager: UndoManager?) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    announce(folders: [folder.deletingLastPathComponent()], moves: [])
    undoManager?.registerUndo(withTarget: self) { operations in
      operations.unmake(folder, undoManager: undoManager)
    }
    undoManager?.setActionName("New Folder")
  }

  /// Removes a folder that was made, if it's still empty; otherwise it's left, for what's in it.
  private func unmake(_ folder: URL, undoManager: UndoManager?) {
    guard (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true,
      (try? FileManager.default.removeItem(at: folder)) != nil
    else { return }
    announce(folders: [folder.deletingLastPathComponent()], moves: [])
    undoManager?.registerUndo(withTarget: self) { operations in
      try? operations.make(folder, undoManager: undoManager)
    }
    undoManager?.setActionName("New Folder")
  }

  private func announce(folders: [URL], moves: [(from: URL, to: URL)]) {
    NotificationCenter.default.post(
      name: Self.didChangeNotification, object: self,
      userInfo: [
        Self.foldersKey: Set(folders.map(\.standardizedFileURL)),
        Self.movesKey: Dictionary(moves.map { ($0.from, $0.to) }, uniquingKeysWith: { $1 }),
      ])
  }
}

extension FileOperations {
  /// Moves the files and folders to the Trash, asking first where that would discard edits
  /// that haven't been saved, and telling of any that couldn't be.
  func trash(_ urls: [URL], from window: NSWindow?) async {
    guard !urls.isEmpty else { return }
    let edited = library.knownTracks(at: urls).filter(\.isModified)
    if !edited.isEmpty, let window {
      let alert = NSAlert()
      alert.messageText =
        edited.count == 1
        ? "“\(edited[0].name)” has changes that haven’t been saved."
        : "\(edited.count) files have changes that haven’t been saved."
      alert.informativeText = "Moving them to the Trash discards the changes."
      alert.addButton(withTitle: "Move to Trash").hasDestructiveAction = true
      alert.addButton(withTitle: "Cancel")
      guard await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else { return }
    }
    perform(in: window) { try trash(urls, undoManager: window?.undoManager) }
  }

  /// Does a file operation, telling of the error, if any, in `window`.
  func perform(in window: NSWindow?, _ operation: () throws -> Void) {
    do {
      try operation()
    } catch {
      if let window {
        window.presentError(
          error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
      } else {
        NSApp.presentError(error)
      }
    }
  }
}
