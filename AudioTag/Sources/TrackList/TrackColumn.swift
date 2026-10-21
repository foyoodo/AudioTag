//
//  TrackColumn.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit
import TagLib

/// A column of the track list.
enum TrackColumn: String, CaseIterable {
  // In the order they're shown at first.
  // The release date's is `year`, which kept columns' widths are by.
  case status, track, title, artist, album, albumArtist, composer, year, originalDate, genre,
    disc, comment
  case duration, kind, bitrate, sampleRate, tagFormats, name

  var identifier: NSUserInterfaceItemIdentifier { .init(rawValue) }

  var title: String {
    switch self {
    case .status: ""
    case .name: "File Name"
    case .title: "Title"
    case .artist: "Artist"
    case .album: "Album"
    case .albumArtist: "Album Artist"
    case .composer: "Composer"
    case .genre: "Genre"
    case .year: "Date"
    case .originalDate: "Original Date"
    case .track: "#"
    case .disc: "Disc"
    case .comment: "Comment"
    case .kind: "Kind"
    case .duration: "Time"
    case .bitrate: "Bit Rate"
    case .sampleRate: "Sample Rate"
    case .tagFormats: "Tag Formats"
    }
  }

  /// For the header's menu, which lists the columns.
  var menuTitle: String {
    switch self {
    case .status: "Status"
    case .track: "Track"
    default: title
    }
  }

  var width: CGFloat {
    switch self {
    case .status: 18
    case .name: 220
    case .title, .album: 180
    case .artist, .albumArtist, .composer, .comment: 140
    case .genre, .kind, .tagFormats: 100
    case .track: 52
    case .year, .originalDate: 84
    case .disc, .duration: 52
    case .bitrate, .sampleRate: 76
    }
  }

  var isHiddenByDefault: Bool {
    switch self {
    case .albumArtist, .composer, .comment, .disc, .bitrate, .sampleRate, .tagFormats,
      .originalDate:
      true
    default: false
    }
  }

  var alignment: NSTextAlignment {
    switch self {
    case .year, .track, .disc, .duration, .bitrate, .sampleRate: .right
    default: .natural
    }
  }

  /// Whether it's of less note than the tags, and so shown dimmer.
  var isSecondary: Bool {
    switch self {
    case .track, .duration, .kind, .bitrate, .sampleRate, .tagFormats, .name: true
    default: false
    }
  }

  /// How the column's text is edited, for columns of tags.
  enum Editing {
    case field(TagField)
    case position(Position)
  }

  var editing: Editing? {
    switch self {
    case .title: .field(.title)
    case .artist: .field(.artist)
    case .album: .field(.album)
    case .albumArtist: .field(.albumArtist)
    case .composer: .field(.composer)
    case .genre: .field(.genre)
    case .year: .field(.date)
    case .originalDate: .field(.originalDate)
    case .comment: .field(.comment)
    case .track: .position(.track)
    case .disc: .position(.disc)
    default: nil
    }
  }

  @MainActor
  func text(for track: Track) -> String {
    if let editing {
      switch editing {
      case .field(let field): return field.value(in: track.tags).replacing("\n", with: " ")
      case .position(let position): return position.value(in: track.tags)
      }
    }
    let metadata = track.metadata
    let properties = metadata?.properties
    return switch self {
    case .name: track.name
    case .kind: metadata?.kind ?? ""
    case .duration: properties.map { Format.duration($0.duration) } ?? ""
    // What a format doesn't record is zero, as a module's sample rate is: left blank.
    case .bitrate: properties.flatMap { $0.bitrate > 0 ? Format.bitrate($0.bitrate) : nil } ?? ""
    case .sampleRate:
      properties.flatMap { $0.sampleRate > 0 ? Format.sampleRate($0.sampleRate) : nil } ?? ""
    case .tagFormats: metadata?.tagFormats.map(\.name).joined(separator: ", ") ?? ""
    default: ""
    }
  }

  /// Orders tracks by the column, ascending.
  @MainActor
  func compare(_ lhs: Track, _ rhs: Track) -> ComparisonResult {
    func numbers(_ values: (Track) -> Int?) -> ComparisonResult {
      let (lhs, rhs) = (values(lhs) ?? 0, values(rhs) ?? 0)
      return lhs == rhs ? .orderedSame : lhs < rhs ? .orderedAscending : .orderedDescending
    }
    switch self {
    case .track:
      let byDisc = numbers { $0.tags.discNumber }
      return byDisc != .orderedSame ? byDisc : numbers { $0.tags.trackNumber }
    case .disc: return numbers { $0.tags.discNumber }
    case .year, .originalDate:
      // By date, where it's one; those that aren't, after.
      let field: TagField = self == .year ? .date : .originalDate
      switch (TagDate(field.value(in: lhs.tags)), TagDate(field.value(in: rhs.tags))) {
      case (let lhs?, let rhs?):
        return lhs < rhs ? .orderedAscending : rhs < lhs ? .orderedDescending : .orderedSame
      case (.some, nil): return .orderedAscending
      case (nil, .some): return .orderedDescending
      case (nil, nil): return text(for: lhs).localizedStandardCompare(text(for: rhs))
      }
    case .duration: return numbers { $0.metadata?.properties.map { Int($0.duration * 1000) } }
    case .bitrate: return numbers { $0.metadata?.properties?.bitrate }
    case .sampleRate: return numbers { $0.metadata?.properties?.sampleRate }
    case .status: return numbers { $0.isModified ? 1 : 0 }
    default: return text(for: lhs).localizedStandardCompare(text(for: rhs))
    }
  }
}
