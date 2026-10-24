//
//  MetadataLookupViewController.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2026.
//

import AppKit
import TagLib
import UniformTypeIdentifiers

/// A sheet that searches MusicBrainz (and iTunes, if need be) for a track’s tags, lets the user
/// pick a recording, and applies the chosen fields in memory so File › Save writes them.
final class MetadataLookupViewController: NSViewController {
  private let track: Track
  private let library: Library
  private let service: MetadataLookupService

  private let titleField = NSTextField(string: "")
  private let artistField = NSTextField(string: "")
  private let albumField = NSTextField(string: "")
  private let searchButton = NSButton(title: "Search", target: nil, action: nil)
  private let spinner = NSProgressIndicator()
  private let tableView = NSTableView()
  private let emptyState = EmptyStateView(
    symbolName: "magnifyingglass", title: "Search for this track")
  private let statusLabel = NSTextField(labelWithString: "")
  private let artworkView = NSImageView()
  private let previewStack = NSStackView()
  private let previewPlaceholder = NSTextField(
    wrappingLabelWithString: "Pick a recording to preview the tags it would apply.")
  private let artworkCheckbox = NSButton(
    checkboxWithTitle: "Artwork", target: nil, action: nil)
  private let applyButton = NSButton(title: "Apply", target: nil, action: nil)
  private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
  private let noteLabel = NSTextField(
    wrappingLabelWithString: "Nothing is written to the file until you save.")

  private var query: MetadataQuery
  private var candidates: [MetadataCandidate] = []
  private var thumbnails: [String: NSImage] = [:]
  private var selectedArtwork: Data?
  private var fieldChecks: [MetadataField: NSButton] = [:]
  private var searchTask: Task<Void, Never>?
  private var coverTask: Task<Void, Never>?
  private var applyTask: Task<Void, Never>?

  var onFinish: (() -> Void)?

  init(track: Track, library: Library, service: MetadataLookupService = MetadataLookupService()) {
    self.track = track
    self.library = library
    self.service = service
    self.query = MetadataQuery.prefill(for: track)
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    titleField.placeholderString = "Title"
    artistField.placeholderString = "Artist"
    albumField.placeholderString = "Album"
    for field in [titleField, artistField, albumField] {
      field.delegate = self
      field.lineBreakMode = .byTruncatingTail
      field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    searchButton.target = self
    searchButton.action = #selector(searchClicked(_:))
    searchButton.keyEquivalent = "\r"
    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.isDisplayedWhenStopped = false

    let queryGrid = InspectorGrid.make()
    queryGrid.addRow(with: [InspectorGrid.label("Title"), titleField])
    let artistAlbum = NSStackView(views: [artistField, albumField])
    artistAlbum.spacing = 8
    artistAlbum.distribution = .fillEqually
    queryGrid.addRow(with: [InspectorGrid.label("Artist / Album"), artistAlbum])
    InspectorGrid.alignLabels(of: queryGrid)
    let searchRow = NSStackView(views: [spinner, searchButton])
    searchRow.alignment = .centerY
    searchRow.spacing = 8
    let queryHeader = NSStackView(views: [queryGrid, searchRow])
    queryHeader.alignment = .top
    queryHeader.spacing = 12
    queryGrid.setContentHuggingPriority(.defaultLow, for: .horizontal)

    for column in LookupColumn.allCases {
      let tableColumn = NSTableColumn(identifier: column.identifier)
      tableColumn.title = column.title
      tableColumn.width = column.width
      tableColumn.minWidth = 28
      tableView.addTableColumn(tableColumn)
    }
    tableView.style = .fullWidth
    tableView.headerView = NSTableHeaderView()
    tableView.rowHeight = 32
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.allowsEmptySelection = true
    tableView.allowsMultipleSelection = false
    tableView.dataSource = self
    tableView.delegate = self
    let tableScroll = NSScrollView()
    tableScroll.documentView = tableView
    tableScroll.hasVerticalScroller = true
    tableScroll.borderType = .bezelBorder
    tableScroll.heightAnchor.constraint(equalToConstant: 220).isActive = true

    emptyState.translatesAutoresizingMaskIntoConstraints = false
    let tableContainer = NSView()
    tableScroll.translatesAutoresizingMaskIntoConstraints = false
    tableContainer.addSubview(tableScroll)
    tableContainer.addSubview(emptyState)
    NSLayoutConstraint.activate([
      tableScroll.topAnchor.constraint(equalTo: tableContainer.topAnchor),
      tableScroll.bottomAnchor.constraint(equalTo: tableContainer.bottomAnchor),
      tableScroll.leadingAnchor.constraint(equalTo: tableContainer.leadingAnchor),
      tableScroll.trailingAnchor.constraint(equalTo: tableContainer.trailingAnchor),
      emptyState.centerXAnchor.constraint(equalTo: tableContainer.centerXAnchor),
      emptyState.centerYAnchor.constraint(equalTo: tableContainer.centerYAnchor),
      emptyState.widthAnchor.constraint(
        lessThanOrEqualTo: tableContainer.widthAnchor, constant: -24),
    ])

    statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    statusLabel.textColor = .secondaryLabelColor

    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = 6
    artworkView.layer?.masksToBounds = true
    NSLayoutConstraint.activate([
      artworkView.widthAnchor.constraint(equalToConstant: 96),
      artworkView.heightAnchor.constraint(equalToConstant: 96),
    ])
    artworkCheckbox.target = self
    artworkCheckbox.action = #selector(previewToggled(_:))
    previewStack.orientation = .vertical
    previewStack.alignment = .leading
    previewStack.spacing = 6
    previewPlaceholder.textColor = .secondaryLabelColor
    previewPlaceholder.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    let previewFields = NSStackView(views: [previewStack, previewPlaceholder])
    previewFields.orientation = .vertical
    previewFields.alignment = .leading
    previewFields.spacing = 6
    let preview = NSStackView(views: [artworkView, previewFields])
    preview.alignment = .top
    preview.spacing = 12
    previewFields.setContentHuggingPriority(.defaultLow, for: .horizontal)

    noteLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    noteLabel.textColor = .tertiaryLabelColor
    applyButton.target = self
    applyButton.action = #selector(applyClicked(_:))
    applyButton.keyEquivalent = "\r"
    cancelButton.target = self
    cancelButton.action = #selector(cancelClicked(_:))
    cancelButton.keyEquivalent = "\u{1b}"
    let buttons = NSStackView(views: [noteLabel, NSView(), cancelButton, applyButton])
    buttons.alignment = .centerY
    buttons.spacing = 10
    noteLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let stack = NSStackView(views: [
      queryHeader, tableContainer, statusLabel, preview, artworkCheckbox, buttons,
    ])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    for view in [queryHeader, tableContainer, statusLabel, preview, buttons] {
      view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
    }
    stack.widthAnchor.constraint(equalToConstant: 740).isActive = true
    stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 560).isActive = true
    view = stack
    preferredContentSize = NSSize(width: 740, height: 620)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    titleField.stringValue = query.title
    artistField.stringValue = query.artist
    albumField.stringValue = query.album
    updatePreview(nil)
    emptyState.set(
      symbolName: "magnifyingglass", title: "Search for this track",
      message: "AudioTag looks up MusicBrainz, and iTunes if that has no match.")
    if !query.isEmpty { search() }
  }

  override func viewWillDisappear() {
    super.viewWillDisappear()
    searchTask?.cancel()
    coverTask?.cancel()
  }

  private func readQuery() -> MetadataQuery {
    MetadataQuery(
      title: titleField.stringValue, artist: artistField.stringValue,
      album: albumField.stringValue)
  }

  @objc private func searchClicked(_ sender: Any?) {
    search()
  }

  private func search() {
    query = readQuery()
    searchTask?.cancel()
    coverTask?.cancel()
    selectedArtwork = nil
    thumbnails = [:]
    candidates = []
    tableView.reloadData()
    updatePreview(nil)
    guard !query.isEmpty else {
      showEmpty(
        symbol: "magnifyingglass", title: "Enter a search",
        message: MetadataLookupError.emptyQuery.message)
      statusLabel.stringValue = ""
      return
    }
    spinner.startAnimation(nil)
    searchButton.isEnabled = false
    emptyState.isHidden = true
    statusLabel.stringValue = "Searching…"
    let query = query
    searchTask = Task { [weak self, service] in
      let result: Result<[MetadataCandidate], Error>
      do {
        result = .success(try await service.search(query))
      } catch {
        result = .failure(error)
      }
      guard !Task.isCancelled, let self else { return }
      switch result {
      case .success(let candidates):
        self.candidates = candidates
        tableView.reloadData()
        spinner.stopAnimation(nil)
        searchButton.isEnabled = true
        if candidates.isEmpty {
          showEmpty(
            symbol: "magnifyingglass", title: "No matching recordings",
            message: "Try a different title, artist or album.")
          statusLabel.stringValue = ""
        } else {
          emptyState.isHidden = true
          let sources = Set(candidates.map(\.source))
          let source =
            sources.count == 1
            ? candidates[0].source.name
            : sources.map(\.name).sorted().joined(separator: " and ")
          let noun = candidates.count == 1 ? "recording" : "recordings"
          statusLabel.stringValue =
            "\(candidates.count.formatted()) \(noun) from \(source)."
          tableView.selectRowIndexes([0], byExtendingSelection: false)
          loadThumbnails()
        }
      case .failure(let error):
        spinner.stopAnimation(nil)
        searchButton.isEnabled = true
        let message = (error as? MetadataLookupError)?.message ?? error.localizedDescription
        if (error as? MetadataLookupError) == .cancelled { return }
        showEmpty(symbol: "wifi.slash", title: "Lookup failed", message: message)
        statusLabel.stringValue = ""
      }
    }
  }

  private func showEmpty(symbol: String, title: String, message: String) {
    emptyState.set(symbolName: symbol, title: title, message: message)
    emptyState.isHidden = false
  }

  private func loadThumbnails() {
    coverTask?.cancel()
    let candidates = candidates
    let service = service
    coverTask = Task { [weak self] in
      guard let self else { return }
      await withTaskGroup(of: (String, Data?).self) { group in
        var next = 0
        func start() {
          let candidate = candidates[next]
          next += 1
          group.addTask {
            (
              candidate.id,
              try? await service.image(for: candidate, size: .thumbnail)
            )
          }
        }
        while next < min(candidates.count, 4) { start() }
        for await (id, data) in group {
          if let data, let image = NSImage(data: data) {
            thumbnails[id] = image
            if let row = self.candidates.firstIndex(where: { $0.id == id }) {
              tableView.reloadData(forRowIndexes: [row], columnIndexes: [0])
              if tableView.selectedRow == row, artworkView.image == nil {
                artworkView.image = image
              }
            }
          }
          if next < candidates.count, !Task.isCancelled { start() }
        }
      }
    }
  }

  private var selectedCandidate: MetadataCandidate? {
    let row = tableView.selectedRow
    guard candidates.indices.contains(row) else { return nil }
    return candidates[row]
  }

  private func updatePreview(_ candidate: MetadataCandidate?) {
    for view in previewStack.arrangedSubviews { view.removeFromSuperview() }
    fieldChecks = [:]
    guard let candidate else {
      previewPlaceholder.isHidden = false
      artworkView.image = nil
      artworkCheckbox.state = .off
      artworkCheckbox.isEnabled = false
      applyButton.isEnabled = false
      searchButton.keyEquivalent = "\r"
      applyButton.keyEquivalent = ""
      return
    }
    previewPlaceholder.isHidden = true
    artworkView.image = thumbnails[candidate.id]
    let hasCover = thumbnails[candidate.id] != nil || candidate.thumbnailURL != nil
    artworkCheckbox.isEnabled = hasCover
    artworkCheckbox.state = hasCover ? .on : .off
    let changes = MetadataLookup.changes(for: track, candidate: candidate)
    for change in changes {
      let checkbox = NSButton(
        checkboxWithTitle: change.field.label, target: self, action: #selector(previewToggled(_:)))
      checkbox.state = change.wouldChange ? .on : .off
      checkbox.identifier = .init(change.field.rawValue)
      fieldChecks[change.field] = checkbox
      let current = NSTextField(labelWithString: change.current.isEmpty ? "None" : change.current)
      current.textColor = change.current.isEmpty ? .tertiaryLabelColor : .secondaryLabelColor
      current.lineBreakMode = .byTruncatingTail
      current.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
      let arrow = NSTextField(labelWithString: "→")
      arrow.textColor = .tertiaryLabelColor
      let proposed = NSTextField(labelWithString: change.proposed)
      proposed.lineBreakMode = .byTruncatingTail
      proposed.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
      for field in [current, proposed] {
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      }
      checkbox.widthAnchor.constraint(equalToConstant: 120).isActive = true
      current.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
      let row = NSStackView(views: [checkbox, current, arrow, proposed])
      row.spacing = 8
      row.alignment = .centerY
      previewStack.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: previewStack.widthAnchor).isActive = true
    }
    searchButton.keyEquivalent = ""
    applyButton.keyEquivalent = "\r"
    updateApplyEnabled()
    loadSelectedArtwork(candidate)
  }

  private func updateApplyEnabled() {
    let hasFields = fieldChecks.values.contains { $0.state == .on }
    let hasArt = artworkCheckbox.isEnabled && artworkCheckbox.state == .on
    applyButton.isEnabled = selectedCandidate != nil && (hasFields || hasArt)
  }

  private func loadSelectedArtwork(_ candidate: MetadataCandidate) {
    selectedArtwork = nil
    let service = service
    Task { [weak self] in
      let data = try? await service.image(for: candidate, size: .full)
      guard !Task.isCancelled, let self, selectedCandidate?.id == candidate.id else { return }
      selectedArtwork = data
      if let data, let image = NSImage(data: data) {
        artworkView.image = image
        thumbnails[candidate.id] = image
        artworkCheckbox.isEnabled = true
        if artworkCheckbox.state == .off { artworkCheckbox.state = .on }
        updateApplyEnabled()
      }
    }
  }

  private var selectedChanges: [MetadataFieldChange] {
    guard let candidate = selectedCandidate else { return [] }
    return MetadataLookup.changes(for: track, candidate: candidate).filter {
      fieldChecks[$0.field]?.state == .on
    }
  }

  @objc private func previewToggled(_ sender: Any?) {
    updateApplyEnabled()
  }

  @objc private func applyClicked(_ sender: Any?) {
    guard let candidate = selectedCandidate else { return }
    applyButton.isEnabled = false
    searchButton.isEnabled = false
    let changes = selectedChanges
    let applyArtwork = artworkCheckbox.state == .on
    let artwork = selectedArtwork
    applyTask = Task { [weak self, service, library, track] in
      var picture: Picture?
      if applyArtwork {
        let data = artwork ?? (try? await service.image(for: candidate, size: .full))
        picture = data.flatMap { Picture(imageData: $0, type: nil) }
      }
      await MetadataLookup.apply(changes, artwork: picture, to: track, library: library)
      self?.onFinish?()
    }
  }

  @objc private func cancelClicked(_ sender: Any?) {
    searchTask?.cancel()
    coverTask?.cancel()
    applyTask?.cancel()
    onFinish?()
  }
}

extension MetadataLookupViewController: NSTextFieldDelegate {
  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    if selector == #selector(NSResponder.insertNewline(_:)) {
      search()
      return true
    }
    return false
  }
}

extension MetadataLookupViewController: NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    candidates.count
  }
}

extension MetadataLookupViewController: NSTableViewDelegate {
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard let tableColumn, let column = LookupColumn(rawValue: tableColumn.identifier.rawValue),
      candidates.indices.contains(row)
    else { return nil }
    let candidate = candidates[row]
    if column == .artwork {
      let view =
        tableView.makeView(withIdentifier: column.identifier, owner: nil) as? NSImageView
        ?? {
          let imageView = NSImageView()
          imageView.identifier = column.identifier
          imageView.imageScaling = .scaleProportionallyUpOrDown
          imageView.wantsLayer = true
          imageView.layer?.cornerRadius = 3
          imageView.layer?.masksToBounds = true
          return imageView
        }()
      view.image =
        thumbnails[candidate.id]
        ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
      return view
    }
    let cell =
      tableView.makeView(withIdentifier: column.identifier, owner: nil) as? NSTableCellView
      ?? {
        let cell = NSTableCellView()
        cell.identifier = column.identifier
        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(textField)
        cell.textField = textField
        NSLayoutConstraint.activate([
          textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
          textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
          textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
      }()
    cell.textField?.stringValue = column.text(for: candidate)
    cell.textField?.textColor = column == .source ? .secondaryLabelColor : .labelColor
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    updatePreview(selectedCandidate)
  }
}

private enum LookupColumn: String, CaseIterable {
  case artwork, title, artist, album, year, track, duration, source

  var identifier: NSUserInterfaceItemIdentifier { .init(rawValue) }

  var title: String {
    switch self {
    case .artwork: ""
    case .title: "Title"
    case .artist: "Artist"
    case .album: "Album"
    case .year: "Year"
    case .track: "#"
    case .duration: "Time"
    case .source: "Source"
    }
  }

  var width: CGFloat {
    switch self {
    case .artwork: 36
    case .title: 160
    case .artist: 120
    case .album: 140
    case .year: 48
    case .track: 36
    case .duration: 48
    case .source: 90
    }
  }

  func text(for candidate: MetadataCandidate) -> String {
    switch self {
    case .artwork: ""
    case .title: candidate.title
    case .artist: candidate.artist
    case .album: candidate.album
    case .year: String(candidate.date.prefix(4))
    case .track: candidate.trackNumber.map(String.init) ?? ""
    case .duration: candidate.duration.map(Format.duration) ?? ""
    case .source: candidate.source.name
    }
  }
}
