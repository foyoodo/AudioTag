//
//  EmptyStateView.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit

/// What a list or panel shows while it has nothing to: a symbol and a line or two, and a
/// button where there's something to do about it.
final class EmptyStateView: NSStackView {
  private let imageView = NSImageView()
  private let titleField = NSTextField(wrappingLabelWithString: "")
  private let messageField = NSTextField(wrappingLabelWithString: "")

  init(symbolName: String, title: String, message: String = "", button: NSButton? = nil) {
    super.init(frame: .zero)
    orientation = .vertical
    spacing = 6
    imageView.symbolConfiguration = .init(pointSize: 32, weight: .light)
    imageView.contentTintColor = .tertiaryLabelColor
    titleField.font = .systemFont(ofSize: NSFont.systemFontSize + 2, weight: .semibold)
    titleField.textColor = .secondaryLabelColor
    messageField.textColor = .tertiaryLabelColor
    for field in [titleField, messageField] {
      field.alignment = .center
      field.isSelectable = false
    }
    for view in [imageView, titleField, messageField] { addArrangedSubview(view) }
    setCustomSpacing(10, after: imageView)
    if let button {
      addArrangedSubview(button)
      setCustomSpacing(14, after: messageField)
    }
    set(symbolName: symbolName, title: title, message: message)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func set(symbolName: String, title: String, message: String = "") {
    imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    titleField.stringValue = title
    messageField.stringValue = message
    messageField.isHidden = message.isEmpty
  }
}
