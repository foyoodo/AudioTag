//
//  MetadataLookup.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2026.
//

import Foundation
import TagLib

/// How AudioTag identifies itself to MusicBrainz and the Cover Art Archive, which require a
/// real User-Agent rather than a generic client string.
enum AudioTagIdentity {
  static let projectURL = "https://github.com/foyoodo/AudioTag"

  static func userAgent(version: String) -> String {
    "AudioTag/\(version) ( \(projectURL) )"
  }

  static var userAgent: String {
    userAgent(version: bundleVersion)
  }

  static var bundleVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"
  }
}

/// A source of online metadata. MusicBrainz and iTunes ship in this version; AcoustID
/// fingerprinting, Discogs and lyrics can be added later by conforming to the same protocol.
protocol MetadataProvider: Sendable {
  /// A stable id, such as `musicbrainz` or `itunes`.
  var id: String { get }
  var name: String { get }
  func search(_ query: MetadataQuery) async throws -> [MetadataCandidate]
}

/// Cover art for a candidate, from the Cover Art Archive or another image host.
protocol CoverArtProvider: Sendable {
  func image(for candidate: MetadataCandidate, size: CoverArtSize) async throws -> Data?
}

enum CoverArtSize: Sendable {
  /// A list thumbnail, about 250 pixels.
  case thumbnail
  /// The image written to the file, about 500–1200 pixels.
  case full
}

/// Cover art fetched for a candidate, and where it came from.
struct LookupImage: Equatable, Sendable {
  var data: Data
  var origin: Origin

  enum Origin: Equatable, Sendable {
    /// The candidate’s own cover, from the Cover Art Archive or its iTunes artwork URL.
    case candidate
    /// iTunes search because the candidate had no cover; it may be a different album.
    case iTunesFallback

    var artworkLabel: String {
      switch self {
      case .candidate: "Artwork"
      case .iTunesFallback: "Artwork (from iTunes, may not match)"
      }
    }

    /// Fallback art is offered but not applied unless the user checks it.
    var isArtworkPreChecked: Bool { self == .candidate }
  }
}

/// Artist, album and title as searched, which the user can edit before searching.
struct MetadataQuery: Equatable, Sendable {
  var title: String
  var artist: String
  var album: String

  var isEmpty: Bool {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// The tags of the track, or, where those are empty, what can be read from its file name.
  @MainActor
  static func prefill(for track: Track) -> MetadataQuery {
    let title = TagField.title.value(in: track.tags)
    let artist = TagField.artist.value(in: track.tags)
    let album = TagField.album.value(in: track.tags)
    if title.isEmpty && artist.isEmpty && album.isEmpty {
      return from(fileName: track.name)
    }
    return MetadataQuery(title: title, artist: artist, album: album)
  }

  /// Reads a file name such as `01 Artist - Title.mp3` or `Artist - Album - Title.flac`.
  static func from(fileName: String) -> MetadataQuery {
    var base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    if let match = base.prefixMatch(of: /^\d{1,3}(?:\s*[.\-)]\s*|\s+)/) {
      base = String(base[match.range.upperBound...])
    }
    let parts = base.split(separator: " - ", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    switch parts.count {
    case 0:
      return MetadataQuery(title: "", artist: "", album: "")
    case 1:
      return MetadataQuery(title: parts[0], artist: "", album: "")
    case 2:
      return MetadataQuery(title: parts[1], artist: parts[0], album: "")
    default:
      return MetadataQuery(
        title: parts.dropFirst(2).joined(separator: " - "), artist: parts[0], album: parts[1])
    }
  }
}

/// A recording a provider offered, to pick from and preview.
struct MetadataCandidate: Equatable, Identifiable, Sendable {
  var id: String
  var title: String
  var artist: String
  var album: String
  var albumArtist: String
  var date: String
  var trackNumber: Int? = nil
  var trackCount: Int? = nil
  var discNumber: Int? = nil
  var genre: String
  var duration: TimeInterval? = nil
  var source: Source
  var recordingMBID: String? = nil
  var releaseMBID: String? = nil
  var score: Int? = nil
  /// A small image, where the provider already has a URL for one.
  var thumbnailURL: URL? = nil
  /// The image to write, where the provider already has a URL for one.
  var imageURL: URL? = nil

  enum Source: String, Equatable, Hashable, Sendable {
    case musicBrainz
    case iTunes

    var name: String {
      switch self {
      case .musicBrainz: "MusicBrainz"
      case .iTunes: "iTunes"
      }
    }
  }

  func value(for field: MetadataField) -> String {
    switch field {
    case .title: title
    case .artist: artist
    case .album: album
    case .albumArtist: albumArtist
    case .date: date
    case .trackNumber: trackNumber.map(String.init) ?? ""
    case .trackCount: trackCount.map(String.init) ?? ""
    case .genre: genre
    }
  }
}

/// A tag the lookup can apply, other than the artwork, which is chosen on its own.
enum MetadataField: String, CaseIterable, Hashable, Sendable {
  case title, artist, album, albumArtist, date, trackNumber, trackCount, genre

  var label: String {
    switch self {
    case .title: "Title"
    case .artist: "Artist"
    case .album: "Album"
    case .albumArtist: "Album Artist"
    case .date: "Release Date"
    case .trackNumber: "Track"
    case .trackCount: "Tracks"
    case .genre: "Genre"
    }
  }

  var tagField: TagField {
    switch self {
    case .title: .title
    case .artist: .artist
    case .album: .album
    case .albumArtist: .albumArtist
    case .date: .date
    case .trackNumber: .trackNumber
    case .trackCount: .trackCount
    case .genre: .genre
    }
  }
}

/// One field as it is now, and as the candidate has it.
struct MetadataFieldChange: Equatable, Identifiable, Sendable {
  var field: MetadataField
  var current: String
  var proposed: String

  var id: MetadataField { field }

  /// Whether applying it would change the file: it has a value, and that value differs.
  var wouldChange: Bool {
    !proposed.isEmpty && proposed != current
  }
}

enum MetadataLookupError: Error, Equatable, Sendable {
  case emptyQuery
  case offline
  case cancelled
  case httpStatus(Int)
  case decoding
  case unreachable

  var message: String {
    switch self {
    case .emptyQuery:
      "Enter a title, artist or album to search."
    case .offline:
      "AudioTag can’t reach the network. Connect and try again."
    case .cancelled:
      "The lookup was cancelled."
    case .httpStatus(503):
      "The server is busy. Wait a moment and try again."
    case .httpStatus(let code):
      "The server returned an error (\(code))."
    case .decoding:
      "The response from the server couldn’t be read."
    case .unreachable:
      "AudioTag can’t reach the server. Try again in a moment."
    }
  }
}

enum MetadataLookup {
  /// The fields that would change if the candidate were applied, hiding those it doesn’t have.
  @MainActor
  static func changes(for track: Track, candidate: MetadataCandidate) -> [MetadataFieldChange] {
    changes(current: currentValues(for: track), candidate: candidate)
  }

  static func changes(
    current: [MetadataField: String], candidate: MetadataCandidate
  ) -> [MetadataFieldChange] {
    MetadataField.allCases.compactMap { field in
      let proposed = candidate.value(for: field)
      guard !proposed.isEmpty else { return nil }
      return MetadataFieldChange(
        field: field, current: current[field] ?? "", proposed: proposed)
    }
  }

  /// Whether the preview should check this field. MusicBrainz genres are folksonomy tags,
  /// so Genre is only pre-checked when the track has none.
  static func isCheckedByDefault(
    _ change: MetadataFieldChange, source: MetadataCandidate.Source
  ) -> Bool {
    if change.field == .genre, source == .musicBrainz {
      return change.current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && change.wouldChange
    }
    return change.wouldChange
  }

  @MainActor
  static func currentValues(for track: Track) -> [MetadataField: String] {
    Dictionary(
      uniqueKeysWithValues: MetadataField.allCases.map {
        ($0, $0.tagField.value(in: track.tags))
      })
  }

  /// Applies the chosen fields to the track in memory, through `Library`, so they are saved
  /// with File › Save as any other edit is. Nothing is written to the file here.
  @MainActor
  static func apply(
    _ changes: [MetadataFieldChange], artwork: Picture?, to track: Track, library: Library
  ) async {
    if !changes.isEmpty {
      library.edit([track]) { track in
        for change in changes {
          change.field.tagField.set(change.proposed, in: &track.tags)
        }
      }
    }
    if let artwork {
      await library.setArtwork(artwork, of: [track])
    }
  }
}

/// A string or number as JSON may give either, as MusicBrainz scores and track numbers do.
struct JSONStringOrNumber: Decodable, Sendable {
  var value: String

  var intValue: Int? { Int(value) }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let string = try? container.decode(String.self) {
      value = string
    } else if let int = try? container.decode(Int.self) {
      value = String(int)
    } else if let double = try? container.decode(Double.self) {
      value = String(Int(double))
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Expected a string or number.")
    }
  }
}
