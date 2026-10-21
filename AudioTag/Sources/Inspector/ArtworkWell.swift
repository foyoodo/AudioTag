//
//  ArtworkWell.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit
import TagLib
import UniformTypeIdentifiers

/// Shows the artwork of the tracks inspected, and takes a new one dropped, pasted or chosen.
final class ArtworkWell: NSView {
  enum Content: Equatable {
    case empty
    /// The pictures are being read.
    case loading
    /// The tracks' artworks differ.
    case mixed
    case picture(Picture)
  }

  /// Told of a picture the well was given, by dropping, pasting or choosing one.
  var onReceive: ((Picture) -> Void)?
  /// Told that the picture was removed.
  var onRemove: (() -> Void)?

  var content = Content.empty {
    didSet {
      guard content != oldValue else { return }
      update()
    }
  }

  var isEnabled = true {
    didSet { update() }
  }

  private let imageView = NSImageView()
  private let placeholder = NSTextField(labelWithString: "")
  /// Shown while an image is dragged over the well.
  private let dropHighlight = NSView()
  private var isDropTarget = false {
    didSet {
      guard isDropTarget != oldValue else { return }
      Motion.animate(duration: 0.15) {
        dropHighlight.animator().alphaValue = isDropTarget ? 1 : 0
      }
    }
  }

  private static let imageTypes: [NSPasteboard.PasteboardType] = [
    .fileURL, .png, .tiff, .init(UTType.jpeg.identifier), .init(UTType.heic.identifier),
  ]

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = Self.cornerRadius
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOffset = CGSize(width: 0, height: -1)
    layer?.shadowRadius = 4
    focusRingType = .default

    // Clipped to the well's corners, which the well itself isn't, to cast its shadow.
    imageView.wantsLayer = true
    imageView.layer?.cornerRadius = Self.cornerRadius
    imageView.layer?.masksToBounds = true
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.unregisterDraggedTypes()
    // The image's size is no size for the well.
    for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
      imageView.setContentCompressionResistancePriority(.init(1), for: orientation)
      imageView.setContentHuggingPriority(.init(1), for: orientation)
    }
    placeholder.alignment = .center
    placeholder.textColor = .tertiaryLabelColor
    placeholder.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
    placeholder.maximumNumberOfLines = 2
    dropHighlight.wantsLayer = true
    dropHighlight.layer?.cornerRadius = Self.cornerRadius
    dropHighlight.layer?.borderWidth = 3
    dropHighlight.alphaValue = 0
    for subview in [imageView, placeholder, dropHighlight] {
      subview.translatesAutoresizingMaskIntoConstraints = false
      addSubview(subview)
    }
    NSLayoutConstraint.activate([
      imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
      imageView.topAnchor.constraint(equalTo: topAnchor),
      imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
      dropHighlight.leadingAnchor.constraint(equalTo: leadingAnchor),
      dropHighlight.trailingAnchor.constraint(equalTo: trailingAnchor),
      dropHighlight.topAnchor.constraint(equalTo: topAnchor),
      dropHighlight.bottomAnchor.constraint(equalTo: bottomAnchor),
      placeholder.centerXAnchor.constraint(equalTo: centerXAnchor),
      placeholder.centerYAnchor.constraint(equalTo: centerYAnchor),
      placeholder.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),
    ])
    registerForDraggedTypes(Self.imageTypes)
    toolTip = "Drop, paste or double-click to choose an image."
    update()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private static let cornerRadius: CGFloat = 8

  private var picture: Picture? {
    if case .picture(let picture) = content { picture } else { nil }
  }

  private func update() {
    let image = picture.flatMap { NSImage(data: $0.data) }
    if image != nil || imageView.image != nil { Motion.crossfade(imageView) }
    imageView.image = image
    placeholder.stringValue =
      switch content {
      case .empty: isEnabled ? "No Artwork" : ""
      case .loading: ""
      case .mixed: "Multiple Images"
      case .picture: imageView.image == nil ? "Unreadable Image" : ""
      }
    needsDisplay = true
    noteFocusRingMaskChanged()
  }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    let hasImage = imageView.image != nil
    // A picture casts a shadow; an empty well is a recess.
    layer?.borderColor = NSColor.separatorColor.cgColor
    layer?.borderWidth = hasImage ? 0 : 1
    layer?.backgroundColor =
      hasImage ? NSColor.windowBackgroundColor.cgColor : NSColor.quaternarySystemFill.cgColor
    layer?.shadowOpacity = hasImage ? 0.2 : 0
    layer?.shadowPath = CGPath(
      roundedRect: bounds, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius,
      transform: nil)
    dropHighlight.layer?.borderColor = NSColor.controlAccentColor.cgColor
    dropHighlight.layer?.backgroundColor =
      NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
  }

  override func layout() {
    super.layout()
    needsDisplay = true
  }

  // MARK: Focus

  override var acceptsFirstResponder: Bool { isEnabled }

  override var focusRingMaskBounds: NSRect { bounds }

  override func drawFocusRingMask() {
    NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
      .fill()
  }

  override func becomeFirstResponder() -> Bool {
    noteFocusRingMaskChanged()
    return super.becomeFirstResponder()
  }

  override func resignFirstResponder() -> Bool {
    noteFocusRingMaskChanged()
    return super.resignFirstResponder()
  }

  // MARK: Mouse and keyboard

  override func mouseDown(with event: NSEvent) {
    guard isEnabled else { return }
    window?.makeFirstResponder(self)
    if event.clickCount == 2 {
      chooseImage(nil)
      return
    }
    // Drag the picture out, once the mouse moves far enough.
    guard let picture, let image = imageView.image else { return }
    let start = event.locationInWindow
    while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]),
      next.type == .leftMouseDragged
    {
      guard hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) > 4 else {
        continue
      }
      let item = NSDraggingItem(pasteboardWriter: Self.pasteboardItem(for: picture))
      item.setDraggingFrame(bounds, contents: image)
      beginDraggingSession(with: [item], event: event, source: self)
      return
    }
  }

  override func keyDown(with event: NSEvent) {
    interpretKeyEvents([event])
  }

  override func deleteBackward(_ sender: Any?) {
    delete(sender)
  }

  override func deleteForward(_ sender: Any?) {
    delete(sender)
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    guard isEnabled else { return nil }
    let menu = NSMenu()
    menu.addItem(withTitle: "Choose Image…", action: #selector(chooseImage(_:)), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
    menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
    menu.addItem(withTitle: "Remove Artwork", action: #selector(delete(_:)), keyEquivalent: "")
    return menu
  }

  // MARK: Editing

  @objc func chooseImage(_ sender: Any?) {
    guard isEnabled, let window else { return }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.message = "Choose an image for the artwork."
    panel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let self, let url = panel.url,
        let data = try? Data(contentsOf: url),
        let picture = Picture(imageData: data, type: UTType(filenameExtension: url.pathExtension))
      else { return }
      onReceive?(picture)
    }
  }

  @objc func copy(_ sender: Any?) {
    guard let picture else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([Self.pasteboardItem(for: picture)])
  }

  @objc func cut(_ sender: Any?) {
    copy(sender)
    delete(sender)
  }

  @objc func paste(_ sender: Any?) {
    guard let picture = Picture(pasteboard: .general) else { return }
    onReceive?(picture)
  }

  @objc func delete(_ sender: Any?) {
    guard isEnabled, content != .empty, content != .loading else { return }
    onRemove?()
  }

  private static func pasteboardItem(for picture: Picture) -> NSPasteboardItem {
    let item = NSPasteboardItem()
    if let type = UTType(mimeType: picture.mimeType) {
      item.setData(picture.data, forType: .init(type.identifier))
    }
    if let image = NSImage(data: picture.data), let tiff = image.tiffRepresentation {
      item.setData(tiff, forType: .tiff)
    }
    return item
  }

  // MARK: Dropping

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard isEnabled, sender.draggingSource as? ArtworkWell !== self,
      NSImage.canInit(with: sender.draggingPasteboard)
    else { return [] }
    isDropTarget = true
    return .copy
  }

  override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    isDropTarget = false
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    isDropTarget = false
    guard let picture = Picture(pasteboard: sender.draggingPasteboard) else { return false }
    onReceive?(picture)
    return true
  }
}

extension ArtworkWell: NSDraggingSource {
  func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    .copy
  }
}

extension ArtworkWell: NSMenuItemValidation {
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(copy(_:)): picture != nil
    case #selector(cut(_:)), #selector(delete(_:)):
      isEnabled && content != .empty && content != .loading
    case #selector(paste(_:)): isEnabled && NSImage.canInit(with: .general)
    default: isEnabled
    }
  }
}

extension Picture {
  /// A picture of image data, kept as it's encoded where it's a JPEG or PNG image, which every
  /// format's tags can hold, or else converted to PNG.
  init?(imageData data: Data, type: UTType?) {
    if let type, type.conforms(to: .jpeg) || type.conforms(to: .png),
      let mimeType = type.preferredMIMEType
    {
      self.init(data: data, mimeType: mimeType)
      return
    }
    guard let image = NSImage(data: data), let png = image.pngData else { return nil }
    self.init(data: png, mimeType: "image/png")
  }

  /// The image on the pasteboard: the contents of an image file, or image data.
  init?(pasteboard: NSPasteboard) {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [
      .urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: [UTType.image.identifier],
    ]
    if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?
      .first,
      let data = try? Data(contentsOf: url)
    {
      self.init(imageData: data, type: UTType(filenameExtension: url.pathExtension))
      return
    }
    for type in [UTType.jpeg, .png] {
      if let data = pasteboard.data(forType: .init(type.identifier)) {
        self.init(imageData: data, type: type)
        return
      }
    }
    guard let image = NSImage(pasteboard: pasteboard), let png = image.pngData else { return nil }
    self.init(data: png, mimeType: "image/png")
  }

  /// Such as `1400 × 1400 · JPEG · 245 KB`.
  var summary: String {
    var parts: [String] = []
    if let image = NSBitmapImageRep(data: data) {
      parts.append("\(image.pixelsWide) × \(image.pixelsHigh)")
    }
    if let type = UTType(mimeType: mimeType) {
      parts.append(
        type.preferredFilenameExtension?.uppercased() ?? type.localizedDescription ?? mimeType)
    }
    parts.append(Format.bytes(data.count))
    return parts.joined(separator: " · ")
  }
}

extension NSImage {
  fileprivate var pngData: Data? {
    tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(
      using: .png, properties: [:])
  }
}
