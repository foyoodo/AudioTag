//
//  MainSplitViewController.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit

/// The sources of tracks in a sidebar, the selected source's tracks, and an inspector of the
/// tracks selected.
final class MainSplitViewController: NSSplitViewController {
  private let library: Library
  private let sources: Sources
  private let fileOperations: FileOperations
  let sidebar: SidebarViewController
  let trackList: TrackListViewController
  let inspector: InspectorViewController

  /// Told of the source shown.
  var onSourceChange: ((TrackSource?) -> Void)?
  /// Told of the status line to show.
  var onStatusChange: ((String) -> Void)?

  init(library: Library, sources: Sources) {
    self.library = library
    self.sources = sources
    fileOperations = FileOperations(library: library)
    sidebar = SidebarViewController(
      library: library, sources: sources, fileOperations: fileOperations,
      thumbnails: ArtworkThumbnails(pointSize: FileCell.iconSize))
    trackList = TrackListViewController(
      library: library, sources: sources, fileOperations: fileOperations)
    inspector = InspectorViewController(library: library)
    super.init(nibName: nil, bundle: nil)

    sidebar.onSelect = { [weak self] source, file in
      guard let self else { return }
      trackList.show(source)
      // A file is shown in its folder, selected.
      if let file { trackList.select([file]) }
      onSourceChange?(source)
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(filesDidChange), name: FileOperations.didChangeNotification,
      object: fileOperations)
    trackList.onSelectionChange = { [weak self] tracks in
      guard let self else { return }
      inspector.tracks = tracks
      library.unloadPictures(except: tracks)
      if tracks.count == 1 { sidebar.follow(tracks[0].url) }
    }
    trackList.onStatusChange = { [weak self] status in
      self?.onStatusChange?(status)
    }
    trackList.onOpen = { [weak self] urls in
      self?.open(urls)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
    sidebarItem.minimumThickness = 160
    sidebarItem.maximumThickness = 360

    let trackListItem = NSSplitViewItem(contentListWithViewController: trackList)
    trackListItem.minimumThickness = 360

    let inspectorItem = NSSplitViewItem(inspectorWithViewController: inspector)
    inspectorItem.minimumThickness = 280
    inspectorItem.maximumThickness = 480
    inspectorItem.canCollapse = true

    for item in [sidebarItem, trackListItem, inspectorItem] {
      addSplitViewItem(item)
    }
    splitView.autosaveName = "Main"
    super.viewDidLoad()
  }

  /// Shows folders and audio files the user gave, which are kept to be reached again: a
  /// folder in the sidebar, selected; files in the folder of the sidebar that holds them, or
  /// else among the files opened on their own.
  func open(_ urls: [URL]) {
    var folders: [URL] = []
    var files: [URL] = []
    for url in urls.map(\.standardizedFileURL) {
      if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
        folders.append(url)
      } else if Library.fileExtensions.contains(url.pathExtension.lowercased()) {
        files.append(url)
      }
    }
    sources.add(folders + files)
    if let folder = folders.first {
      sidebar.select(.folder(folder))
    } else if let file = files.first {
      let folder = file.deletingLastPathComponent()
      sidebar.select(sources.folder(containing: folder) != nil ? .folder(folder) : .openedFiles)
      trackList.select(files)
    }
  }

  /// Lists the source's files afresh, as they were moved, renamed or trashed.
  @objc private func filesDidChange() {
    trackList.show(trackList.source, reloading: true)
  }

  /// Makes a folder in the folder selected in the sidebar, or the selected file's, whatever has
  /// the focus.
  @objc func newFolder(_ sender: Any?) {
    sidebar.newFolder(sender)
  }
}

extension MainSplitViewController: NSMenuItemValidation {
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(newFolder(_:)): sidebar.selectedFolder != nil
    default: true
    }
  }
}
