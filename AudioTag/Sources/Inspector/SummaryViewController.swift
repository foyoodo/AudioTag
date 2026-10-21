//
//  SummaryViewController.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit
import TagLib

/// The head of the inspector: the artwork of the tracks inspected, which is the picture most
/// often edited and so can be replaced here, and what they are. Every picture is edited in the
/// Pictures section.
final class SummaryViewController: NSViewController, TrackInspecting {
  private let library: Library
  private let artworkWell = ArtworkWell()
  private let titleField = NSTextField(wrappingLabelWithString: "")
  private let subtitleField = NSTextField(labelWithString: "")
  private let detailField = NSTextField(labelWithString: "")
  private let artworkField = NSTextField(labelWithString: "")
  private var artworkTask: Task<Void, Never>?

  var tracks: [Track] = [] {
    didSet {
      guard tracks != oldValue else { return }
      reload()
      readPictures()
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
    artworkWell.onReceive = { [weak self] picture in
      guard let self else { return }
      let tracks = editableTracks
      Task { await library.setArtwork(picture, of: tracks) }
    }
    artworkWell.onRemove = { [weak self] in
      guard let self else { return }
      let tracks = editableTracks
      Task { await library.setArtwork(nil, of: tracks) }
    }
    NSLayoutConstraint.activate([
      artworkWell.widthAnchor.constraint(equalToConstant: 96),
      artworkWell.heightAnchor.constraint(equalToConstant: 96),
    ])

    titleField.font = .systemFont(ofSize: NSFont.systemFontSize + 2, weight: .semibold)
    titleField.maximumNumberOfLines = 2
    titleField.lineBreakMode = .byTruncatingTail
    subtitleField.textColor = .secondaryLabelColor
    for field in [detailField, artworkField] {
      field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
      field.textColor = .tertiaryLabelColor
    }
    for field in [titleField, subtitleField, detailField, artworkField] {
      field.lineBreakMode = .byTruncatingTail
      field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    let text = NSStackView(views: [titleField, subtitleField, detailField, artworkField])
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 2
    text.setCustomSpacing(6, after: subtitleField)

    let stack = NSStackView(views: [artworkWell, text])
    stack.alignment = .top
    stack.spacing = 12
    // Pinned with room below, for the artwork's shadow and the section divider under it, rather
    // than by the stack's insets, which a horizontal stack's height doesn't keep.
    let view = NSView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -22),
    ])
    self.view = view
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
    let read = tracks.filter(\.isRead)
    if tracks.count == 1, let track = tracks.first {
      titleField.stringValue = track.tags.title ?? track.name
      subtitleField.stringValue = [track.tags.artist, track.tags.album].compactMap(\.self).joined(
        separator: " — ")
      var details = [
        track.metadata?.kind, track.metadata?.properties.map { Format.duration($0.duration) },
      ]
      if track.isRead && !track.isWritable { details.append("Read Only") }
      if let error = track.readError { details.append(error.message) }
      detailField.stringValue = details.compactMap(\.self).joined(separator: " · ")
    } else {
      titleField.stringValue = "\(tracks.count.formatted()) Files"
      let albums = Set(read.map { $0.tags.album ?? "" })
      let artists = Set(read.map { $0.tags.albumArtist ?? $0.tags.artist ?? "" })
      subtitleField.stringValue =
        albums.count == 1 && albums.first != ""
        ? [artists.count == 1 ? artists.first : nil, albums.first].compactMap(\.self)
          .filter { !$0.isEmpty }.joined(separator: " — ")
        : "Multiple Albums"
      let kinds = Set(read.compactMap { $0.metadata?.kind })
      let duration = read.reduce(0) { $0 + ($1.metadata?.properties?.duration ?? 0) }
      let readOnly = read.count(where: { !$0.isWritable })
      var details = [kinds.count == 1 ? kinds.first! : "Multiple Kinds", Format.duration(duration)]
      if readOnly > 0 { details.append("\(readOnly) read only") }
      detailField.stringValue = details.joined(separator: " · ")
    }
    subtitleField.isHidden = subtitleField.stringValue.isEmpty
    updateArtwork()
  }

  private var editableTracks: [Track] {
    tracks.filter(\.isEditable)
  }

  private func updateArtwork() {
    let tracks = tracks.filter(\.isRead)
    artworkWell.isEnabled = !editableTracks.isEmpty
    if tracks.isEmpty {
      artworkWell.content = .empty
    } else if tracks.contains(where: { $0.pictures == nil }) {
      // The artwork shown stays while the tracks' pictures are read, to fade into theirs,
      // rather than the well emptying for a moment.
      return
    } else {
      let artworks = Set(tracks.map(\.artwork))
      artworkWell.content =
        artworks.count > 1
        ? .mixed : artworks.first.flatMap { $0.map(ArtworkWell.Content.picture) } ?? .empty
    }
    let others = tracks.count == 1 ? (tracks[0].pictures?.count ?? 1) - 1 : 0
    artworkField.stringValue =
      switch artworkWell.content {
      case .picture(let picture) where others > 0:
        "\(picture.summary) · \(others) more \(others == 1 ? "picture" : "pictures")"
      case .picture(let picture): picture.summary
      case .mixed: "Different artwork"
      case .empty where artworkWell.isEnabled: "Drop an image on the artwork to add it."
      default: ""
      }
    artworkField.toolTip = artworkField.stringValue
  }

  private func readPictures() {
    artworkTask?.cancel()
    let tracks = tracks
    artworkTask = Task { [library] in
      await library.readPictures(of: tracks)
      guard !Task.isCancelled else { return }
      updateArtwork()
    }
  }

  @objc private func tracksDidChange(_ notification: Notification) {
    guard let changed = notification.userInfo?[Library.tracksKey] as? [Track],
      !Set(changed).isDisjoint(with: tracks)
    else { return }
    reload()
  }
}
