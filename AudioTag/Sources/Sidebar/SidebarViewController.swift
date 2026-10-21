//
//  SidebarViewController.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit

/// The sources of the track list: the library as a whole, the files edited, and the folders the
/// user browses, with the audio and video files in them, which can be renamed, moved between
/// folders, and moved to the Trash, as can folders, and folders made.
final class SidebarViewController: NSViewController {
  /// A row of the sidebar: one of the library's sources.
  @MainActor
  private final class SourceItem {
    let source: TrackSource

    init(_ source: TrackSource) {
      self.source = source
    }
  }

  private enum Section: String, CaseIterable {
    case library = "Library"
    case folders = "Folders"
  }

  /// Where the item selected is kept, as `allFiles`, `edited`, `openedFiles`, or a path.
  private static let selectionKey = "SelectedSource"

  private let library: Library
  private let sources: Sources
  private let fileOperations: FileOperations
  private let thumbnails: ArtworkThumbnails
  private let outlineView = SidebarOutlineView()
  private let allFilesItem = SourceItem(.allFiles)
  private let editedItem = SourceItem(.edited)
  private let openedFilesItem = SourceItem(.openedFiles)
  private var roots: [FileNode] = []
  /// Whether the selection is changing to follow the track list, rather than to change what it
  /// shows.
  private var isFollowingTrackList = false

  /// The library's sources: Opened Files only where there are some.
  private var sourceItems: [SourceItem] {
    sources.files.isEmpty
      ? [allFilesItem, editedItem] : [allFilesItem, editedItem, openedFilesItem]
  }

  /// Told of the source selected, and of the file, where a file is: its folder is the source.
  var onSelect: ((TrackSource?, URL?) -> Void)?

  init(
    library: Library, sources: Sources, fileOperations: FileOperations,
    thumbnails: ArtworkThumbnails
  ) {
    self.library = library
    self.sources = sources
    self.fileOperations = fileOperations
    self.thumbnails = thumbnails
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private var selectedItem: Any? {
    outlineView.item(atRow: outlineView.selectedRow)
  }

  var selectedSource: TrackSource? {
    switch selectedItem {
    case let item as SourceItem: item.source
    case let node as FileNode:
      .folder(node.isDirectory ? node.url : node.url.deletingLastPathComponent())
    default: nil
    }
  }

  /// The folder new folders are made in: the one selected, or the selected file's.
  var selectedFolder: URL? {
    guard let node = selectedItem as? FileNode, node.isAvailable else { return nil }
    return node.isDirectory ? node.url : node.url.deletingLastPathComponent()
  }

  override func loadView() {
    let column = NSTableColumn(identifier: .init("Source"))
    outlineView.addTableColumn(column)
    outlineView.outlineTableColumn = column
    outlineView.headerView = nil
    outlineView.style = .sourceList
    outlineView.floatsGroupRows = false
    outlineView.dataSource = self
    outlineView.delegate = self
    outlineView.autosaveName = "Sidebar"
    outlineView.autosaveExpandedItems = true
    outlineView.registerForDraggedTypes([.fileURL])
    outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
    outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
    outlineView.onReturn = { [weak self] in self?.renameSelection() ?? false }

    let menu = NSMenu()
    menu.delegate = self
    outlineView.menu = menu

    let scrollView = NSScrollView()
    scrollView.documentView = outlineView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.autohidesScrollers = true

    let addButton = NSButton(
      image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Folder")!,
      target: nil, action: #selector(AppDelegate.openDocument(_:)))
    addButton.isBordered = false
    addButton.toolTip = "Add a folder to the sidebar"

    let bottomBar = NSStackView(views: [addButton])
    bottomBar.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 8, right: 12)

    let stack = NSStackView(views: [scrollView, bottomBar])
    stack.orientation = .vertical
    stack.spacing = 0
    stack.alignment = .leading
    scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    view = stack
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(sourcesDidChange), name: Sources.didChangeNotification,
      object: sources)
    center.addObserver(
      self, selector: #selector(tracksDidChange(_:)), name: Library.tracksDidChangeNotification,
      object: library)
    center.addObserver(
      self, selector: #selector(filesDidChange(_:)), name: FileOperations.didChangeNotification,
      object: fileOperations)
    center.addObserver(
      self, selector: #selector(thumbnailDidMake(_:)),
      name: ArtworkThumbnails.didMakeNotification, object: thumbnails)
    reloadRoots()
    let saved = UserDefaults.standard.string(forKey: Self.selectionKey)
    switch saved {
    case "allFiles", nil: select(.allFiles)
    case "edited": select(.edited)
    case "openedFiles": select(.openedFiles)
    case let path?: reveal(URL(filePath: path))
    }
    if outlineView.selectedRow < 0 { select(.allFiles) }
  }

  // MARK: Selecting

  /// Selects the source, showing the folders a folder is in.
  func select(_ source: TrackSource) {
    switch source {
    case .folder(let folder): reveal(folder)
    default: select(item: sourceItems.first { $0.source == source })
    }
  }

  /// Selects the node of a file or folder, showing the folders it's in.
  func reveal(_ url: URL) {
    select(item: revealedNode(for: url))
  }

  /// Shows a file selected in the track list: the folders it's in expanded, and its row
  /// selected, without the track list being told, as what it shows stays as it is.
  func follow(_ file: URL) {
    guard sources.folder(containing: file) != nil,
      (selectedItem as? FileNode)?.url != file.standardizedFileURL,
      let node = revealedNode(for: file)
    else { return }
    isFollowingTrackList = true
    defer { isFollowingTrackList = false }
    select(item: node)
  }

  private func select(item: Any?) {
    let row = outlineView.row(forItem: item)
    guard row >= 0 else { return }
    outlineView.selectRowIndexes([row], byExtendingSelection: false)
    outlineView.scrollRowToVisible(row)
  }

  /// Lists the selected folder's contents afresh.
  func reloadSelection() {
    guard let node = selectedItem as? FileNode else { return }
    let folder = node.isDirectory ? node : node.parent
    folder?.reload()
    outlineView.reloadItem(folder, reloadChildren: true)
  }

  /// The node of `url`, with the folders it's in expanded.
  private func revealedNode(for url: URL) -> FileNode? {
    let url = url.standardizedFileURL
    guard var node = roots.first(where: { $0.url == sources.folder(containing: url) }) else {
      return nil
    }
    while node.url != url {
      outlineView.expandItem(node)
      guard
        let child = node.children.first(where: {
          url.path.hasPrefix($0.url.path + "/") || $0.url == url
        })
      else { return nil }
      node = child
    }
    return node
  }

  /// The node of `url`, where the folders it's in have been listed.
  private func listedNode(for url: URL) -> FileNode? {
    let url = url.standardizedFileURL
    guard
      var node = roots.first(where: {
        url.path == $0.url.path || url.path.hasPrefix($0.url.path + "/")
      })
    else { return nil }
    while node.url != url {
      guard
        let child = node.listedChildren?.first(where: {
          url.path.hasPrefix($0.url.path + "/") || $0.url == url
        })
      else { return nil }
      node = child
    }
    return node
  }

  private func reloadRoots() {
    let selected = selectedItem
    let existing = Dictionary(roots.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
    roots = sources.folders.map { entry in
      entry.isAvailable
        ? existing[entry.url] ?? FileNode(url: entry.url, isDirectory: true)
        : FileNode(url: entry.url, isDirectory: true, isAvailable: false)
    }
    outlineView.reloadData()
    for section in Section.allCases { outlineView.expandItem(section.rawValue) }
    switch selected {
    case let node as FileNode: reveal(node.url)
    case let item as SourceItem: select(item.source)
    default: break
    }
    if outlineView.selectedRow < 0 { select(.allFiles) }
  }

  @objc private func sourcesDidChange() {
    reloadRoots()
  }

  /// Lists afresh the folders whose contents changed, and selects what was selected where it
  /// is now.
  @objc private func filesDidChange(_ notification: Notification) {
    let folders = notification.userInfo?[FileOperations.foldersKey] as? Set<URL> ?? []
    let moves = notification.userInfo?[FileOperations.movesKey] as? [URL: URL] ?? [:]
    let selected = (selectedItem as? FileNode)?.url
    for folder in folders {
      guard let node = listedNode(for: folder) else { continue }
      node.reload()
      outlineView.reloadItem(node, reloadChildren: true)
    }
    guard let selected else { return }
    // Where the item selected, or a folder it's in, moved, it's selected where it is now.
    if let (from, to) = moves.first(where: {
      selected.path == $0.key.path || selected.path.hasPrefix($0.key.path + "/")
    }) {
      reveal(URL(filePath: to.path + selected.path.dropFirst(from.path.count)))
    } else if outlineView.row(forItem: listedNode(for: selected)) < 0 {
      // Gone, it's the folder it was in that's selected.
      reveal(selected.deletingLastPathComponent())
    }
  }

  // MARK: Thumbnails and counts

  @objc private func tracksDidChange(_ notification: Notification) {
    let row = outlineView.row(forItem: editedItem)
    if row >= 0,
      let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? SourceCell
    {
      cell.badge = library.modifiedTracks.count
    }
    // Their artwork may have been edited.
    let changed = Set((notification.userInfo?[Library.tracksKey] as? [Track] ?? []).map(\.url))
    refreshVisibleFiles { changed.contains($0) }
  }

  @objc private func thumbnailDidMake(_ notification: Notification) {
    guard let track = notification.userInfo?[ArtworkThumbnails.trackKey] as? Track else { return }
    refreshVisibleFiles { $0 == track.url }
  }

  /// Shows the icons of the files shown that `matches`, as they are now.
  private func refreshVisibleFiles(where matches: (URL) -> Bool) {
    let rows = outlineView.rows(in: outlineView.visibleRect)
    for row in rows.lowerBound..<rows.upperBound {
      guard let node = outlineView.item(atRow: row) as? FileNode, !node.isDirectory,
        matches(node.url),
        let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? FileCell
      else { continue }
      configure(cell, for: node)
    }
  }

  private func configure(_ cell: FileCell, for node: FileNode) {
    if cell.textField?.currentEditor() == nil {
      cell.textField?.stringValue =
        node.isRoot
        ? FileManager.default.displayName(atPath: node.url.path) : node.url.lastPathComponent
    }
    cell.textField?.isEditable = !node.isRoot && node.isAvailable
    cell.textField?.delegate = self
    cell.toolTip =
      node.isAvailable
      ? node.url.path
      : "AudioTag can’t reach “\(node.url.path)”. Remove it, and add it again if it was moved."
    if node.isDirectory {
      cell.setIcon(thumbnail: nil, symbol: node.isAvailable ? "folder" : "exclamationmark.triangle")
    } else {
      cell.setIcon(
        thumbnail: thumbnails.image(for: library.track(for: node.url)),
        symbol: node.isVideo ? "film" : "music.note")
    }
  }

  // MARK: Managing files

  /// The nodes a command acts on: the row clicked, or else the one selected.
  private var targetNode: FileNode? {
    let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
    return outlineView.item(atRow: row) as? FileNode
  }

  /// Begins renaming the file or folder selected, as Return does; returns whether it could.
  @discardableResult
  private func renameSelection() -> Bool {
    guard let node = selectedItem as? FileNode, !node.isRoot, node.isAvailable else { return false }
    let row = outlineView.row(forItem: node)
    outlineView.editColumn(0, row: row, with: nil, select: true)
    return true
  }

  @objc func renameItem(_ sender: Any?) {
    if let node = targetNode, outlineView.selectedRow != outlineView.row(forItem: node) {
      select(item: node)
    }
    renameSelection()
  }

  @objc func newFolder(_ sender: Any?) {
    let node = targetNode
    guard
      let folder = node.map({ $0.isDirectory ? $0.url : $0.url.deletingLastPathComponent() })
        ?? selectedFolder
    else { return }
    fileOperations.perform(in: view.window) {
      let made = try fileOperations.makeFolder(in: folder, undoManager: view.window?.undoManager)
      reveal(made)
      renameSelection()
    }
  }

  @objc func moveToTrash(_ sender: Any?) {
    guard let node = targetNode, !node.isRoot else { return }
    let window = view.window
    Task { await fileOperations.trash([node.url], from: window) }
  }

  @objc private func showInFinder(_ sender: Any?) {
    guard let node = targetNode else { return }
    NSWorkspace.shared.activateFileViewerSelecting([node.url])
  }

  @objc private func removeFolder(_ sender: Any?) {
    guard let node = targetNode, node.isRoot else { return }
    sources.remove(node.url)
  }
}

extension SidebarViewController: NSMenuItemValidation {
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    let node = targetNode
    switch menuItem.action {
    case #selector(renameItem(_:)), #selector(moveToTrash(_:)):
      return node.map { !$0.isRoot && $0.isAvailable } ?? false
    case #selector(newFolder(_:)):
      return node?.isAvailable ?? false
    default:
      return true
    }
  }
}

// MARK: Renaming

extension SidebarViewController: NSTextFieldDelegate {
  /// Selects a file's name but for its extension, as the Finder does.
  func controlTextDidBeginEditing(_ notification: Notification) {
    guard let textField = notification.object as? NSTextField,
      let editor = textField.currentEditor(),
      let node = outlineView.item(atRow: outlineView.row(for: textField)) as? FileNode,
      !node.isDirectory, !node.url.pathExtension.isEmpty
    else { return }
    let name = textField.stringValue as NSString
    editor.selectedRange = NSRange(location: 0, length: name.deletingPathExtension.utf16.count)
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    guard selector == #selector(NSResponder.cancelOperation(_:)),
      let textField = control as? NSTextField
    else { return false }
    let row = outlineView.row(for: textField)
    textField.abortEditing()
    if let node = outlineView.item(atRow: row) as? FileNode,
      let cell = textField.superview as? FileCell
    {
      configure(cell, for: node)
    }
    view.window?.makeFirstResponder(outlineView)
    return true
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    guard let textField = notification.object as? NSTextField,
      let node = outlineView.item(atRow: outlineView.row(for: textField)) as? FileNode,
      textField.stringValue != node.url.lastPathComponent
    else { return }
    let name = textField.stringValue
    // Shown as it was, until it's renamed, which lists the folder afresh.
    textField.stringValue = node.url.lastPathComponent
    fileOperations.perform(in: view.window) {
      try fileOperations.rename(node.url, to: name, undoManager: view.window?.undoManager)
    }
  }
}

// MARK: Data source

extension SidebarViewController: NSOutlineViewDataSource {
  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    switch item {
    case nil: Section.allCases.count
    case let section as String:
      section == Section.library.rawValue ? sourceItems.count : roots.count
    case let node as FileNode: node.children.count
    default: 0
    }
  }

  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    switch item {
    case nil: Section.allCases[index].rawValue
    case let section as String:
      section == Section.library.rawValue ? sourceItems[index] : roots[index]
    case let node as FileNode: node.children[index]
    default: fatalError("No children of \(String(describing: item))")
    }
  }

  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    switch item {
    case is String: true
    case let node as FileNode: node.isDirectory && !node.children.isEmpty
    default: false
    }
  }

  func outlineView(_ outlineView: NSOutlineView, persistentObjectForItem item: Any?) -> Any? {
    switch item {
    case let section as String: section
    case let node as FileNode: node.url.path
    default: nil
    }
  }

  func outlineView(_ outlineView: NSOutlineView, itemForPersistentObject object: Any) -> Any? {
    guard let value = object as? String else { return nil }
    if let section = Section(rawValue: value) { return section.rawValue }
    let url = URL(filePath: value).standardizedFileURL
    guard var node = roots.first(where: { $0.url == sources.folder(containing: url) }) else {
      return nil
    }
    while node.url != url {
      guard
        let child = node.children.first(where: {
          url.path.hasPrefix($0.url.path + "/") || $0.url == url
        })
      else { return nil }
      node = child
    }
    return node
  }

  func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (
    any NSPasteboardWriting
  )? {
    (item as? FileNode)?.url as NSURL?
  }

  /// Files and folders dragged from the sidebar, or the track list, are moved into the folder
  /// they're dropped on, or the one the file they're dropped on is in; folders dragged from
  /// elsewhere, as from the Finder, are added to the sidebar.
  func outlineView(
    _ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?,
    proposedChildIndex index: Int
  ) -> NSDragOperation {
    let urls = Self.fileURLs(on: info.draggingPasteboard)
    guard !urls.isEmpty else { return [] }
    if isFromThisWindow(info) {
      guard let folder = dropFolder(for: item), canMove(urls, into: folder) else { return [] }
      outlineView.setDropItem(folder, dropChildIndex: NSOutlineViewDropOnItemIndex)
      return .move
    }
    guard urls.contains(where: Self.isDirectory) else { return [] }
    outlineView.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)
    return .link
  }

  func outlineView(
    _ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?,
    childIndex index: Int
  ) -> Bool {
    let urls = Self.fileURLs(on: info.draggingPasteboard)
    if isFromThisWindow(info) {
      guard let folder = dropFolder(for: item) else { return false }
      fileOperations.perform(in: view.window) {
        try fileOperations.move(urls, into: folder.url, undoManager: view.window?.undoManager)
      }
      return true
    }
    let folders = urls.filter(Self.isDirectory)
    sources.add(folders)
    if let first = folders.first { reveal(first) }
    return !folders.isEmpty
  }

  private func isFromThisWindow(_ info: any NSDraggingInfo) -> Bool {
    (info.draggingSource as? NSView)?.window === view.window
  }

  /// The folder what's dropped on `item` goes in: the folder, or the one the file is in.
  private func dropFolder(for item: Any?) -> FileNode? {
    guard let node = item as? FileNode, node.isAvailable else { return nil }
    return node.isDirectory ? node : node.parent
  }

  /// Whether the files and folders can be moved into `folder`: none is a folder of the
  /// sidebar's own, none is the folder or a folder it's in, and not all are in it already.
  private func canMove(_ urls: [URL], into folder: FileNode) -> Bool {
    let rootPaths = Set(roots.map(\.url.path))
    let folderPath = folder.url.path
    return
      urls.allSatisfy { url in
        let path = url.standardizedFileURL.path
        return !rootPaths.contains(path) && folderPath != path && !folderPath.hasPrefix(path + "/")
      }
      && urls.contains { $0.deletingLastPathComponent().standardizedFileURL.path != folderPath }
  }

  private static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
    let urls = pasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    return (urls as? [URL] ?? []).map(\.standardizedFileURL)
  }

  private static func isDirectory(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
  }
}

// MARK: Delegate

extension SidebarViewController: NSOutlineViewDelegate {
  func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
    item is String
  }

  func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
    !(item is String)
  }

  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any)
    -> NSView?
  {
    switch item {
    case let section as String:
      let identifier = NSUserInterfaceItemIdentifier("Header")
      let cell =
        outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
        ?? {
          let cell = NSTableCellView()
          cell.identifier = identifier
          let textField = NSTextField(labelWithString: "")
          textField.translatesAutoresizingMaskIntoConstraints = false
          cell.addSubview(textField)
          cell.textField = textField
          NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
          ])
          return cell
        }()
      cell.textField?.stringValue = section
      return cell
    case let node as FileNode:
      let identifier = NSUserInterfaceItemIdentifier("File")
      let cell =
        outlineView.makeView(withIdentifier: identifier, owner: nil) as? FileCell
        ?? FileCell(identifier: identifier)
      configure(cell, for: node)
      return cell
    case let item as SourceItem:
      let identifier = NSUserInterfaceItemIdentifier("Source")
      let cell =
        outlineView.makeView(withIdentifier: identifier, owner: nil) as? SourceCell
        ?? SourceCell(identifier: identifier)
      cell.textField?.stringValue = item.source.title
      switch item.source {
      case .allFiles:
        cell.imageView?.image = NSImage(
          systemSymbolName: "music.note.list", accessibilityDescription: nil)
        cell.badge = 0
      case .edited:
        cell.imageView?.image = NSImage(
          systemSymbolName: "square.and.pencil", accessibilityDescription: nil)
        cell.badge = library.modifiedTracks.count
      case .openedFiles:
        cell.imageView?.image = NSImage(
          systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        cell.badge = sources.files.count
      case .folder:
        cell.badge = 0
      }
      return cell
    default:
      return nil
    }
  }

  func outlineViewSelectionDidChange(_ notification: Notification) {
    guard !isFollowingTrackList else { return }
    let selected: String? =
      switch selectedItem {
      case let item as SourceItem:
        switch item.source {
        case .allFiles: "allFiles"
        case .edited: "edited"
        case .openedFiles: "openedFiles"
        case .folder(let url): url.path
        }
      case let node as FileNode: node.url.path
      default: nil
      }
    UserDefaults.standard.set(selected, forKey: Self.selectionKey)
    let node = selectedItem as? FileNode
    onSelect?(selectedSource, node.flatMap { $0.isDirectory ? nil : $0.url })
  }
}

// MARK: Contextual menu

extension SidebarViewController: NSMenuDelegate {
  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    guard let node = outlineView.item(atRow: outlineView.clickedRow) as? FileNode else { return }
    func add(_ title: String, _ action: Selector) {
      menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
    }
    add("Show in Finder", #selector(showInFinder(_:)))
    guard node.isAvailable else {
      menu.addItem(.separator())
      add("Remove from Sidebar", #selector(removeFolder(_:)))
      return
    }
    if node.isDirectory { add("New Folder", #selector(newFolder(_:))) }
    if !node.isRoot { add("Rename", #selector(renameItem(_:))) }
    menu.addItem(.separator())
    if node.isRoot {
      add("Remove from Sidebar", #selector(removeFolder(_:)))
    } else {
      add("Move to Trash", #selector(moveToTrash(_:)))
    }
  }
}
