//
//  MainWindowController.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit

/// The window, its toolbar, and the commands that act on the library: saving, reverting and
/// filtering.
final class MainWindowController: NSWindowController {
  private let library: Library
  private let splitViewController: MainSplitViewController
  private let searchItem = NSSearchToolbarItem(itemIdentifier: .search)

  init(library: Library, sources: Sources) {
    self.library = library
    splitViewController = MainSplitViewController(library: library, sources: sources)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.title = "AudioTag"
    window.toolbarStyle = .unified
    // Before the sidebar is loaded, and selects a folder.
    splitViewController.onSourceChange = { [weak window] source in
      window?.title = source?.title ?? "AudioTag"
      if case .folder(let url) = source {
        window?.representedURL = url
      } else {
        window?.representedURL = nil
      }
    }
    splitViewController.onStatusChange = { [weak window] status in
      window?.subtitle = status
    }
    window.contentViewController = splitViewController
    window.minSize = NSSize(width: 820, height: 420)
    window.setContentSize(NSSize(width: 1180, height: 720))
    window.center()
    super.init(window: window)
    window.delegate = self

    let toolbar = NSToolbar(identifier: "Main")
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = true
    toolbar.autosavesConfiguration = true
    window.toolbar = toolbar
    windowFrameAutosaveName = "Main"

    searchItem.searchField.placeholderString = "Filter"
    searchItem.searchField.target = self
    searchItem.searchField.action = #selector(filterChanged(_:))

    NotificationCenter.default.addObserver(
      self, selector: #selector(tracksDidChange), name: Library.tracksDidChangeNotification,
      object: library)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func open(_ urls: [URL]) {
    splitViewController.open(urls)
  }

  @objc private func tracksDidChange() {
    window?.isDocumentEdited = library.hasModifiedTracks
  }

  // MARK: Saving

  /// Saves the tracks' edits, telling of the files that couldn't be saved; returns whether
  /// every one was.
  @discardableResult
  func save(_ tracks: [Track]) async -> Bool {
    commitEditing()
    let failures = await library.save(tracks)
    guard !failures.isEmpty, let window else { return failures.isEmpty }
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText =
      failures.count == 1
      ? "“\(failures[0].track.name)” couldn’t be saved."
      : "\(failures.count) files couldn’t be saved."
    alert.informativeText = failures.prefix(8)
      .map { failures.count == 1 ? $0.error.message : "\($0.track.name): \($0.error.message)" }
      .joined(separator: "\n")
    // Those whose formats can't hold some of what they're given can be saved without it.
    let savable = failures.filter(\.error.isUnsupportedContent).map(\.track)
    if !savable.isEmpty {
      alert.addButton(
        withTitle: savable.count == 1 ? "Save Without Them" : "Save Those Without Them")
      alert.addButton(withTitle: "Cancel")
    }
    guard await alert.beginSheetModal(for: window) == .alertFirstButtonReturn, !savable.isEmpty
    else { return false }
    let stillFailing = await library.save(savable, skippingUnsupportedTags: true)
    return stillFailing.isEmpty && savable.count == failures.count
  }

  /// Asks whether to save the files edited before they're closed; tells `completion` whether
  /// to go on closing them, once they're saved or their edits discarded.
  func confirmClosing(_ completion: @escaping (Bool) -> Void) {
    commitEditing()
    let tracks = library.modifiedTracks
    guard !tracks.isEmpty, let window else {
      completion(true)
      return
    }
    let alert = NSAlert()
    alert.messageText =
      tracks.count == 1
      ? "Do you want to save the changes made to “\(tracks[0].name)”?"
      : "Do you want to save the changes made to \(tracks.count) files?"
    alert.informativeText = "Your changes will be lost if you don’t save them."
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    let discard = alert.addButton(withTitle: "Don’t Save")
    discard.hasDestructiveAction = true
    alert.beginSheetModal(for: window) { [self] response in
      switch response {
      case .alertFirstButtonReturn:
        Task { completion(await save(tracks)) }
      case .alertThirdButtonReturn:
        library.revert(tracks)
        completion(true)
      default:
        completion(false)
      }
    }
  }

  /// Applies the text being edited by ending its editing: a table cell's, which is applied only
  /// then, and what an input method is still composing.
  private func commitEditing() {
    guard let window, window.firstResponder is NSTextView else { return }
    window.makeFirstResponder(nil)
  }

  // MARK: Actions

  @objc func saveDocument(_ sender: Any?) {
    Task { await save(library.modifiedTracks) }
  }

  /// Discards the edits of the tracks selected.
  @objc func revertDocumentToSaved(_ sender: Any?) {
    commitEditing()
    library.revert(splitViewController.trackList.selectedTracks)
  }

  /// Lists the source's files, and a folder's subfolders, afresh.
  @objc func reloadFolder(_ sender: Any?) {
    splitViewController.sidebar.reloadSelection()
    splitViewController.trackList.show(splitViewController.trackList.source, reloading: true)
  }

  @objc func focusSearch(_ sender: Any?) {
    searchItem.beginSearchInteraction()
  }

  @objc private func filterChanged(_ sender: NSSearchField) {
    splitViewController.trackList.filter = sender.stringValue
  }

  private func validate(_ action: Selector?) -> Bool {
    switch action {
    case #selector(saveDocument(_:)): library.hasModifiedTracks
    case #selector(revertDocumentToSaved(_:)):
      splitViewController.trackList.selectedTracks.contains { $0.isModified }
    case #selector(reloadFolder(_:)): splitViewController.trackList.source != nil
    default: true
    }
  }
}

extension MainWindowController: NSWindowDelegate {
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard library.hasModifiedTracks else { return true }
    confirmClosing { shouldClose in
      if shouldClose { sender.close() }
    }
    return false
  }
}

extension MainWindowController: NSMenuItemValidation, NSToolbarItemValidation {
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    validate(menuItem.action)
  }

  func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
    validate(item.action)
  }
}

extension NSToolbarItem.Identifier {
  fileprivate static let save = Self("Save")
  fileprivate static let revert = Self("Revert")
  fileprivate static let search = Self("Search")
}

extension MainWindowController: NSToolbarDelegate {
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
      .toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .revert, .save, .search,
      .inspectorTrackingSeparator,
      .flexibleSpace, .toggleInspector,
    ]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarDefaultItemIdentifiers(toolbar) + [.space]
  }

  func toolbar(
    _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    switch itemIdentifier {
    case .save:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Save"
      item.toolTip = "Save the edited files"
      item.image = NSImage(
        systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
      item.isBordered = true
      item.target = self
      item.action = #selector(saveDocument(_:))
      return item
    case .revert:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = "Revert"
      item.toolTip = "Discard the changes to the selected files"
      item.image = NSImage(
        systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Revert")
      item.isBordered = true
      item.target = self
      item.action = #selector(revertDocumentToSaved(_:))
      return item
    case .search:
      return searchItem
    default:
      return nil
    }
  }
}
