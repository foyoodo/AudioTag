//
//  Track.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import Foundation
import TagLib

/// An audio file in the library: its metadata as read from disk, and the edits to it that
/// haven't been saved. `Library` makes every change to it.
@MainActor
final class Track {
  /// Where the file is, which follows it as it's moved or renamed.
  private(set) var url: URL

  /// As last read from disk, without pictures; nil until it has been read.
  private(set) var metadata: AudioMetadata?
  /// Why the file couldn't be read, where it couldn't.
  private(set) var readError: AudioFileError?
  /// False where the file can be read but not written: it's locked, on a read-only volume, or
  /// not the user's to change.
  private(set) var isWritable = true

  /// The tags as edited.
  var tags = Tags()
  /// The pictures as edited; nil until they have been read, since they can be large.
  private(set) var pictures: [Picture]?
  private(set) var picturesAreEdited = false
  /// Changes whenever the pictures are edited or reverted, which a thumbnail of the artwork is
  /// made again for.
  private(set) var artworkRevision = 0
  /// How the file is saved, as edited.
  var options = WriteOptions()

  init(url: URL) {
    self.url = url
  }

  var name: String { url.lastPathComponent }

  var isRead: Bool { metadata != nil }

  /// Whether its tags can be edited: it has been read, and can be saved.
  var isEditable: Bool { isRead && isWritable }

  var isModified: Bool {
    guard let metadata else { return false }
    return tags != metadata.tags || picturesAreEdited || options != defaultOptions
  }

  /// The options a file is saved with when nothing about them has been edited: with the tag
  /// formats it has, and its ID3v2 tag in the version it's in.
  var defaultOptions: WriteOptions {
    WriteOptions(id3v2Version: metadata?.id3v2Version == 3 ? .v3 : .v4)
  }

  /// The tag formats the file will hold once saved.
  var tagFormats: Set<TagFormat> {
    get { options.tagFormats ?? keptTagFormats }
    set { options.tagFormats = newValue == keptTagFormats ? nil : newValue }
  }

  /// The tag formats a file is saved with when they aren't edited: those it has, and its
  /// format's first.
  private var keptTagFormats: Set<TagFormat> {
    guard let metadata else { return [] }
    return Set(metadata.tagFormats + metadata.format.tagFormats.prefix(1))
  }

  /// Whether the file will be saved with an ID3v2.3 tag, which keeps less of a date.
  var writesID3v23: Bool {
    tagFormats.contains(.id3v2) && options.id3v2Version == .v3
  }

  /// The front cover, or the first picture where none is marked as one.
  var artwork: Picture? {
    pictures.flatMap { $0.first { $0.kind == .frontCover } ?? $0.first }
  }

  func didRead(_ metadata: AudioMetadata, isWritable: Bool) {
    self.metadata = metadata
    self.isWritable = isWritable
    readError = nil
    tags = metadata.tags
    options = defaultOptions
    if !picturesAreEdited { pictures = nil }
  }

  func didFailToRead(_ error: AudioFileError) {
    metadata = nil
    readError = error
  }

  func didReadPictures(_ pictures: [Picture]) {
    guard !picturesAreEdited else { return }
    self.pictures = pictures
  }

  /// Replaces every picture. The pictures must have been read.
  func setPictures(_ pictures: [Picture]) {
    self.pictures = pictures
    picturesAreEdited = true
    artworkRevision += 1
  }

  /// Replaces the artwork, keeping the other pictures; nil removes it. The pictures must have
  /// been read.
  func setArtwork(_ picture: Picture?) {
    var pictures = pictures ?? []
    if let artwork, let index = pictures.firstIndex(of: artwork) {
      pictures.remove(at: index)
    }
    if let picture {
      pictures.insert(picture, at: 0)
    }
    setPictures(pictures)
  }

  func revert() {
    guard let metadata else { return }
    tags = metadata.tags
    options = defaultOptions
    if picturesAreEdited {
      pictures = nil
      picturesAreEdited = false
      artworkRevision += 1
    }
  }

  /// Lets go of the pictures, unless they're edited, to be read again when needed.
  func unloadPictures() {
    if !picturesAreEdited { pictures = nil }
  }

  func didMove(to url: URL) {
    self.url = url
  }

  func didSave(_ metadata: AudioMetadata) {
    // The pictures are now those on disk.
    let pictures = pictures
    picturesAreEdited = false
    didRead(metadata, isWritable: true)
    self.pictures = pictures
  }
}
