//
//  TagField.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import TagLib

/// A tag edited as text, in the track list and the inspector.
enum TagField: String, CaseIterable {
  case title, artist, album, albumArtist, composer, genre, date, originalDate
  case trackNumber, trackCount, discNumber, discCount
  case comment, lyrics

  var label: String {
    switch self {
    case .title: "Title"
    case .artist: "Artist"
    case .album: "Album"
    case .albumArtist: "Album Artist"
    case .composer: "Composer"
    case .genre: "Genre"
    case .date: "Release Date"
    case .originalDate: "Original Date"
    case .trackNumber: "Track"
    case .trackCount: "Tracks"
    case .discNumber: "Disc"
    case .discCount: "Discs"
    case .comment: "Comment"
    case .lyrics: "Lyrics"
    }
  }

  /// The key it's stored under, for fields that are text.
  private var key: String? {
    switch self {
    case .title: "TITLE"
    case .artist: "ARTIST"
    case .album: "ALBUM"
    case .albumArtist: "ALBUMARTIST"
    case .composer: "COMPOSER"
    case .genre: "GENRE"
    case .date: "DATE"
    case .originalDate: "ORIGINALDATE"
    case .comment: "COMMENT"
    case .lyrics: "LYRICS"
    case .trackNumber, .trackCount, .discNumber, .discCount: nil
    }
  }

  var isNumeric: Bool { key == nil }

  /// Whether it's a date, which is written as `TagDate` has it.
  var isDate: Bool { self == .date || self == .originalDate }

  /// The text to write for what was typed: a date as `TagDate` writes it, or nothing to
  /// remove one; nil where a date field's text is no date, which isn't written.
  func normalized(_ text: String) -> String? {
    guard isDate, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return text }
    return TagDate(text)?.text
  }

  /// The keys the fields edit, and the totals the positions may be kept in.
  static let keys: Set<String> = Set(allCases.compactMap(\.key)).union([
    "TRACKNUMBER", "TRACKTOTAL", "TOTALTRACKS", "DISCNUMBER", "DISCTOTAL", "TOTALDISCS",
  ])

  /// The field's text: a key's values, separated by semicolons where it has several; a date
  /// as `TagDate` writes it, rather than as the tags read, which may differ only in form, as
  /// ID3v2 dates read with a space before their time.
  func value(in tags: Tags) -> String {
    let number: Int? =
      switch self {
      case .trackNumber: tags.trackNumber
      case .trackCount: tags.trackCount
      case .discNumber: tags.discNumber
      case .discCount: tags.discCount
      default: nil
      }
    guard let key else { return number.map(String.init) ?? "" }
    let text = tags[key].joined(separator: "; ")
    return isDate ? TagDate(text)?.text ?? text : text
  }

  /// Sets the field from text, which, empty, removes it; numbers that aren't remove it too.
  func set(_ text: String, in tags: inout Tags) {
    guard let key else {
      let number = Int(text.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
      switch self {
      case .trackNumber: tags.trackNumber = number
      case .trackCount: tags.trackCount = number
      case .discNumber: tags.discNumber = number
      case .discCount: tags.discCount = number
      default: break
      }
      return
    }
    tags[key] = text.isEmpty ? [] : [text]
  }
}

/// A track or disc position, shown as `3/12`, and edited so.
enum Position {
  case track, disc

  private var fields: (number: TagField, count: TagField) {
    switch self {
    case .track: (.trackNumber, .trackCount)
    case .disc: (.discNumber, .discCount)
    }
  }

  func value(in tags: Tags) -> String {
    let number = fields.number.value(in: tags)
    let count = fields.count.value(in: tags)
    return count.isEmpty ? number : "\(number)/\(count)"
  }

  /// Sets the position from text such as `3/12` or `3`; without a count, it keeps the one
  /// the tags have.
  func set(_ text: String, in tags: inout Tags) {
    let parts = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    fields.number.set(parts.first.map(String.init) ?? "", in: &tags)
    if parts.count > 1 {
      fields.count.set(String(parts[1]), in: &tags)
    }
  }
}
