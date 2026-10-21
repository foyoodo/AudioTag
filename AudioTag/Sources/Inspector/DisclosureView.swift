//
//  DisclosureView.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit

/// A titled part of the inspector, which collapses and expands, animating, when its header is
/// clicked, and remembers which it did.
///
/// Its height is a single value it animates, from 0 to its content's and back, and again as the
/// content's changes while it's expanded, so that no change in it, nor in the sections below,
/// jumps. The content is laid out at its own height all the while, from the top, and clipped
/// rather than squeezed or faded; the padding around it is inside the height, so it shrinks with
/// it.
///
/// Mostly, the window is laid out once, at the end, and Core Animation carries every view's
/// frame there, which is smooth, as nothing is laid out or drawn on the way. Collapsing, the
/// height is animated frame by frame instead, so that the body clips the content as it's seen
/// to: laid out at its end from the start, the body would clip all of it at once, and text
/// that's drawn again on the way, drawn in nothing, would vanish. Content that has grown
/// shorter fits in the height it ends at, and so shrinks to it as smoothly as anything grows.
final class DisclosureView: NSView {
  enum Style {
    /// A section of the inspector, below a separator.
    case section
    /// A part of a section's content.
    case subsection
  }

  private let content: NSView
  private let body = NSView()
  private let header: DisclosureHeader
  private let defaultsKey: String?
  private let contentInsets: (top: CGFloat, bottom: CGFloat)
  /// The body's height: what's seen of the content, which is all of it, with its padding, when
  /// expanded, and none when collapsed.
  private var visibleHeight: NSLayoutConstraint!
  private var isHeightUpdateScheduled = false
  /// Whether the content has been laid out, and the height set to it, since which it animates.
  private var hasMeasuredContent = false

  private(set) var isCollapsed: Bool

  /// `defaultsKey` names where whether it's collapsed is kept, if anywhere.
  init(
    title: String, content: NSView, style: Style = .section, isCollapsedByDefault: Bool,
    defaultsKey: String? = nil
  ) {
    self.content = content
    self.defaultsKey = defaultsKey
    header = DisclosureHeader(title: title, style: style)
    contentInsets = style == .section ? (2, 16) : (4, 4)
    isCollapsed =
      defaultsKey.flatMap { UserDefaults.standard.object(forKey: $0) as? Bool }
      ?? isCollapsedByDefault
    super.init(frame: .zero)

    body.wantsLayer = true
    body.layer?.masksToBounds = true
    content.translatesAutoresizingMaskIntoConstraints = false
    body.addSubview(content)
    visibleHeight = body.heightAnchor.constraint(equalToConstant: 0)

    header.onClick = { [weak self] in self?.toggle() }

    var views: [NSView] = [header, body]
    if style == .section {
      let separator = NSBox()
      separator.boxType = .separator
      views.insert(separator, at: 0)
    }
    let inset: CGFloat = style == .section ? 16 : 0
    for view in views {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
      NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
        view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
      ])
    }
    for (upper, lower) in zip(views, views.dropFirst()) {
      lower.topAnchor.constraint(equalTo: upper.bottomAnchor).isActive = true
    }
    // The content's bottom is left free: it's as tall as it is, whatever's seen of it.
    NSLayoutConstraint.activate([
      views[0].topAnchor.constraint(equalTo: topAnchor),
      body.bottomAnchor.constraint(equalTo: bottomAnchor),
      visibleHeight,
      content.topAnchor.constraint(equalTo: body.topAnchor, constant: contentInsets.top),
      content.leadingAnchor.constraint(equalTo: body.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: body.trailingAnchor),
    ])

    content.postsFrameChangedNotifications = true
    NotificationCenter.default.addObserver(
      self, selector: #selector(contentFrameDidChange), name: NSView.frameDidChangeNotification,
      object: content)
    content.isHidden = isCollapsed
    header.setExpanded(!isCollapsed)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// The height that shows what there is to: all of the content, as laid out at the body's
  /// width, which its free bottom leaves at its own height, with its padding.
  private var targetHeight: CGFloat {
    isCollapsed ? 0 : (content.frame.height + contentInsets.top + contentInsets.bottom).rounded()
  }

  func toggle() {
    setCollapsed(!isCollapsed, animated: true)
  }

  func setCollapsed(_ collapsed: Bool, animated: Bool) {
    guard collapsed != isCollapsed else { return }
    isCollapsed = collapsed
    if let defaultsKey { UserDefaults.standard.set(collapsed, forKey: defaultsKey) }
    if !collapsed {
      // Laid out at its own height before any of it is seen.
      content.isHidden = false
      layoutSubtreeIfNeeded()
    }
    let duration = animated ? Self.duration : 0
    header.setExpanded(!collapsed, duration: duration, timing: Motion.easeInOut)
    animateHeight(to: targetHeight, duration: duration) { [weak self] in
      guard let self, isCollapsed == collapsed else { return }
      // Out of the key view loop, and accessibility, while it can't be seen.
      content.isHidden = collapsed
    }
  }

  /// How long expanding and collapsing take.
  private static let duration: TimeInterval = 0.25
  /// How long following the content's height takes, as it changes with what's selected, which
  /// is quicker, so as not to lag behind it.
  private static let followingDuration: TimeInterval = 0.2

  /// Animates the body to `height`, the views below it following.
  private func animateHeight(
    to height: CGFloat, duration: TimeInterval, completion: (@MainActor () -> Void)? = nil
  ) {
    guard let window, duration > 0, !Motion.isReduced else {
      visibleHeight.constant = height
      completion?()
      return
    }
    // From where everything is, so that only this change is animated.
    window.layoutIfNeeded()
    let clipsContent =
      height < content.frame.height + contentInsets.top + contentInsets.bottom - 0.5
    if clipsContent {
      Motion.animate(duration: duration, implicitly: false) {
        visibleHeight.animator().constant = height
      } completion: {
        completion?()
      }
    } else {
      Motion.animate(duration: duration) {
        visibleHeight.constant = height
        window.layoutIfNeeded()
      } completion: {
        completion?()
      }
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    // Shown at the height it has from the first, rather than growing into it.
    updateHeight(animated: false)
  }

  /// Follows the content's height, as what it shows changes, once the layout that changed it is
  /// done, rather than from within it.
  @objc private func contentFrameDidChange() {
    guard !isCollapsed, !isHeightUpdateScheduled else { return }
    isHeightUpdateScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      isHeightUpdateScheduled = false
      updateHeight(animated: hasMeasuredContent && window?.isVisible == true)
    }
  }

  private func updateHeight(animated: Bool) {
    let height = targetHeight
    if !isCollapsed, content.frame.height > 0 { hasMeasuredContent = true }
    guard abs(visibleHeight.constant - height) >= 0.5 else { return }
    animateHeight(to: height, duration: animated ? Self.followingDuration : 0)
  }
}

/// The header of a `DisclosureView`: a chevron that turns, and a title, all of it clickable.
private final class DisclosureHeader: NSView {
  private let chevron: ChevronView
  private let titleField: NSTextField
  private let style: DisclosureView.Style
  private var isHighlighted = false {
    didSet { titleField.textColor = isHighlighted ? .secondaryLabelColor : textColor }
  }

  var onClick: (() -> Void)?

  init(title: String, style: DisclosureView.Style) {
    self.style = style
    titleField = NSTextField(labelWithString: title)
    chevron = ChevronView(pointSize: style == .section ? 10 : 9)
    super.init(frame: .zero)
    titleField.font =
      style == .section
      ? .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
      : .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
    titleField.textColor = textColor

    for view in [chevron, titleField] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: style == .section ? 32 : 24),
      chevron.leadingAnchor.constraint(equalTo: leadingAnchor),
      chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
      chevron.widthAnchor.constraint(equalToConstant: 12),
      chevron.heightAnchor.constraint(equalToConstant: 12),
      titleField.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: 6),
      titleField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
      titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    setAccessibilityElement(true)
    setAccessibilityRole(.disclosureTriangle)
    setAccessibilityLabel(title)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private var textColor: NSColor {
    style == .section ? .labelColor : .secondaryLabelColor
  }

  func setExpanded(
    _ isExpanded: Bool, duration: TimeInterval = 0, timing: CAMediaTimingFunction = Motion.easeInOut
  ) {
    chevron.setPointsDown(isExpanded, duration: duration, timing: timing)
    setAccessibilityValue(isExpanded ? 1 : 0)
  }

  override func mouseDown(with event: NSEvent) {
    isHighlighted = true
  }

  override func mouseDragged(with event: NSEvent) {
    isHighlighted = bounds.contains(convert(event.locationInWindow, from: nil))
  }

  override func mouseUp(with event: NSEvent) {
    let isInside = bounds.contains(convert(event.locationInWindow, from: nil))
    isHighlighted = false
    if isInside { onClick?() }
  }

  override func accessibilityPerformPress() -> Bool {
    onClick?()
    return true
  }
}

/// A chevron that points right, or down, and turns between them. It's drawn in a layer of its
/// own, which turns about its center without upsetting the view's layout.
private final class ChevronView: NSView {
  private let arrow = CALayer()
  private let pointSize: CGFloat
  private var pointsDown = false

  init(pointSize: CGFloat) {
    self.pointSize = pointSize
    super.init(frame: .zero)
    wantsLayer = true
    layer?.addSublayer(arrow)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var wantsUpdateLayer: Bool { true }

  /// Draws the symbol in the appearance's color, which a layer's contents don't follow.
  override func updateLayer() {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
      .applying(.init(paletteColors: [.tertiaryLabelColor]))
    guard
      let image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
    else { return }
    let scale = window?.backingScaleFactor ?? 2
    effectiveAppearance.performAsCurrentDrawingAppearance {
      arrow.contents = image.layerContents(forContentsScale: scale)
    }
    arrow.contentsScale = scale
    arrow.contentsGravity = .center
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    arrow.bounds = bounds
    arrow.position = CGPoint(x: bounds.midX, y: bounds.midY)
    CATransaction.commit()
  }

  func setPointsDown(_ pointsDown: Bool, duration: TimeInterval, timing: CAMediaTimingFunction) {
    self.pointsDown = pointsDown
    CATransaction.begin()
    CATransaction.setDisableActions(duration == 0 || Motion.isReduced)
    CATransaction.setAnimationDuration(duration)
    CATransaction.setAnimationTimingFunction(timing)
    arrow.transform = CATransform3DMakeRotation(pointsDown ? -.pi / 2 : 0, 0, 0, 1)
    CATransaction.commit()
  }
}
