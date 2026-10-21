//
//  Library.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import Foundation
import TagLib

/// The tracks of the folders browsed, kept once read so that their edits outlast leaving the
/// folder, and every change made to them.
@MainActor
final class Library {
  /// Posted with the tracks that changed under `tracksKey`.
  static let tracksDidChangeNotification = Notification.Name("LibraryTracksDidChange")
  static let tracksKey = "tracks"

  /// File name extensions of the formats TagLib reads.
  nonisolated static let fileExtensions = AudioFile.supportedFileExtensions

  /// What's read of a file to list it: all but its pictures, which can be large.
  private nonisolated static let listedParts: ReadOptions = [.audioProperties, .nativeTags]

  private var tracks: [URL: Track] = [:]

  nonisolated init() {}

  var modifiedTracks: [Track] {
    tracks.values.filter(\.isModified).sorted {
      $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
    }
  }

  var hasModifiedTracks: Bool {
    tracks.values.contains { $0.isModified }
  }

  func track(for url: URL) -> Track {
    let url = url.standardizedFileURL
    if let track = tracks[url] { return track }
    let track = Track(url: url)
    tracks[url] = track
    return track
  }

  /// The tracks known of the files at, or in, the URLs.
  func knownTracks(at urls: [URL]) -> [Track] {
    tracks.filter { url, _ in urls.contains { Self.url(url, isAtOrIn: $0) } }.map(\.value)
  }

  /// Follows files and folders moved or renamed: the tracks of the files at, or in, each
  /// `from` are those of the `to` it's paired with, edits and all.
  func filesDidMove(_ moves: [(from: URL, to: URL)]) {
    var moved: [Track] = []
    for (from, to) in moves {
      let (from, to) = (from.standardizedFileURL, to.standardizedFileURL)
      for (url, track) in tracks where Self.url(url, isAtOrIn: from) {
        let destination = URL(filePath: to.path + url.path.dropFirst(from.path.count))
          .standardizedFileURL
        tracks[url] = nil
        track.didMove(to: destination)
        tracks[destination] = track
        moved.append(track)
      }
    }
    announce(moved)
  }

  /// Lets go of the tracks of the files at, or in, the URLs, which are gone, edits and all.
  func forget(_ urls: [URL]) {
    let urls = urls.map(\.standardizedFileURL)
    let gone = tracks.keys.filter { url in urls.contains { Self.url(url, isAtOrIn: $0) } }
    let forgotten = gone.compactMap { tracks.removeValue(forKey: $0) }
    announce(forgotten)
  }

  private static func url(_ url: URL, isAtOrIn other: URL) -> Bool {
    url.path == other.path || url.path.hasPrefix(other.path + "/")
  }

  /// The tracks of the audio files in `folder` and its subfolders, by path, read or not.
  func tracks(in folder: URL) async -> [Track] {
    await Self.audioFiles(in: folder).map(track(for:))
  }

  /// Reads the tracks that aren't edited, from disk afresh, announcing them in batches as they
  /// are read and telling `progress` how many have been.
  func read(_ tracks: [Track], progress: (Int) -> Void = { _ in }) async {
    var changed: [Track] = []
    var lastAnnouncement = ContinuousClock.now
    var count = 0
    let read = { @Sendable (file: AudioFile) throws(AudioFileError) in
      (
        try file.read(Library.listedParts),
        FileManager.default.isWritableFile(atPath: file.url.path)
      )
    }
    await perform(on: tracks.filter { !$0.isModified }, read) { track, result in
      switch result {
      case .success((let metadata, let isWritable)): track.didRead(metadata, isWritable: isWritable)
      case .failure(let error): track.didFailToRead(error)
      }
      changed.append(track)
      count += 1
      if ContinuousClock.now - lastAnnouncement > .milliseconds(150) {
        announce(changed)
        changed.removeAll()
        lastAnnouncement = .now
        progress(count)
      }
    }
    announce(changed)
    progress(count)
  }

  /// Reads the pictures of those of the tracks whose pictures haven't been.
  func readPictures(of tracks: [Track]) async {
    let unread = tracks.filter { $0.isRead && $0.pictures == nil }
    guard !unread.isEmpty else { return }
    let read = { @Sendable (file: AudioFile) throws(AudioFileError) in
      try file.read(.pictures).pictures
    }
    await perform(on: unread, read) { track, result in
      track.didReadPictures((try? result.get()) ?? [])
    }
    announce(unread)
  }

  /// Lets go of the pictures of every track but `tracks`, unless they're edited.
  func unloadPictures(except tracks: [Track]) {
    let kept = Set(tracks)
    for track in self.tracks.values where !kept.contains(track) {
      track.unloadPictures()
    }
  }

  /// Changes those of the tracks that can be edited.
  func edit(_ tracks: [Track], _ change: (Track) -> Void) {
    let tracks = tracks.filter(\.isEditable)
    guard !tracks.isEmpty else { return }
    tracks.forEach(change)
    announce(tracks)
  }

  /// Replaces the tracks' pictures, reading them first, each in turn with what `change` makes
  /// of its own.
  func editPictures(of tracks: [Track], _ change: @escaping ([Picture]) -> [Picture]) async {
    await readPictures(of: tracks)
    edit(tracks) { $0.setPictures(change($0.pictures ?? [])) }
  }

  /// Replaces the tracks' artwork, reading their pictures first; nil removes it.
  func setArtwork(_ picture: Picture?, of tracks: [Track]) async {
    await readPictures(of: tracks)
    edit(tracks) { $0.setArtwork(picture) }
  }

  func revert(_ tracks: [Track]) {
    let tracks = tracks.filter(\.isModified)
    for track in tracks { track.revert() }
    announce(tracks)
  }

  /// Saves those of the tracks that are edited, returning those that couldn't be, with why;
  /// `skippingUnsupportedTags`, the tags and pictures a file's format can't hold are left out
  /// of it, rather than it not being saved.
  func save(
    _ tracks: [Track], skippingUnsupportedTags: Bool = false
  ) async -> [(track: Track, error: AudioFileError)] {
    struct Edits: Sendable {
      var tags: Tags?
      var pictures: [Picture]?
      var options: WriteOptions
    }
    let tracks = tracks.filter(\.isModified)
    var edits: [Track: Edits] = [:]
    for track in tracks {
      var options = track.options
      options.skipsUnsupportedTags = skippingUnsupportedTags
      edits[track] = Edits(
        tags: track.tags != track.metadata?.tags ? track.tags : nil,
        pictures: track.picturesAreEdited ? track.pictures : nil,
        options: options)
    }
    var failures: [(track: Track, error: AudioFileError)] = []
    await perform(on: tracks.map { ($0, edits[$0]!) }) { file, edits throws(AudioFileError) in
      try file.write(tags: edits.tags, pictures: edits.pictures, options: edits.options)
      return try file.read(Library.listedParts)
    } then: { track, result in
      switch result {
      case .success(let metadata): track.didSave(metadata)
      case .failure(let error): failures.append((track, error))
      }
    }
    announce(tracks)
    return failures
  }

  private func announce(_ tracks: [Track]) {
    guard !tracks.isEmpty else { return }
    NotificationCenter.default.post(
      name: Self.tracksDidChangeNotification, object: self, userInfo: [Self.tracksKey: tracks])
  }

  private func perform<Value: Sendable>(
    on tracks: [Track], _ work: @escaping @Sendable (AudioFile) throws(AudioFileError) -> Value,
    then body: (Track, Result<Value, AudioFileError>) -> Void
  ) async {
    await perform(
      on: tracks.map { ($0, ()) }, { file, _ throws(AudioFileError) in try work(file) }, then: body)
  }

  /// Does `work` on the tracks' files off the main actor, a few at a time, handing each result
  /// to `body` as it comes; stops starting more once cancelled.
  private func perform<Input: Sendable, Value: Sendable>(
    on inputs: [(Track, Input)],
    _ work: @escaping @Sendable (AudioFile, Input) throws(AudioFileError) -> Value,
    then body: (Track, Result<Value, AudioFileError>) -> Void
  ) async {
    // Where the files are now, which a move later doesn't change for these.
    let inputs = inputs.map { track, input in (track, AudioFile(url: track.url), input) }
    await withTaskGroup(of: (Track, Result<Value, AudioFileError>).self) { group in
      var next = 0
      func start() {
        let (track, file, input) = inputs[next]
        next += 1
        group.addTask {
          (track, Result { () throws(AudioFileError) in try work(file, input) })
        }
      }
      while next < min(inputs.count, ProcessInfo.processInfo.activeProcessorCount) {
        start()
      }
      while let (track, result) = await group.next() {
        body(track, result)
        if next < inputs.count, !Task.isCancelled { start() }
      }
    }
  }

  /// The audio files in `folder` and its subfolders, by path.
  @concurrent
  private nonisolated static func audioFiles(in folder: URL) async -> [URL] {
    audioFilesSynchronously(in: folder)
  }

  private nonisolated static func audioFilesSynchronously(in folder: URL) -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: folder, includingPropertiesForKeys: [],
        options: [.skipsHiddenFiles, .skipsPackageDescendants])
    else { return [] }
    var urls: [URL] = []
    for case let url as URL in enumerator
    where fileExtensions.contains(url.pathExtension.lowercased()) {
      urls.append(url.standardizedFileURL)
    }
    return urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
  }
}

extension Track: Hashable {
  nonisolated static func == (lhs: Track, rhs: Track) -> Bool {
    lhs === rhs
  }

  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

extension AudioFileError {
  var message: String {
    switch self {
    case .fileNotFound: "The file can’t be found. It may have been moved or deleted."
    case .unreadable: "The file can’t be opened. You may not have permission to read it."
    case .unsupportedFormat: "The file isn’t in a format AudioTag reads."
    case .readOnly: "The file can’t be changed. It may be locked, or on a read-only volume."
    case .unsupportedTags(let keys):
      "Its format can’t hold \(keys.count == 1 ? "the tag" : "the tags") \(ListFormatter.localizedString(byJoining: keys))."
    case .unsupportedPictures: "Its format can’t hold artwork."
    case .saveFailed: "The file couldn’t be saved."
    }
  }

  /// Whether saving without what the file's format can't hold would get it saved.
  var isUnsupportedContent: Bool {
    switch self {
    case .unsupportedTags, .unsupportedPictures: true
    default: false
    }
  }
}
