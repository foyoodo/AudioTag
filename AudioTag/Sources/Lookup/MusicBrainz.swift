//
//  MusicBrainz.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2026.
//

import Foundation

/// MusicBrainz recording search, and cover art from the Cover Art Archive for a release MBID.
struct MusicBrainzProvider: MetadataProvider {
  let id = "musicbrainz"
  let name = "MusicBrainz"
  var client: LookupClient

  func search(_ query: MetadataQuery) async throws -> [MetadataCandidate] {
    let url = try MusicBrainz.recordingSearchURL(query: query)
    let data = try await client.data(from: url)
    return try MusicBrainz.recordings(from: data, query: query)
  }
}

enum MusicBrainz {
  /// A Lucene query of the filled-in fields, with quotes escaped.
  static func luceneQuery(_ query: MetadataQuery) -> String {
    func clause(_ field: String, _ text: String) -> String? {
      let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return nil }
      return "\(field):\"\(escape(text))\""
    }
    return [
      clause("recording", query.title), clause("artist", query.artist),
      clause("release", query.album),
    ].compactMap(\.self).joined(separator: " AND ")
  }

  static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
  }

  static func recordingSearchURL(query: MetadataQuery, limit: Int = 25) throws -> URL {
    let lucene = luceneQuery(query)
    guard !lucene.isEmpty else { throw MetadataLookupError.emptyQuery }
    var components = URLComponents(string: "https://musicbrainz.org/ws/2/recording")!
    components.queryItems = [
      URLQueryItem(name: "query", value: lucene),
      URLQueryItem(name: "fmt", value: "json"),
      URLQueryItem(name: "limit", value: String(limit)),
    ]
    guard let url = components.url else { throw MetadataLookupError.emptyQuery }
    return url
  }

  static func recordings(
    from data: Data,
    query: MetadataQuery = MetadataQuery(title: "", artist: "", album: "")
  ) throws -> [MetadataCandidate] {
    let response: SearchResponse
    do {
      response = try JSONDecoder().decode(SearchResponse.self, from: data)
    } catch {
      throw MetadataLookupError.decoding
    }
    return (response.recordings ?? []).compactMap { $0.candidate(matching: query) }
  }

  struct SearchResponse: Decodable, Sendable {
    var recordings: [Recording]?
  }

  struct Recording: Decodable, Sendable {
    var id: String
    var title: String
    var length: Int?
    var score: JSONStringOrNumber?
    var artistCredit: [NameCredit]?
    var firstReleaseDate: String?
    var releases: [Release]?
    var tags: [Tag]?

    enum CodingKeys: String, CodingKey {
      case id, title, length, score, releases, tags
      case artistCredit = "artist-credit"
      case firstReleaseDate = "first-release-date"
    }

    func candidate(matching query: MetadataQuery) -> MetadataCandidate? {
      let artist = Self.creditedName(artistCredit)
      let release = Self.preferredRelease(releases, album: query.album)
      let media = release?.media?.first
    let track = media?.track?.first
    let trackNumber =
      track?.number?.intValue ?? Int(track?.number?.value.filter(\.isNumber) ?? "")
      let albumArtist = Self.creditedName(release?.artistCredit)
      let date = release?.date ?? firstReleaseDate ?? ""
      let genre = tags?.max { $0.count ?? 0 < $1.count ?? 0 }?.name ?? ""
      let releaseMBID = release?.id
      return MetadataCandidate(
        id: "mb:\(id):\(releaseMBID ?? "")",
        title: title,
        artist: artist,
        album: release?.title ?? "",
        albumArtist: albumArtist.isEmpty || albumArtist == artist ? artist : albumArtist,
        date: date,
        trackNumber: trackNumber,
        trackCount: release?.trackCount ?? media?.trackCount,
        discNumber: media?.position,
        genre: genre,
        duration: length.map { TimeInterval($0) / 1000 },
        source: .musicBrainz,
        recordingMBID: id,
        releaseMBID: releaseMBID,
        score: score?.intValue,
        thumbnailURL: releaseMBID.map {
          CoverArtArchive.imageURL(releaseMBID: $0, size: .thumbnail)
        },
        imageURL: releaseMBID.map { CoverArtArchive.imageURL(releaseMBID: $0, size: .full) })
    }

    private static func creditedName(_ credits: [NameCredit]?) -> String {
      (credits ?? []).reduce("") { $0 + $1.creditedName + ($1.joinphrase ?? "") }
        .trimmingCharacters(in: .whitespaces)
    }

    /// The release whose title matches the album searched, an Official one, or the first.
    private static func preferredRelease(_ releases: [Release]?, album: String) -> Release? {
      guard let releases, !releases.isEmpty else { return nil }
      let album = album.trimmingCharacters(in: .whitespacesAndNewlines)
      if !album.isEmpty,
        let match = releases.first(where: {
          $0.title.localizedCaseInsensitiveCompare(album) == .orderedSame
        })
      {
        return match
      }
      return
        releases.first { $0.status?.localizedCaseInsensitiveCompare("Official") == .orderedSame }
        ?? releases.first
    }
  }

  struct NameCredit: Decodable, Sendable {
    var name: String?
    var joinphrase: String?
    var artist: Artist?

    var creditedName: String { name ?? artist?.name ?? "" }
  }

  struct Artist: Decodable, Sendable {
    var id: String?
    var name: String?
  }

  struct Release: Decodable, Sendable {
    var id: String
    var title: String
    var status: String?
    var date: String?
    var trackCount: Int?
    var artistCredit: [NameCredit]?
    var media: [Medium]?

    enum CodingKeys: String, CodingKey {
      case id, title, status, date, media
      case trackCount = "track-count"
      case artistCredit = "artist-credit"
    }
  }

  struct Medium: Decodable, Sendable {
    var position: Int?
    var trackCount: Int?
    var track: [TrackRef]?

    enum CodingKeys: String, CodingKey {
      case position, track
      case trackCount = "track-count"
    }
  }

  struct TrackRef: Decodable, Sendable {
    var number: JSONStringOrNumber?
    var title: String?
    var length: Int?
  }

  struct Tag: Decodable, Sendable {
    var name: String?
    var count: Int?
  }
}

/// Cover images at coverartarchive.org, looked up by MusicBrainz release MBID.
enum CoverArtArchive {
  static func imageURL(releaseMBID: String, size: CoverArtSize) -> URL {
    let suffix =
      switch size {
      case .thumbnail: "front-250"
      case .full: "front-500"
      }
    return URL(string: "https://coverartarchive.org/release/\(releaseMBID)/\(suffix)")!
  }

  /// The front image, from a Cover Art Archive JSON listing.
  static func frontImageURL(from data: Data, size: CoverArtSize) throws -> URL? {
    let listing: Listing
    do {
      listing = try JSONDecoder().decode(Listing.self, from: data)
    } catch {
      throw MetadataLookupError.decoding
    }
    let image = listing.images.first { $0.front == true } ?? listing.images.first
    let raw =
      switch size {
      case .thumbnail: image?.thumbnails?["250"] ?? image?.thumbnails?["small"] ?? image?.image
      case .full: image?.image ?? image?.thumbnails?["1200"] ?? image?.thumbnails?["500"]
      }
    guard let raw, var components = URLComponents(string: raw) else { return nil }
    if components.scheme == "http" { components.scheme = "https" }
    return components.url
  }

  struct Listing: Decodable, Sendable {
    var images: [Image]
  }

  struct Image: Decodable, Sendable {
    var front: Bool?
    var image: String?
    var thumbnails: [String: String]?
  }
}

struct CoverArtArchiveProvider: CoverArtProvider {
  var client: LookupClient

  func image(for candidate: MetadataCandidate, size: CoverArtSize) async throws -> Data? {
    if let url = size == .thumbnail ? candidate.thumbnailURL : candidate.imageURL {
      if let data = try await client.data(from: url, acceptNotFound: true) { return data }
    }
    guard let mbid = candidate.releaseMBID else { return nil }
    return try await client.data(
      from: CoverArtArchive.imageURL(releaseMBID: mbid, size: size), acceptNotFound: true)
  }
}
