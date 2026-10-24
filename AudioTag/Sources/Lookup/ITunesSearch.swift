//
//  ITunesSearch.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2026.
//

import Foundation

/// The iTunes Search API, used when MusicBrainz has no recordings, and for cover art when the
/// Cover Art Archive has none.
struct ITunesSearchProvider: MetadataProvider {
  let id = "itunes"
  let name = "iTunes"
  var client: LookupClient

  func search(_ query: MetadataQuery) async throws -> [MetadataCandidate] {
    let url = try ITunesSearch.searchURL(query: query)
    let data = try await client.data(from: url)
    return try ITunesSearch.songs(from: data)
  }

  func artwork(matching candidate: MetadataCandidate) async throws -> Data? {
    let query = MetadataQuery(
      title: candidate.title, artist: candidate.artist, album: candidate.album)
    guard let url = try? ITunesSearch.searchURL(query: query, limit: 1) else { return nil }
    let data = try await client.data(from: url)
    guard let song = try ITunesSearch.songs(from: data).first,
      let imageURL = song.imageURL ?? song.thumbnailURL
    else { return nil }
    return try await client.data(from: imageURL, acceptNotFound: true)
  }
}

enum ITunesSearch {
  static func searchURL(query: MetadataQuery, limit: Int = 25) throws -> URL {
    let term = [query.artist, query.album, query.title]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    guard !term.isEmpty else { throw MetadataLookupError.emptyQuery }
    var components = URLComponents(string: "https://itunes.apple.com/search")!
    components.queryItems = [
      URLQueryItem(name: "term", value: term),
      URLQueryItem(name: "media", value: "music"),
      URLQueryItem(name: "entity", value: "song"),
      URLQueryItem(name: "limit", value: String(limit)),
    ]
    guard let url = components.url else { throw MetadataLookupError.emptyQuery }
    return url
  }

  static func songs(from data: Data) throws -> [MetadataCandidate] {
    let response: Response
    do {
      response = try JSONDecoder().decode(Response.self, from: data)
    } catch {
      throw MetadataLookupError.decoding
    }
    return (response.results ?? []).compactMap(\.candidate)
  }

  /// A larger iTunes artwork URL, from the 100-pixel one the search returns.
  static func largerArtworkURL(_ url: URL) -> URL {
    let text = url.absoluteString
      .replacingOccurrences(of: "100x100", with: "600x600")
      .replacingOccurrences(of: "100x100bb", with: "600x600bb")
    return URL(string: text) ?? url
  }

  struct Response: Decodable, Sendable {
    var resultCount: Int?
    var results: [Song]?
  }

  struct Song: Decodable, Sendable {
    var wrapperType: String?
    var kind: String?
    var trackId: Int?
    var trackName: String?
    var artistName: String?
    var collectionName: String?
    var collectionArtistName: String?
    var releaseDate: String?
    var trackNumber: Int?
    var trackCount: Int?
    var discNumber: Int?
    var trackTimeMillis: Int?
    var primaryGenreName: String?
    var artworkUrl100: String?
    var artworkUrl60: String?

    var candidate: MetadataCandidate? {
      guard kind == "song" || wrapperType == "track", let title = trackName else { return nil }
      let thumbnail = (artworkUrl100 ?? artworkUrl60).flatMap(URL.init(string:))
      return MetadataCandidate(
        id: "itunes:\(trackId.map(String.init) ?? title)",
        title: title,
        artist: artistName ?? "",
        album: collectionName ?? "",
        albumArtist: collectionArtistName ?? artistName ?? "",
        date: Self.date(from: releaseDate),
        trackNumber: trackNumber,
        trackCount: trackCount,
        discNumber: discNumber,
        genre: primaryGenreName ?? "",
        duration: trackTimeMillis.map { TimeInterval($0) / 1000 },
        source: .iTunes,
        recordingMBID: nil,
        releaseMBID: nil,
        score: nil,
        thumbnailURL: thumbnail,
        imageURL: thumbnail.map(ITunesSearch.largerArtworkURL))
    }

    /// The calendar day of an iTunes date such as `2016-08-26T12:00:00Z`.
    private static func date(from text: String?) -> String {
      guard let text, !text.isEmpty else { return "" }
      if let tag = TagDate(text) { return tag.text }
      return String(text.prefix(10))
    }
  }
}
