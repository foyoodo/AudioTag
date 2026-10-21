//
//  TagEditorViewController.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit
import TagLib

/// Edits the tags most edited of the tracks inspected, together: a field whose value differs
/// between them shows so, and editing it gives them all the same.
final class TagEditorViewController: NSViewController, TrackInspecting {
  private let library: Library
  private var fields: [TagField: NSTextField] = [:]
  /// The fields whose values differ between the tracks, until edited.
  private var mixedFields: Set<TagField> = []
  /// Tells of a date that isn't one, and of what of a date the files' tags won't keep.
  private let dateNote = NSTextField(wrappingLabelWithString: "")
  /// What was typed that's no date, which stays told of until the field is edited again.
  private var invalidDate: (field: TagField, text: String)?

  var tracks: [Track] = [] {
    didSet {
      guard tracks != oldValue else { return }
      reload()
    }
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
    let grid = InspectorGrid.make()
    for field in [TagField.title, .artist, .album, .albumArtist, .composer, .genre] {
      grid.addRow(with: [InspectorGrid.label(field.label), textField(for: field)])
    }
    for field in [TagField.date, .originalDate] {
      let date = textField(for: field)
      date.widthAnchor.constraint(equalToConstant: 150).isActive = true
      grid.addRow(with: [InspectorGrid.label(field.label), date])
    }
    grid.addRow(with: [InspectorGrid.label("Track"), positionFields(.trackNumber, .trackCount)])
    grid.addRow(with: [InspectorGrid.label("Disc"), positionFields(.discNumber, .discCount)])
    grid.addRow(with: [InspectorGrid.label(TagField.comment.label), textField(for: .comment)])
    InspectorGrid.alignLabels(of: grid)

    dateNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    dateNote.textColor = .secondaryLabelColor
    dateNote.isHidden = true
    let stack = NSStackView(views: [grid, dateNote])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    for view in [grid, dateNote] {
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

  private func textField(for field: TagField) -> NSTextField {
    let textField = NSTextField(string: "")
    textField.identifier = .init(field.rawValue)
    textField.delegate = self
    textField.lineBreakMode = .byTruncatingTail
    textField.usesSingleLineMode = true
    textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    if field.isNumeric {
      textField.alignment = .right
      textField.widthAnchor.constraint(equalToConstant: 44).isActive = true
    }
    fields[field] = textField
    return textField
  }

  private func positionFields(_ number: TagField, _ count: TagField) -> NSView {
    let of = NSTextField(labelWithString: "of")
    of.textColor = .secondaryLabelColor
    let stack = NSStackView(views: [textField(for: number), of, textField(for: count)])
    stack.spacing = 6
    return stack
  }

  private func reload() {
    guard isViewLoaded else { return }
    let tracks = tracks.filter(\.isEditable)
    for (field, textField) in fields where textField.currentEditor() == nil {
      textField.isEnabled = !tracks.isEmpty
      let values = Set(tracks.map { field.value(in: $0.tags) })
      textField.stringValue = values.count == 1 ? values.first! : ""
      if values.count > 1 { mixedFields.insert(field) } else { mixedFields.remove(field) }
      textField.placeholderString =
        values.count > 1
        ? field.isNumeric ? "—" : "Multiple Values"
        : field.isDate ? "yyyy-mm-dd" : nil
    }
    updateDateNote()
  }

  /// Tells of a date typed that isn't one, or else of what of the dates the files' tags won't
  /// keep: ID3v2.3 keeps a month only with its day, and a time only to the minute; ID3v1, only
  /// the year.
  private func updateDateNote() {
    var notes: [String] = []
    if let invalidDate {
      notes.append(
        "“\(invalidDate.text)” isn’t a date. Enter one such as 2021, 2021-06 or 2021-06-01.")
    } else {
      let tracks = tracks.filter(\.isEditable)
      let dates = tracks.flatMap { track in
        [TagField.date, .originalDate].compactMap { TagDate($0.value(in: track.tags)) }
          .map { (track, $0) }
      }
      if dates.contains(where: { track, date in
        track.writesID3v23 && date.precision == .month
      }) {
        notes.append("ID3v2.3 tags keep a month only with its day, so only the year is saved.")
      }
      if tracks.contains(where: { track in
        track.writesID3v23
          && (TagDate(TagField.originalDate.value(in: track.tags))?.precision ?? .year) > .year
      }) {
        notes.append("ID3v2.3 tags keep only the year of an original date.")
      }
      if dates.contains(where: { track, date in track.writesID3v23 && date.second != nil }) {
        notes.append("ID3v2.3 tags keep times to the minute.")
      }
      if dates.contains(where: { track, date in
        track.tagFormats.contains(.id3v1) && date.precision > .year
      }) {
        notes.append("ID3v1 tags keep only the year.")
      }
    }
    dateNote.stringValue = notes.joined(separator: " ")
    dateNote.textColor = invalidDate == nil ? .secondaryLabelColor : .systemRed
    dateNote.isHidden = notes.isEmpty
  }

  @objc private func tracksDidChange(_ notification: Notification) {
    guard let changed = notification.userInfo?[Library.tracksKey] as? [Track],
      !Set(changed).isDisjoint(with: tracks)
    else { return }
    reload()
  }
}

extension TagEditorViewController: NSTextFieldDelegate {
  func controlTextDidChange(_ notification: Notification) {
    apply(notification)
  }

  /// Applies text an input method composed, which isn't told of until it's done; a date is
  /// shown as it's written, or, where it's none, as it was, telling why.
  func controlTextDidEndEditing(_ notification: Notification) {
    apply(notification)
    guard let textField = notification.object as? NSTextField,
      let field = textField.identifier.flatMap({ TagField(rawValue: $0.rawValue) }), field.isDate
    else { return }
    if let date = field.normalized(textField.stringValue) {
      textField.stringValue = date
    } else {
      invalidDate = (field, textField.stringValue)
      reload()
    }
  }

  private func apply(_ notification: Notification) {
    guard let textField = notification.object as? NSTextField,
      let field = textField.identifier.flatMap({ TagField(rawValue: $0.rawValue) })
    else { return }
    if invalidDate?.field == field {
      invalidDate = nil
      updateDateNote()
    }
    // A date that isn't one yet, as it's typed, isn't written.
    guard let text = field.normalized(textField.stringValue) else { return }
    let tracks = tracks.filter { field.value(in: $0.tags) != text }
    guard !tracks.isEmpty, !mixedFields.contains(field) || !text.isEmpty else { return }
    mixedFields.remove(field)
    textField.placeholderString = field.isDate ? "yyyy-mm-dd" : nil
    library.edit(tracks) { field.set(text, in: &$0.tags) }
  }
}

/// Edits the lyrics of the tracks inspected, together.
final class LyricsViewController: NSViewController, TrackInspecting {
  private let library: Library
  private let textView = NSTextView()

  var tracks: [Track] = [] {
    didSet {
      guard tracks != oldValue else { return }
      reload()
    }
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
    textView.isRichText = false
    textView.allowsUndo = true
    textView.font = .systemFont(ofSize: NSFont.systemFontSize)
    textView.textContainerInset = NSSize(width: 2, height: 4)
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.delegate = self
    textView.isVerticallyResizable = true
    textView.autoresizingMask = .width
    textView.textContainer?.widthTracksTextView = true
    let scrollView = NSScrollView()
    scrollView.documentView = textView
    scrollView.hasVerticalScroller = true
    scrollView.borderType = .bezelBorder
    scrollView.heightAnchor.constraint(equalToConstant: 180).isActive = true
    view = scrollView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    NotificationCenter.default.addObserver(
      self, selector: #selector(tracksDidChange(_:)), name: Library.tracksDidChangeNotification,
      object: library)
    reload()
  }

  private func reload() {
    guard isViewLoaded, view.window?.firstResponder !== textView else { return }
    let tracks = tracks.filter(\.isEditable)
    let values = Set(tracks.map { TagField.lyrics.value(in: $0.tags) })
    textView.isEditable = !tracks.isEmpty
    textView.string = values.count == 1 ? values.first! : ""
    textView.textColor = .labelColor
  }

  @objc private func tracksDidChange(_ notification: Notification) {
    guard let changed = notification.userInfo?[Library.tracksKey] as? [Track],
      !Set(changed).isDisjoint(with: tracks)
    else { return }
    reload()
  }
}

extension LyricsViewController: NSTextViewDelegate {
  func textDidChange(_ notification: Notification) {
    apply()
  }

  func textDidEndEditing(_ notification: Notification) {
    apply()
  }

  private func apply() {
    let text = textView.string
    let tracks = tracks.filter { TagField.lyrics.value(in: $0.tags) != text }
    library.edit(tracks) { TagField.lyrics.set(text, in: &$0.tags) }
  }
}
