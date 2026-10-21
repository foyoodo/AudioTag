//
//  ArtworkThumbnails.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit
import ImageIO
import TagLib

/// Small images of tracks' artwork, for the sidebar's files. Each is made off the main actor,
/// from the artwork as edited, or else as read afresh from the file, whose pictures aren't
/// kept, and is made again once the artwork is edited.
@MainActor
final class ArtworkThumbnails {
  private final class Entry {
    let revision: Int
    let image: NSImage?

    init(revision: Int, image: NSImage?) {
      self.revision = revision
      self.image = image
    }
  }

  /// Image data that crosses to the thread that scales it down.
  private struct Thumbnail: @unchecked Sendable {
    let image: CGImage
  }

  /// Posted with a track whose thumbnail was made, under `trackKey`.
  static let didMakeNotification = Notification.Name("ArtworkThumbnailsDidMake")
  static let trackKey = "track"

  private let pointSize: CGFloat
  private let cache = NSCache<Track, Entry>()
  /// Those waiting to be made, the latest asked for last, to be made first.
  private var queue: [Track] = []
  private var making: Set<Track> = []
  private let concurrency = 4

  init(pointSize: CGFloat) {
    self.pointSize = pointSize
    cache.countLimit = 2000
  }

  /// The thumbnail of the track's artwork; nil where it has none, or while it's being made, the
  /// one before it, if any, standing in for it.
  func image(for track: Track) -> NSImage? {
    let entry = cache.object(forKey: track)
    guard entry?.revision != track.artworkRevision else { return entry?.image }
    if !making.contains(track) {
      queue.removeAll { $0 === track }
      queue.append(track)
      makeNext()
    }
    return entry?.image
  }

  private func makeNext() {
    while making.count < concurrency, let track = queue.popLast() {
      making.insert(track)
      let revision = track.artworkRevision
      // The pictures as edited, where they're read; otherwise the file's.
      let data = track.pictures.map { _ in track.artwork?.data }
      let file = AudioFile(url: track.url)
      let pixelSize = Int(pointSize * (NSScreen.main?.backingScaleFactor ?? 2))
      Task {
        let thumbnail = await Self.thumbnail(of: data, or: file, pixelSize: pixelSize)
        making.remove(track)
        let image = thumbnail.map { NSImage(cgImage: $0.image, size: .zero) }
        cache.setObject(Entry(revision: revision, image: image), forKey: track)
        NotificationCenter.default.post(
          name: Self.didMakeNotification, object: self, userInfo: [Self.trackKey: track])
        makeNext()
      }
    }
  }

  /// A thumbnail of `data`, where it's given, else of the artwork of `file`, at most
  /// `pixelSize` on its longer side.
  @concurrent
  private nonisolated static func thumbnail(
    of data: Data??, or file: AudioFile, pixelSize: Int
  ) async -> Thumbnail? {
    guard
      let data = data ?? (try? file.read(.pictures))?.artwork?.data,
      let source = CGImageSourceCreateWithData(data as CFData, nil)
    else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: pixelSize,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(
      Thumbnail.init)
  }
}
