//
//  FileInfoViewController.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit
import TagLib

/// The tag formats the files inspected hold their tags in, the ones they're saved in, and the
/// items each holds, as it stores them.
final class TagFormatsViewController: NSViewController, TrackInspecting {
  private let library: Library
  private let grid = InspectorGrid.make()
  private let note = NSTextField(wrappingLabelWithString: "")
  private let versionPopUp = NSPopUpButton()
  private let itemsButton = NSButton()
  private let itemsStack = NSStackView()
  /// The tag formats offered, in the order the checkboxes show them.
  private var formats: [TagFormat] = []

  var tracks: [Track] = [] {
    didSet {
      guard tracks != oldValue else { return }
      reload()
    }
  }

  private var readTracks: [Track] {
    tracks.filter(\.isRead)
  }

  init(library: Library) {
    self.library = library
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    note.textColor = .tertiaryLabelColor

    versionPopUp.addItems(withTitles: ID3v2Version.allCases.map { "ID3v2.\($0.rawValue)" })
    versionPopUp.target = self
    versionPopUp.action = #selector(versionChosen(_:))

    itemsButton.setButtonType(.pushOnPushOff)
    itemsButton.bezelStyle = .disclosure
    itemsButton.title = ""
    itemsButton.target = self
    itemsButton.action = #selector(toggleItems(_:))
    let itemsTitle = NSButton(
      title: "Stored Items", target: self, action: #selector(toggleItemsFromTitle(_:)))
    itemsTitle.isBordered = false
    let itemsHeader = NSStackView(views: [itemsButton, itemsTitle])
    itemsHeader.spacing = 2

    itemsStack.orientation = .vertical
    itemsStack.alignment = .leading
    itemsStack.spacing = 10
    itemsStack.isHidden = true

    let stack = NSStackView(views: [grid, note, itemsHeader, itemsStack])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    for view in [grid, note, itemsStack] {
      view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    view = stack
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    NotificationCenter.default.addObserver(
      self, selector: #selector(tracksDidChange(_:)), name: Library.tracksDidChangeNotification,
      object: library)
    reload()
  }

  private func reload() {
    guard isViewLoaded else { return }
    InspectorGrid.removeAllRows(of: grid)
    let tracks = readTracks
    let audioFormats = Set(tracks.compactMap { $0.metadata?.format })
    formats = audioFormats.count == 1 ? audioFormats.first!.tagFormats : []

    let stored = Set(
      tracks.map { track in
        track.metadata.map { metadata in
          metadata.tagFormats.map {
            $0 == .id3v2 ? metadata.id3v2Version.map { "ID3v2.\($0)" } ?? $0.name : $0.name
          }
          .joined(separator: ", ")
        } ?? ""
      })
    let storedText =
      stored.count > 1 ? "Multiple" : stored.first.flatMap { $0.isEmpty ? nil : $0 } ?? "None"
    grid.addRow(with: [InspectorGrid.label("Stored in"), NSTextField(labelWithString: storedText)])

    if formats.count > 1 {
      let editable = tracks.filter(\.isEditable)
      let checkboxes = NSStackView()
      checkboxes.orientation = .vertical
      checkboxes.alignment = .leading
      checkboxes.spacing = 4
      for (index, format) in formats.enumerated() {
        let checkbox = NSButton(
          checkboxWithTitle: format.name, target: self, action: #selector(formatToggled(_:)))
        checkbox.tag = index
        checkbox.allowsMixedState = true
        let holding = editable.count(where: { $0.tagFormats.contains(format) })
        checkbox.state = holding == 0 ? .off : holding == editable.count ? .on : .mixed
        checkbox.isEnabled = !editable.isEmpty
        checkboxes.addArrangedSubview(checkbox)
      }
      grid.addRow(with: [InspectorGrid.label("Save in"), checkboxes])
      grid.row(at: grid.numberOfRows - 1).rowAlignment = .none
      grid.row(at: grid.numberOfRows - 1).yPlacement = .top
      note.stringValue =
        "When saved, the tags are written to each format checked, and removed from the others."
    } else if let format = audioFormats.first {
      note.stringValue =
        formats.first.map { "\(format.name) files keep their tags in \($0.name) tags only." }
        ?? "\(format.name) files can’t hold tags."
    } else {
      note.stringValue =
        audioFormats.isEmpty
        ? "" : "Select files of a single format to choose the tag formats they’re saved in."
    }

    if formats.contains(.id3v2) {
      let versions = Set(tracks.filter(\.isEditable).map(\.options.id3v2Version))
      if versions.count == 1, let version = versions.first {
        versionPopUp.selectItem(at: ID3v2Version.allCases.firstIndex(of: version)!)
      } else {
        versionPopUp.select(nil)
      }
      versionPopUp.isEnabled = tracks.contains(where: \.isEditable)
      grid.addRow(with: [InspectorGrid.label("Write as"), versionPopUp])
    }
    InspectorGrid.alignLabels(of: grid)
    note.isHidden = note.stringValue.isEmpty
    reloadItems()
  }

  /// Lists the items of the single track's tags, as last read from disk.
  private func reloadItems() {
    for view in itemsStack.arrangedSubviews { view.removeFromSuperview() }
    guard tracks.count == 1, let metadata = tracks.first?.metadata else {
      let label = NSTextField(labelWithString: "Select a single file to see its stored items.")
      label.textColor = .secondaryLabelColor
      itemsStack.addArrangedSubview(label)
      return
    }
    if metadata.nativeTags.isEmpty {
      let label = NSTextField(labelWithString: "The file holds no tags.")
      label.textColor = .secondaryLabelColor
      itemsStack.addArrangedSubview(label)
    }
    for tag in metadata.nativeTags {
      let name =
        tag.format == .id3v2
        ? metadata.id3v2Version.map { "ID3v2.\($0)" } ?? tag.format.name : tag.format.name
      let header = NSTextField(labelWithString: name)
      header.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
      itemsStack.addArrangedSubview(header)
      let items = InspectorGrid.make()
      items.rowSpacing = 4
      for item in tag.items {
        let key = NSTextField(labelWithString: item.key)
        key.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        key.textColor = .secondaryLabelColor
        key.lineBreakMode = .byTruncatingMiddle
        key.toolTip = item.key
        key.widthAnchor.constraint(lessThanOrEqualToConstant: 120).isActive = true
        let text =
          switch item.value {
          case .text(let text): text.replacing("\n", with: " ")
          case .binary(let byteCount): "Binary data, \(Format.bytes(byteCount))"
          }
        let value = NSTextField(labelWithString: text)
        value.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        value.isSelectable = true
        value.lineBreakMode = .byTruncatingTail
        value.toolTip = text
        value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        items.addRow(with: [key, value])
      }
      if tag.items.isEmpty {
        items.addRow(with: [InspectorGrid.label("Empty")])
      }
      InspectorGrid.alignLabels(of: items)
      itemsStack.addArrangedSubview(items)
      items.widthAnchor.constraint(equalTo: itemsStack.widthAnchor).isActive = true
    }
  }

  @objc private func toggleItems(_ sender: NSButton) {
    itemsStack.isHidden = sender.state == .off
  }

  @objc private func toggleItemsFromTitle(_ sender: NSButton) {
    itemsButton.state = itemsButton.state == .on ? .off : .on
    toggleItems(itemsButton)
  }

  @objc private func formatToggled(_ sender: NSButton) {
    if sender.state == .mixed { sender.state = .on }
    let format = formats[sender.tag]
    let holds = sender.state == .on
    library.edit(tracks) { track in
      if holds {
        track.tagFormats.insert(format)
      } else {
        track.tagFormats.remove(format)
      }
    }
  }

  @objc private func versionChosen(_ sender: NSPopUpButton) {
    let version = ID3v2Version.allCases[sender.indexOfSelectedItem]
    library.edit(tracks) { $0.options.id3v2Version = version }
  }

  @objc private func tracksDidChange(_ notification: Notification) {
    guard let changed = notification.userInfo?[Library.tracksKey] as? [Track],
      !Set(changed).isDisjoint(with: tracks)
    else { return }
    reload()
  }
}

/// The files of the tracks inspected: their audio, size and place.
final class FileInfoViewController: NSViewController, TrackInspecting {
  private let grid = InspectorGrid.make()

  var tracks: [Track] = [] {
    didSet {
      guard tracks != oldValue else { return }
      reload()
    }
  }

  override func loadView() {
    grid.rowSpacing = 6
    view = grid
  }

  private func reload() {
    guard isViewLoaded else { return }
    InspectorGrid.removeAllRows(of: grid)
    for (label, value) in info() {
      let valueField = NSTextField(labelWithString: value)
      valueField.isSelectable = true
      valueField.lineBreakMode = .byTruncatingMiddle
      valueField.toolTip = value
      valueField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      grid.addRow(with: [InspectorGrid.label(label), valueField])
    }
    if tracks.count == 1 {
      let reveal = NSButton(
        title: "Show in Finder", target: self, action: #selector(showInFinder(_:)))
      reveal.controlSize = .small
      reveal.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
      grid.addRow(with: [NSGridCell.emptyContentView, reveal])
    }
    InspectorGrid.alignLabels(of: grid)
  }

  private func info() -> [(String, String)] {
    func size(_ track: Track) -> Int {
      (try? track.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
    let read = tracks.filter(\.isRead)
    guard tracks.count == 1, let track = tracks.first else {
      let kinds = Set(read.compactMap { $0.metadata?.kind })
      let duration = read.reduce(0) { $0 + ($1.metadata?.properties?.duration ?? 0) }
      return [
        ("Files", tracks.count.formatted()),
        ("Kind", kinds.count == 1 ? kinds.first! : "Multiple"),
        ("Size", Format.bytes(tracks.reduce(0) { $0 + size($1) })),
        ("Duration", Format.duration(duration)),
      ]
    }
    var info = [("Name", track.name)]
    if let metadata = track.metadata {
      info.append(("Kind", metadata.kind))
      if let properties = metadata.properties {
        info += [
          ("Duration", Format.duration(properties.duration)),
          ("Bit Rate", Format.bitrate(properties.bitrate)),
          ("Sample Rate", Format.sampleRate(properties.sampleRate)),
          ("Channels", Format.channels(properties.channels)),
        ]
        if let bits = properties.bitsPerSample { info.append(("Bit Depth", "\(bits)-bit")) }
        if properties.isEncrypted { info.append(("Protected", "Yes")) }
      }
    } else if let error = track.readError {
      info.append(("Error", error.message))
    }
    info.append(("Size", Format.bytes(size(track))))
    if track.isRead && !track.isWritable { info.append(("Access", "Read only")) }
    info.append(("Where", track.url.deletingLastPathComponent().path))
    return info
  }

  @objc private func showInFinder(_ sender: Any?) {
    NSWorkspace.shared.activateFileViewerSelecting(tracks.map(\.url))
  }
}
