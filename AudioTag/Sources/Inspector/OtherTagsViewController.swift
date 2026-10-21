//
//  OtherTagsViewController.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit
import TagLib

/// Edits the tags of the tracks inspected that the tag fields don't, such as `ISRC` or
/// `MUSICBRAINZ_ALBUMID`, by the keys TagLib gives them in every format; together, as the
/// fields are, where several tracks are.
final class OtherTagsViewController: NSViewController, TrackInspecting {
  private let library: Library
  private let grid = InspectorGrid.make()
  private let newKeyField = NSTextField(string: "")
  private let newValueField = NSTextField(string: "")
  private let addButton = NSButton()
  private let emptyLabel = NSTextField(labelWithString: "No other tags.")
  /// The keys shown, each with its value's field.
  private var valueFields: [String: NSTextField] = [:]

  var tracks: [Track] = [] {
    didSet {
      guard tracks != oldValue else { return }
      reload()
    }
  }

  private var editableTracks: [Track] {
    tracks.filter(\.isEditable)
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
    emptyLabel.textColor = .secondaryLabelColor

    newKeyField.placeholderString = "KEY"
    newKeyField.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    newKeyField.widthAnchor.constraint(equalToConstant: 110).isActive = true
    newKeyField.delegate = self
    newValueField.placeholderString = "Value"
    newValueField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    newValueField.target = self
    newValueField.action = #selector(addTag(_:))
    addButton.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: "Add Tag")
    addButton.isBordered = false
    addButton.toolTip = "Add the tag"
    addButton.target = self
    addButton.action = #selector(addTag(_:))
    let newRow = NSStackView(views: [newKeyField, newValueField, addButton])
    newRow.spacing = 6

    let note = NSTextField(
      wrappingLabelWithString:
        "Keys are TagLib’s names for tags in every format, which each format stores in its own way."
    )
    note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    note.textColor = .tertiaryLabelColor

    let stack = NSStackView(views: [emptyLabel, grid, newRow, note])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    for view in [grid, newRow, note] {
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

  /// The keys the tracks have that the tag fields don't edit.
  private var keys: [String] {
    Set(editableTracks.flatMap(\.tags.values.keys)).subtracting(TagField.keys).sorted()
  }

  private func reload() {
    guard isViewLoaded else { return }
    let keys = keys
    if keys != valueFields.keys.sorted() {
      rebuild(keys)
    }
    let tracks = editableTracks
    for (key, field) in valueFields where field.currentEditor() == nil {
      let values = Set(tracks.map { $0.tags[key].joined(separator: "; ") })
      field.stringValue = values.count == 1 ? values.first! : ""
      field.placeholderString = values.count > 1 ? "Multiple Values" : nil
    }
    let isEnabled = !tracks.isEmpty
    for control in [newKeyField, newValueField, addButton] as [NSControl] {
      control.isEnabled = isEnabled
    }
    addButton.isEnabled = isEnabled && !newKey.isEmpty
  }

  private func rebuild(_ keys: [String]) {
    InspectorGrid.removeAllRows(of: grid)
    valueFields = [:]
    for key in keys {
      let label = NSTextField(labelWithString: key)
      label.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
      label.textColor = .secondaryLabelColor
      label.lineBreakMode = .byTruncatingMiddle
      label.toolTip = key
      label.widthAnchor.constraint(lessThanOrEqualToConstant: 110).isActive = true

      let field = NSTextField(string: "")
      field.identifier = .init(key)
      field.delegate = self
      field.lineBreakMode = .byTruncatingTail
      field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      valueFields[key] = field

      let remove = NSButton(
        image: NSImage(
          systemSymbolName: "minus.circle", accessibilityDescription: "Remove \(key)")!,
        target: self, action: #selector(removeTag(_:)))
      remove.isBordered = false
      remove.identifier = .init(key)
      remove.toolTip = "Remove the tag"

      grid.addRow(with: [label, field, remove])
    }
    grid.isHidden = keys.isEmpty
    emptyLabel.isHidden = !keys.isEmpty
    if grid.numberOfColumns > 0 { grid.column(at: 0).xPlacement = .trailing }
  }

  private var newKey: String {
    newKeyField.stringValue.trimmingCharacters(in: .whitespaces).uppercased()
  }

  @objc private func addTag(_ sender: Any?) {
    let key = newKey
    guard !key.isEmpty else {
      view.window?.makeFirstResponder(newKeyField)
      return
    }
    let value = newValueField.stringValue
    library.edit(tracks) { $0.tags[key] = [value] }
    newKeyField.stringValue = ""
    newValueField.stringValue = ""
    addButton.isEnabled = false
    valueFields[key].map { _ = view.window?.makeFirstResponder($0) }
  }

  @objc private func removeTag(_ sender: NSButton) {
    guard let key = sender.identifier?.rawValue else { return }
    library.edit(tracks) { $0.tags[key] = [] }
  }

  @objc private func tracksDidChange(_ notification: Notification) {
    guard let changed = notification.userInfo?[Library.tracksKey] as? [Track],
      !Set(changed).isDisjoint(with: tracks)
    else { return }
    reload()
  }
}

extension OtherTagsViewController: NSTextFieldDelegate {
  func controlTextDidChange(_ notification: Notification) {
    guard let field = notification.object as? NSTextField else { return }
    if field === newKeyField {
      addButton.isEnabled = !newKey.isEmpty
      return
    }
    apply(field)
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    guard let field = notification.object as? NSTextField else { return }
    apply(field)
  }

  private func apply(_ field: NSTextField) {
    guard field !== newKeyField, field !== newValueField, let key = field.identifier?.rawValue
    else { return }
    // Emptied, the tag stays, until it's removed.
    let value = field.stringValue
    let tracks = tracks.filter { $0.tags[key].joined(separator: "; ") != value }
    guard !tracks.isEmpty, field.placeholderString == nil || !value.isEmpty else { return }
    field.placeholderString = nil
    library.edit(tracks) { $0.tags[key] = [value] }
  }
}
