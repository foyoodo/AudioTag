//
//  TrackListViewController.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit

/// The audio files of the source selected, in a table whose tag columns can be edited.
final class TrackListViewController: NSViewController {
  private let library: Library
  private let sources: Sources
  private let fileOperations: FileOperations
  private let tableView = NSTableView()
  private let emptyState = EmptyStateView(
    symbolName: "folder.badge.plus", title: "",
    button: NSButton(
      title: "Add Folder…", target: nil, action: #selector(AppDelegate.openDocument(_:))))

  private(set) var source: TrackSource?
  /// Every track of the source, by path.
  private var tracks: [Track] = []
  /// The tracks shown: those the filter matches, sorted.
  private var rows: [Track] = []
  private var rowsByTrack: [Track: Int] = [:]
  private var loadTask: Task<Void, Never>?
  private var readCount: Int?
  /// Files to select once the source's tracks are listed.
  private var pendingSelection: [URL] = []

  /// Told of the tracks selected.
  var onSelectionChange: (([Track]) -> Void)?
  /// Told of the status line to show, whenever it changes.
  var onStatusChange: ((String) -> Void)?
  /// Told of files dropped onto the list.
  var onOpen: (([URL]) -> Void)?

  /// Shows only the tracks whose name, title, artist or album contains it.
  var filter = "" {
    didSet { updateRows(animated: true) }
  }

  init(library: Library, sources: Sources, fileOperations: FileOperations) {
    self.library = library
    self.sources = sources
    self.fileOperations = fileOperations
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  var selectedTracks: [Track] {
    tableView.selectedRowIndexes.map { rows[$0] }
  }

  override func loadView() {
    for column in TrackColumn.allCases {
      let tableColumn = NSTableColumn(identifier: column.identifier)
      tableColumn.title = column.title
      tableColumn.width = column.width
      tableColumn.headerCell.alignment = column.alignment
      tableColumn.isHidden = column.isHiddenByDefault
      if column == .status {
        tableColumn.resizingMask = []
        tableColumn.headerToolTip = "Edited"
      } else {
        tableColumn.minWidth = 40
        tableColumn.sortDescriptorPrototype = NSSortDescriptor(
          key: column.rawValue, ascending: true)
      }
      tableView.addTableColumn(tableColumn)
    }
    tableView.style = .fullWidth
    tableView.rowSizeStyle = .custom
    tableView.rowHeight = 24
    tableView.intercellSpacing = NSSize(width: 8, height: 0)
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.allowsMultipleSelection = true
    tableView.allowsColumnReordering = true
    tableView.columnAutoresizingStyle = .noColumnAutoresizing
    tableView.dataSource = self
    tableView.delegate = self
    tableView.autosaveName = "Tracks"
    tableView.autosaveTableColumns = true
    tableView.registerForDraggedTypes([.fileURL])
    tableView.setDraggingSourceOperationMask(.copy, forLocal: false)

    let headerMenu = NSMenu()
    headerMenu.delegate = self
    tableView.headerView?.menu = headerMenu

    let rowMenu = NSMenu()
    rowMenu.delegate = self
    tableView.menu = rowMenu

    let scrollView = NSScrollView()
    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true

    emptyState.isHidden = true
    let container = NSView()
    for subview in [scrollView, emptyState] {
      subview.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(subview)
    }
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: container.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      emptyState.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      emptyState.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      emptyState.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
      emptyState.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -40),
    ])
    view = container
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    NotificationCenter.default.addObserver(
      self, selector: #selector(tracksDidChange(_:)), name: Library.tracksDidChangeNotification,
      object: library)
    NotificationCenter.default.addObserver(
      self, selector: #selector(sourcesDidChange), name: Sources.didChangeNotification,
      object: sources)
    updateEmptyState()
  }

  /// Shows the rows' tracks as they are now, in the views the rows have, which reloading them
  /// would make anew, ending the editing of a cell in them, as of one just moved to.
  private func refresh(rows indexes: IndexSet, columns: IndexSet? = nil) {
    let columns = columns ?? IndexSet(integersIn: 0..<tableView.numberOfColumns)
    for row in indexes where rows.indices.contains(row) {
      for column in columns {
        guard
          let view = tableView.view(atColumn: column, row: row, makeIfNecessary: false),
          let trackColumn = TrackColumn(
            rawValue: tableView.tableColumns[column].identifier.rawValue)
        else { continue }
        configure(view, for: trackColumn, track: rows[row])
      }
    }
  }

  // MARK: Showing

  /// Lists the source's audio files, and reads them.
  func show(_ source: TrackSource?, reloading: Bool = false) {
    guard source != self.source || reloading else { return }
    self.source = source
    loadTask?.cancel()
    pendingSelection = []
    if !reloading {
      tracks = []
      updateRows()
    }
    guard let source else {
      readCount = nil
      updateStatus()
      return
    }
    readCount = 0
    updateStatus()
    loadTask = Task {
      let listed = await tracks(of: source)
      guard !Task.isCancelled else { return }
      tracks = listed
      updateRows()
      selectPendingFiles()
      await library.read(listed) { count in
        self.readCount = count
        self.updateStatus()
      }
      guard !Task.isCancelled else { return }
      readCount = nil
      // Sorted by tags, the rows can now be put in order.
      updateRows()
    }
  }

  private func tracks(of source: TrackSource) async -> [Track] {
    switch source {
    case .edited:
      return library.modifiedTracks
    case .openedFiles:
      return sources.files.filter(\.isAvailable).map { library.track(for: $0.url) }
    case .folder(let url):
      return sources.folder(containing: url) == nil ? [] : await library.tracks(in: url)
    case .allFiles:
      var tracks = sources.files.filter(\.isAvailable).map { library.track(for: $0.url) }
      for folder in sources.folders where folder.isAvailable {
        tracks += await library.tracks(in: folder.url)
      }
      var seen = Set<Track>()
      return
        tracks
        .filter { seen.insert($0).inserted }
        .sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }
  }

  @objc private func sourcesDidChange() {
    if source == .allFiles || source == .openedFiles { show(source, reloading: true) }
  }

  /// Selects the tracks of these files, once they're listed.
  func select(_ files: [URL]) {
    pendingSelection = files.map(\.standardizedFileURL)
    if loadTask == nil || !tracks.isEmpty { selectPendingFiles() }
  }

  private func selectPendingFiles() {
    guard !pendingSelection.isEmpty else { return }
    let files = Set(pendingSelection)
    pendingSelection = []
    let indexes = IndexSet(rows.indices.filter { files.contains(rows[$0].url) })
    guard let first = indexes.first else { return }
    tableView.selectRowIndexes(indexes, byExtendingSelection: false)
    tableView.scrollRowToVisible(first)
    view.window?.makeFirstResponder(tableView)
  }

  /// Filters and sorts the tracks into the rows shown; `animated`, rows that come or go do so
  /// with a fade, if the others stay in the order they were.
  private func updateRows(animated: Bool = false) {
    let selected = Set(selectedTracks)
    let filter = filter.trimmingCharacters(in: .whitespaces)
    var rows =
      filter.isEmpty
      ? tracks
      : tracks.filter { track in
        [TrackColumn.name, .title, .artist, .album, .albumArtist].contains {
          $0.text(for: track).localizedStandardContains(filter)
        }
      }
    for descriptor in tableView.sortDescriptors.reversed() {
      guard let key = descriptor.key, let column = TrackColumn(rawValue: key) else { continue }
      let order: ComparisonResult = descriptor.ascending ? .orderedAscending : .orderedDescending
      rows = rows.enumerated()
        .sorted { lhs, rhs in
          let result = column.compare(lhs.element, rhs.element)
          return result == .orderedSame ? lhs.offset < rhs.offset : result == order
        }
        .map(\.element)
    }
    let oldRows = self.rows
    self.rows = rows
    rowsByTrack = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1, $0) })
    let difference = rows.difference(from: oldRows)
    if animated, !Motion.isReduced, !oldRows.isEmpty, !rows.isEmpty, difference.count <= 200 {
      var removals = IndexSet()
      var insertions = IndexSet()
      for change in difference {
        switch change {
        case .remove(let offset, _, _): removals.insert(offset)
        case .insert(let offset, _, _): insertions.insert(offset)
        }
      }
      tableView.beginUpdates()
      tableView.removeRows(at: removals, withAnimation: .effectFade)
      tableView.insertRows(at: insertions, withAnimation: .effectFade)
      tableView.endUpdates()
    } else {
      tableView.reloadData()
    }
    tableView.selectRowIndexes(
      IndexSet(rows.indices.filter { selected.contains(rows[$0]) }), byExtendingSelection: false)
    updateEmptyState()
    updateStatus()
  }

  /// Shows why the list is empty, where it is, fading in and out.
  private func updateEmptyState() {
    let hasSources = !sources.entries.isEmpty
    let state: (symbol: String, title: String, message: String)? =
      if !rows.isEmpty || (readCount != nil && tracks.isEmpty && hasSources) {
        nil
      } else if !hasSources {
        (
          "folder.badge.plus", "No Folders",
          "Add a folder of audio files, or drop files here, to edit their tags."
        )
      } else if !filter.isEmpty {
        ("magnifyingglass", "No Matches", "No file’s name, title, artist or album has “\(filter)”.")
      } else if source == .edited {
        ("checkmark.circle", "No Edited Files", "The files you edit are listed here until saved.")
      } else if case .folder(let url) = source, sources.folder(containing: url) == nil {
        (
          "exclamationmark.triangle", "Folder Unavailable",
          "AudioTag can’t reach this folder. Remove it, and add it again if it was moved."
        )
      } else {
        ("music.note.list", "No Audio Files", "")
      }
    if let state {
      emptyState.set(symbolName: state.symbol, title: state.title, message: state.message)
    }
    emptyState.arrangedSubviews.last?.isHidden = hasSources
    let isShown = state != nil
    guard isShown == emptyState.isHidden else { return }
    if isShown {
      emptyState.alphaValue = 0
      emptyState.isHidden = false
    }
    Motion.animate(duration: 0.2) {
      emptyState.animator().alphaValue = isShown ? 1 : 0
    } completion: { [emptyState] in
      if emptyState.alphaValue == 0 { emptyState.isHidden = true }
    }
  }

  private func updateStatus() {
    let status: String
    if let readCount, readCount < tracks.count {
      status = "Reading \(readCount.formatted()) of \(tracks.count.formatted()) files…"
    } else if source == nil {
      status = ""
    } else {
      let edited = tracks.count(where: \.isModified)
      let files = tracks.count == 1 ? "1 file" : "\(tracks.count.formatted()) files"
      let shown = rows.count == tracks.count ? files : "\(rows.count.formatted()) of \(files)"
      status = edited > 0 ? "\(shown), \(edited.formatted()) edited" : shown
    }
    onStatusChange?(status)
  }

  @objc private func tracksDidChange(_ notification: Notification) {
    guard let changed = notification.userInfo?[Library.tracksKey] as? [Track] else { return }
    if source == .edited {
      updateEditedTracks(changed)
    }
    let indexes = IndexSet(changed.compactMap { rowsByTrack[$0] })
    guard !indexes.isEmpty else { return }
    refresh(rows: indexes)
    updateStatus()
    if !tableView.selectedRowIndexes.isDisjoint(with: indexes) {
      onSelectionChange?(selectedTracks)
    }
  }

  /// Lists the tracks newly edited, and leaves out those no longer edited, unless they're
  /// selected, which would change the selection from under the user.
  private func updateEditedTracks(_ changed: [Track]) {
    let selected = Set(selectedTracks)
    let listed = Set(tracks)
    let added = changed.filter { $0.isModified && !listed.contains($0) }
    let removed = Set(changed.filter { !$0.isModified && !selected.contains($0) })
    guard !added.isEmpty || !removed.isEmpty else { return }
    tracks = (tracks.filter { !removed.contains($0) } + added)
      .sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    updateRows(animated: true)
  }

  // MARK: Actions

  /// The tracks a contextual menu's command acts on: the row clicked, or the selection where
  /// it's in it.
  private var clickedTracks: [Track] {
    let row = tableView.clickedRow
    guard row >= 0 else { return selectedTracks }
    return tableView.selectedRowIndexes.contains(row) ? selectedTracks : [rows[row]]
  }

  @objc private func saveClicked(_ sender: Any?) {
    let tracks = clickedTracks
    Task { await (view.window?.windowController as? MainWindowController)?.save(tracks) }
  }

  @objc private func revertClicked(_ sender: Any?) {
    library.revert(clickedTracks)
  }

  /// Moves the files of the tracks selected, or clicked, to the Trash.
  @objc func moveToTrash(_ sender: Any?) {
    let urls = clickedTracks.map(\.url)
    let window = view.window
    Task { await fileOperations.trash(urls, from: window) }
  }

  @objc private func showInFinder(_ sender: Any?) {
    NSWorkspace.shared.activateFileViewerSelecting(clickedTracks.map(\.url))
  }

  @objc private func toggleColumn(_ sender: NSMenuItem) {
    guard let column = sender.representedObject as? NSTableColumn else { return }
    column.isHidden.toggle()
  }
}

// MARK: Editing in the list

/// Editing a cell moves on as a spreadsheet does: Return applies it and edits the same field of
/// the next row, Shift-Return of the one before; Tab and Shift-Tab, the next field and the one
/// before, in the order the columns are shown, on into the next row and the one before. Escape
/// discards it. Rows that can't be edited are passed over.
extension TrackListViewController: NSTextFieldDelegate {
  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    guard let textField = control as? NSTextField else { return false }
    let row = tableView.row(for: textField)
    let column = tableView.column(for: textField)
    guard row >= 0, column >= 0 else { return false }
    let isShifted = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
    let move: (rows: Int, fields: Int)
    switch selector {
    case #selector(NSResponder.insertNewline(_:)): move = (isShifted ? -1 : 1, 0)
    case #selector(NSResponder.insertTab(_:)): move = (0, 1)
    case #selector(NSResponder.insertBacktab(_:)): move = (0, -1)
    case #selector(NSResponder.cancelOperation(_:)):
      textField.abortEditing()
      tableView.reloadData(forRowIndexes: [row], columnIndexes: [column])
      view.window?.makeFirstResponder(tableView)
      return true
    default:
      return false
    }
    // Once the field editor is done with the key, the edit ends, which applies it, and the
    // next field's begins.
    DispatchQueue.main.async { [self] in
      view.window?.makeFirstResponder(tableView)
      beginEditing(from: (row, column), moving: move)
    }
    return true
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    guard let textField = notification.object as? NSTextField else { return }
    apply(textField)
  }

  /// Gives the cell's track the text of its field, where it was changed.
  private func apply(_ textField: NSTextField) {
    let row = tableView.row(for: textField)
    let column = tableView.column(for: textField)
    guard row >= 0, column >= 0,
      let trackColumn = TrackColumn(rawValue: tableView.tableColumns[column].identifier.rawValue),
      let editing = trackColumn.editing
    else { return }
    let track = rows[row]
    let text = textField.stringValue
    // As shown, rather than as stored, which a field's text may differ from, its line breaks
    // shown as spaces.
    guard text != trackColumn.text(for: track) else { return }
    // A date is written as `TagDate` has it; text that's no date, not at all.
    var written = text
    if case .field(let field) = editing {
      guard let date = field.normalized(text) else {
        NSSound.beep()
        textField.stringValue = trackColumn.text(for: track)
        return
      }
      written = date
    }
    library.edit([track]) { [written] track in
      switch editing {
      case .field(let field): field.set(written, in: &track.tags)
      case .position(let position): position.set(written, in: &track.tags)
      }
    }
  }

  /// Selects, and edits, the field `move` leads to from `cell`: a row's, which keeps the
  /// column, or another field's, which may be in the row next to it. Where there's none, the
  /// edit just ends.
  private func beginEditing(
    from cell: (row: Int, column: Int), moving move: (rows: Int, fields: Int)
  ) {
    let navigation = CellNavigation(
      editableColumns: tableView.tableColumns.indices.filter { index in
        let tableColumn = tableView.tableColumns[index]
        return !tableColumn.isHidden
          && TrackColumn(rawValue: tableColumn.identifier.rawValue)?.editing != nil
      },
      rowCount: rows.count, isEditable: { [rows] in rows[$0].isEditable })
    guard
      let next = navigation.cell(
        from: .init(row: cell.row, column: cell.column), rows: move.rows, fields: move.fields)
    else { return }
    let (row, column) = (next.row, next.column)
    tableView.selectRowIndexes([row], byExtendingSelection: false)
    tableView.scrollRowToVisible(row)
    tableView.scrollColumnToVisible(column)
    tableView.editColumn(column, row: row, with: nil, select: true)
  }
}

extension TrackListViewController: NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    rows.count
  }

  func tableView(
    _ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
  ) {
    updateRows()
  }

  func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (
    any NSPasteboardWriting
  )? {
    rows[row].url as NSURL
  }

  func tableView(
    _ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
    proposedDropOperation dropOperation: NSTableView.DropOperation
  ) -> NSDragOperation {
    guard info.draggingSource as? NSTableView !== tableView,
      info.draggingPasteboard.canReadObject(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    else { return [] }
    tableView.setDropRow(-1, dropOperation: .on)
    return .copy
  }

  func tableView(
    _ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
    dropOperation: NSTableView.DropOperation
  ) -> Bool {
    let urls = info.draggingPasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    guard let urls = urls as? [URL], !urls.isEmpty else { return false }
    onOpen?(urls)
    return true
  }
}

extension TrackListViewController: NSTableViewDelegate {
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard let tableColumn, let column = TrackColumn(rawValue: tableColumn.identifier.rawValue)
    else { return nil }
    let view: NSView =
      tableView.makeView(withIdentifier: column.identifier, owner: nil)
      ?? {
        switch column {
        case .status: makeStatusView()
        default: makeTextCell(for: column)
        }
      }()
    configure(view, for: column, track: rows[row])
    return view
  }

  /// Shows the track in a cell's view, but for the text of a field that's being edited.
  private func configure(_ view: NSView, for column: TrackColumn, track: Track) {
    switch (column, view) {
    case (.status, let imageView as NSImageView):
      configureStatus(imageView, for: track)
    case (_, let cell as NSTableCellView):
      guard let textField = cell.textField else { return }
      if textField.currentEditor() == nil {
        textField.stringValue = column.text(for: track)
      }
      // An untitled track goes by its file's name, dimmed, which isn't its title, to be edited
      // as though it were.
      textField.placeholderString = column == .title ? track.name : nil
      textField.textColor = column.isSecondary ? .secondaryLabelColor : .labelColor
      textField.isEditable = column.editing != nil && track.isEditable
    default:
      break
    }
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    onSelectionChange?(selectedTracks)
  }

  private func makeTextCell(for column: TrackColumn) -> NSTableCellView {
    let cell = NSTableCellView()
    cell.identifier = column.identifier
    let textField = NSTextField(labelWithString: "")
    textField.lineBreakMode = .byTruncatingTail
    textField.alignment = column.alignment
    textField.translatesAutoresizingMaskIntoConstraints = false
    if column.alignment == .right {
      textField.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }
    if column.editing != nil {
      textField.delegate = self
      textField.makeEditableInPlace()
    }
    cell.addSubview(textField)
    cell.textField = textField
    NSLayoutConstraint.activate([
      textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
      textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
      textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }

  private func makeStatusView() -> NSImageView {
    let imageView = NSImageView()
    imageView.identifier = TrackColumn.status.identifier
    imageView.symbolConfiguration = .init(pointSize: 8, weight: .regular)
    return imageView
  }

  private func configureStatus(_ imageView: NSImageView, for track: Track) {
    if let error = track.readError {
      imageView.image = NSImage(
        systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Unreadable")
      imageView.symbolConfiguration = .init(pointSize: 11, weight: .regular)
      imageView.contentTintColor = .systemYellow
      imageView.toolTip = error.message
    } else if track.isRead && !track.isWritable {
      imageView.image = NSImage(
        systemSymbolName: "lock.fill", accessibilityDescription: "Read Only")
      imageView.symbolConfiguration = .init(pointSize: 9, weight: .regular)
      imageView.contentTintColor = .secondaryLabelColor
      imageView.toolTip = "The file is read-only, so its tags can’t be changed."
    } else if track.isModified {
      imageView.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Edited")
      imageView.symbolConfiguration = .init(pointSize: 7, weight: .regular)
      imageView.contentTintColor = .controlAccentColor
      imageView.toolTip = "Edited"
    } else {
      imageView.image = nil
      imageView.toolTip = nil
    }
  }
}

extension TrackListViewController: NSMenuDelegate {
  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    if menu === tableView.headerView?.menu {
      for tableColumn in tableView.tableColumns {
        guard let column = TrackColumn(rawValue: tableColumn.identifier.rawValue), column != .name
        else { continue }
        let item = menu.addItem(
          withTitle: column.menuTitle, action: #selector(toggleColumn(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = tableColumn
        item.state = tableColumn.isHidden ? .off : .on
      }
      return
    }
    let tracks = clickedTracks
    guard !tracks.isEmpty else { return }
    let edited = tracks.contains { $0.isModified }
    let save = menu.addItem(
      withTitle: "Save", action: edited ? #selector(saveClicked(_:)) : nil, keyEquivalent: "")
    save.target = self
    let revert = menu.addItem(
      withTitle: "Revert Changes", action: edited ? #selector(revertClicked(_:)) : nil,
      keyEquivalent: "")
    revert.target = self
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Show in Finder", action: #selector(showInFinder(_:)), keyEquivalent: ""
    ).target = self
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Move to Trash", action: #selector(moveToTrash(_:)), keyEquivalent: ""
    ).target = self
  }
}

extension TrackListViewController: NSMenuItemValidation {
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(moveToTrash(_:)): !clickedTracks.isEmpty
    default: true
    }
  }
}
