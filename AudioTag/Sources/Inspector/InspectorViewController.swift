//
//  InspectorViewController.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit

/// A part of the inspector, which shows the tracks selected.
@MainActor
protocol TrackInspecting: NSViewController {
  var tracks: [Track] { get set }
}

/// The tracks selected, in one panel: a summary with their artwork, then sections in the order
/// they're needed: the tags most edited, lyrics, every picture, every other tag, the tag formats
/// the files are saved in, and the files themselves.
final class InspectorViewController: NSViewController {
  private let placeholder = EmptyStateView(symbolName: "music.note", title: "No Selection")
  private let summary: SummaryViewController
  private let sections: [(title: String, isCollapsedByDefault: Bool, pane: any TrackInspecting)]
  private var contentView: NSView?

  var tracks: [Track] = [] {
    didSet {
      guard tracks != oldValue else { return }
      summary.tracks = tracks
      for section in sections { section.pane.tracks = tracks }
      guard let contentView, tracks.isEmpty != oldValue.isEmpty else { return }
      if tracks.isEmpty {
        Motion.show(placeholder, hiding: contentView)
      } else {
        Motion.show(contentView, hiding: placeholder)
      }
    }
  }

  init(library: Library) {
    summary = SummaryViewController(library: library)
    sections = [
      ("Tags", false, TagEditorViewController(library: library)),
      ("Lyrics", true, LyricsViewController(library: library)),
      ("Pictures", true, PicturesViewController(library: library)),
      ("Other Tags", true, OtherTagsViewController(library: library)),
      ("Tag Formats", true, TagFormatsViewController(library: library)),
      ("File", false, FileInfoViewController()),
    ]
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    addChild(summary)
    var views: [NSView] = [summary.view]
    for section in sections {
      addChild(section.pane)
      views.append(
        DisclosureView(
          title: section.title, content: section.pane.view,
          isCollapsedByDefault: section.isCollapsedByDefault,
          defaultsKey: "InspectorSectionCollapsed.\(section.title)"))
    }
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 0
    stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)
    for view in views {
      view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    let scrollView = ScrollingStack(stack)
    scrollView.isHidden = true
    contentView = scrollView

    let view = NSView()
    for subview in [scrollView, placeholder] {
      subview.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(subview)
    }
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      placeholder.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      placeholder.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      placeholder.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32),
    ])
    self.view = view
  }
}

/// A scroll view of a vertical stack, as wide as the scroll view is, from the top.
final class ScrollingStack: NSScrollView {
  init(_ stack: NSStackView) {
    super.init(frame: .zero)
    let documentView = FlippedView()
    documentView.translatesAutoresizingMaskIntoConstraints = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    documentView.addSubview(stack)
    self.documentView = documentView
    hasVerticalScroller = true
    autohidesScrollers = true
    drawsBackground = false
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: documentView.topAnchor),
      stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
      documentView.topAnchor.constraint(equalTo: contentView.topAnchor),
      documentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      documentView.widthAnchor.constraint(equalTo: contentView.widthAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
  }
}

/// Labels and fields in two columns, as the inspector's sections lay them out.
@MainActor
enum InspectorGrid {
  static func label(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.textColor = .secondaryLabelColor
    label.alignment = .right
    return label
  }

  static func make() -> NSGridView {
    let grid = NSGridView()
    grid.rowSpacing = 8
    grid.columnSpacing = 8
    grid.rowAlignment = .firstBaseline
    return grid
  }

  /// Removes every row, and its views, which removing a row alone leaves in the grid.
  static func removeAllRows(of grid: NSGridView) {
    while grid.numberOfRows > 0 {
      let row = grid.row(at: 0)
      for index in 0..<row.numberOfCells {
        row.cell(at: index).contentView?.removeFromSuperview()
      }
      grid.removeRow(at: 0)
    }
  }

  /// Aligns the labels of the grid's first column to the right, once it has rows.
  static func alignLabels(of grid: NSGridView) {
    guard grid.numberOfColumns > 0 else { return }
    grid.column(at: 0).xPlacement = .trailing
  }
}
