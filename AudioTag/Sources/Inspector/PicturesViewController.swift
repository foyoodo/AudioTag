//
//  PicturesViewController.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit
import TagLib
import UniformTypeIdentifiers

/// Edits every picture of the tracks inspected: what each shows, its description, and the image
/// itself, which can be replaced or removed, and more added. Several tracks are edited together
/// where their pictures are the same.
final class PicturesViewController: NSViewController, TrackInspecting {
  private let library: Library
  private let rowsStack = NSStackView()
  private let note = NSTextField(wrappingLabelWithString: "")
  private let addButton = NSButton(title: "Add Picture…", target: nil, action: nil)
  /// The pictures the rows show, which edits are made to.
  private var shownPictures: [Picture]?
  private var readTask: Task<Void, Never>?

  var tracks: [Track] = [] {
    didSet {
      guard tracks != oldValue else { return }
      reload()
      readTask?.cancel()
      let tracks = tracks
      readTask = Task { [library] in await library.readPictures(of: tracks) }
    }
  }

  private var editableTracks: [Track] {
    tracks.filter(\.isEditable)
  }

  /// The pictures of the tracks, where they're all read and the same.
  private var commonPictures: [Picture]? {
    let pictures = tracks.filter(\.isRead).map(\.pictures)
    guard let first = pictures.first, let first, pictures.allSatisfy({ $0 == first }) else {
      return nil
    }
    return first
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
    rowsStack.orientation = .vertical
    rowsStack.alignment = .leading
    rowsStack.spacing = 12
    note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    note.textColor = .tertiaryLabelColor
    addButton.target = self
    addButton.action = #selector(addPictures(_:))
    addButton.controlSize = .small
    addButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

    let stack = NSStackView(views: [rowsStack, addButton, note])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    for view in [rowsStack, note] {
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
    // The pictures shown stay until the tracks' are read, rather than going while they are,
    // and the section shrinking to grow again.
    guard !tracks.contains(where: { $0.isRead && $0.pictures == nil }) else { return }
    let pictures = commonPictures
    let isEditable = pictures != nil && !editableTracks.isEmpty
    addButton.isEnabled = isEditable
    note.stringValue = noteText(isEditable: isEditable)
    note.isHidden = note.stringValue.isEmpty
    guard pictures != shownPictures else { return }
    // Left as they are while a description is typed, which the rows already show.
    if let pictures, let shownPictures, pictures.count == shownPictures.count,
      zip(pictures, shownPictures).allSatisfy({ $0.data == $1.data && $0.kind == $1.kind }),
      view.window?.firstResponder is NSText
    {
      self.shownPictures = pictures
      return
    }
    shownPictures = pictures
    // MP4's `covr` keeps only images: every picture of it is a cover, without a description.
    let keepsDetails = !tracks.contains { $0.metadata?.format == .mp4 }
    for row in rowsStack.arrangedSubviews { row.removeFromSuperview() }
    for (index, picture) in (pictures ?? []).enumerated() {
      let row = PictureRow(picture: picture, isEditable: isEditable, keepsDetails: keepsDetails)
      row.onChange = { [weak self] picture in self?.edit { $0[index] = picture } }
      row.onRemove = { [weak self] in self?.edit { $0.remove(at: index) } }
      rowsStack.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
    }
  }

  private func noteText(isEditable: Bool) -> String {
    let read = tracks.filter(\.isRead)
    if read.contains(where: { $0.pictures == nil }) { return "" }
    if commonPictures == nil { return "The files selected have different pictures." }
    if commonPictures?.isEmpty == true, !isEditable { return "No pictures." }
    let formats = Set(read.compactMap { $0.metadata?.format })
    if formats.contains(.mp4) {
      return "MPEG-4 files keep pictures as covers, without their kinds or descriptions."
    }
    return ""
  }

  /// Changes the pictures shown, and gives every track that can be edited the result.
  private func edit(_ change: (inout [Picture]) -> Void) {
    guard var pictures = shownPictures else { return }
    change(&pictures)
    let result = pictures
    let tracks = editableTracks
    Task { await library.editPictures(of: tracks) { _ in result } }
  }

  @objc private func addPictures(_ sender: Any?) {
    guard let window = view.window else { return }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = true
    panel.message = "Choose images to add to the files’ pictures."
    panel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let self else { return }
      let added = panel.urls.compactMap { url in
        (try? Data(contentsOf: url)).flatMap {
          Picture(imageData: $0, type: UTType(filenameExtension: url.pathExtension))
        }
      }
      edit { pictures in
        for var picture in added {
          // The cover, where there's none; otherwise another picture, until said otherwise.
          picture.kind = pictures.contains { $0.kind == .frontCover } ? .other : .frontCover
          pictures.append(picture)
        }
      }
    }
  }

  @objc private func tracksDidChange(_ notification: Notification) {
    guard let changed = notification.userInfo?[Library.tracksKey] as? [Track],
      !Set(changed).isDisjoint(with: tracks)
    else { return }
    reload()
  }
}

/// A picture: its image, which can be replaced or removed, what it shows, and its description.
private final class PictureRow: NSView, NSTextFieldDelegate {
  private var picture: Picture
  private let well = ArtworkWell()
  private let kindPopUp = NSPopUpButton()
  private let descriptionField = NSTextField(string: "")

  /// Told of the picture as edited.
  var onChange: ((Picture) -> Void)?
  var onRemove: (() -> Void)?

  /// `keepsDetails` says whether the files keep pictures' kinds and descriptions, which can be
  /// edited only where they do.
  init(picture: Picture, isEditable: Bool, keepsDetails: Bool) {
    self.picture = picture
    super.init(frame: .zero)

    well.content = .picture(picture)
    well.isEnabled = isEditable
    well.onReceive = { [weak self] image in
      guard let self else { return }
      // A new image, of the same kind, with the same description.
      self.picture.data = image.data
      self.picture.mimeType = image.mimeType
      onChange?(self.picture)
    }
    well.onRemove = { [weak self] in self?.onRemove?() }

    kindPopUp.addItems(withTitles: Picture.Kind.allCases.map(\.name))
    kindPopUp.selectItem(at: Picture.Kind.allCases.firstIndex(of: picture.kind) ?? 0)
    kindPopUp.controlSize = .small
    kindPopUp.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    kindPopUp.target = self
    kindPopUp.action = #selector(kindChosen(_:))

    descriptionField.stringValue = picture.description
    descriptionField.placeholderString = "Description"
    descriptionField.controlSize = .small
    descriptionField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    descriptionField.delegate = self
    descriptionField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let info = NSTextField(labelWithString: picture.summary)
    info.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    info.textColor = .tertiaryLabelColor
    info.lineBreakMode = .byTruncatingTail
    info.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let remove = NSButton(
      image: NSImage(systemSymbolName: "minus.circle", accessibilityDescription: "Remove Picture")!,
      target: self, action: #selector(removeClicked(_:)))
    remove.isBordered = false
    remove.toolTip = "Remove the picture"

    remove.isEnabled = isEditable
    for control in [kindPopUp, descriptionField] as [NSControl] {
      control.isEnabled = isEditable && keepsDetails
    }

    let topLine = NSStackView(views: [kindPopUp, NSView(), remove])
    topLine.spacing = 6
    let details = NSStackView(views: [topLine, descriptionField, info])
    details.orientation = .vertical
    details.alignment = .leading
    details.spacing = 4
    for view in [topLine, descriptionField] {
      view.widthAnchor.constraint(equalTo: details.widthAnchor).isActive = true
    }

    for view in [well, details] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    NSLayoutConstraint.activate([
      well.leadingAnchor.constraint(equalTo: leadingAnchor),
      well.topAnchor.constraint(equalTo: topAnchor),
      well.widthAnchor.constraint(equalToConstant: 64),
      well.heightAnchor.constraint(equalToConstant: 64),
      well.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
      details.leadingAnchor.constraint(equalTo: well.trailingAnchor, constant: 10),
      details.trailingAnchor.constraint(equalTo: trailingAnchor),
      details.topAnchor.constraint(equalTo: topAnchor),
      details.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func kindChosen(_ sender: NSPopUpButton) {
    picture.kind = Picture.Kind.allCases[sender.indexOfSelectedItem]
    onChange?(picture)
  }

  @objc private func removeClicked(_ sender: Any?) {
    onRemove?()
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    guard descriptionField.stringValue != picture.description else { return }
    picture.description = descriptionField.stringValue
    onChange?(picture)
  }
}
