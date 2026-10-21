//
//  SidebarCells.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit

/// The sidebar's outline, where Return renames the file or folder selected, as in the Finder.
final class SidebarOutlineView: NSOutlineView {
  /// Told that Return was pressed.
  var onReturn: (() -> Bool)?

  override func keyDown(with event: NSEvent) {
    // Return, and Enter.
    if [36, 76].contains(event.keyCode),
      event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
      onReturn?() == true
    {
      return
    }
    super.keyDown(with: event)
  }
}

/// A file's or folder's row: its icon, which for a file is its artwork, where it has some, and
/// its name, which can be edited to rename it.
final class FileCell: NSTableCellView {
  static let iconSize: CGFloat = 18

  private let icon = NSImageView()

  init(identifier: NSUserInterfaceItemIdentifier) {
    super.init(frame: .zero)
    self.identifier = identifier
    icon.wantsLayer = true
    icon.layer?.masksToBounds = true
    icon.imageScaling = .scaleProportionallyUpOrDown
    let textField = NSTextField(labelWithString: "")
    textField.lineBreakMode = .byTruncatingMiddle
    textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    textField.makeEditableInPlace()
    for view in [icon, textField] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    NSLayoutConstraint.activate([
      icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
      icon.centerYAnchor.constraint(equalTo: centerYAnchor),
      icon.widthAnchor.constraint(equalToConstant: Self.iconSize),
      icon.heightAnchor.constraint(equalToConstant: Self.iconSize),
      textField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
      textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
      textField.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    imageView = icon
    self.textField = textField
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Shows a thumbnail, rounded, in place of a symbol; nil shows `symbol` instead.
  func setIcon(thumbnail: NSImage?, symbol: String) {
    let image = thumbnail ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    guard image !== icon.image else { return }
    // Faded in as it's made, rather than as a reused cell is given another file's.
    if thumbnail != nil, icon.image?.isTemplate == true { Motion.crossfade(icon) }
    icon.image = image
    icon.layer?.cornerRadius = thumbnail == nil ? 0 : 3
    icon.imageScaling = thumbnail == nil ? .scaleProportionallyDown : .scaleProportionallyUpOrDown
  }
}

/// A source's row: its icon and name, and a count where it has one.
final class SourceCell: NSTableCellView {
  private let badgeView = BadgeView()

  var badge: Int {
    get { badgeView.count }
    set { badgeView.count = newValue }
  }

  init(identifier: NSUserInterfaceItemIdentifier) {
    super.init(frame: .zero)
    self.identifier = identifier
    let imageView = NSImageView()
    let textField = NSTextField(labelWithString: "")
    textField.lineBreakMode = .byTruncatingMiddle
    textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let stack = NSStackView(views: [imageView, textField, badgeView])
    stack.spacing = 6
    stack.setCustomSpacing(4, after: textField)
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    textField.setContentHuggingPriority(.init(1), for: .horizontal)
    self.imageView = imageView
    self.textField = textField
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

/// A count in a capsule, as Mail shows unread messages, which fades in and out as it becomes
/// nonzero and zero, and crossfades as it changes.
private final class BadgeView: NSView {
  private let label = NSTextField(labelWithString: "")

  var count = 0 {
    didSet {
      guard count != oldValue else { return }
      if count > 0 {
        if oldValue > 0 { Motion.crossfade(label) }
        label.stringValue = count.formatted()
      }
      guard (count > 0) != (oldValue > 0) else { return }
      let isShown = count > 0
      if isShown {
        alphaValue = window == nil ? 1 : 0
        isHidden = false
      }
      Motion.animate(duration: 0.2) {
        animator().alphaValue = isShown ? 1 : 0
      } completion: { [weak self] in
        guard let self, count == 0 else { return }
        isHidden = true
      }
    }
  }

  init() {
    super.init(frame: .zero)
    wantsLayer = true
    isHidden = true
    label.wantsLayer = true
    label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
    label.textColor = .secondaryLabelColor
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
      label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
      widthAnchor.constraint(greaterThanOrEqualTo: heightAnchor),
    ])
    setContentHuggingPriority(.required, for: .horizontal)
    setContentCompressionResistancePriority(.required, for: .horizontal)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
  }

  override func layout() {
    super.layout()
    layer?.cornerRadius = bounds.height / 2
  }
}

extension NSTextField {
  /// Has a label that's edited in place, as a table's cell is, stay where it is as its editing
  /// begins: a single line, which scrolls rather than wraps, as the field editor lays it out.
  func makeEditableInPlace() {
    usesSingleLineMode = true
    cell?.wraps = false
    cell?.isScrollable = true
  }
}
