//
//  MetadataLookupService.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2026.
//

import Foundation

/// Searches MusicBrainz, falls back to iTunes when that has no recordings, and loads cover art
/// from the Cover Art Archive, then iTunes, when a candidate has none.
struct MetadataLookupService: Sendable {
  var musicBrainz: any MetadataProvider
  var iTunes: any MetadataProvider
  var coverArt: any CoverArtProvider
  var iTunesArtwork: ITunesSearchProvider

  init(client: LookupClient = LookupClient()) {
    let musicBrainz = MusicBrainzProvider(client: client)
    let iTunes = ITunesSearchProvider(client: client)
    self.init(
      musicBrainz: musicBrainz, iTunes: iTunes, coverArt: CoverArtArchiveProvider(client: client),
      iTunesArtwork: iTunes)
  }

  init(
    musicBrainz: any MetadataProvider, iTunes: any MetadataProvider, coverArt: any CoverArtProvider,
    iTunesArtwork: ITunesSearchProvider
  ) {
    self.musicBrainz = musicBrainz
    self.iTunes = iTunes
    self.coverArt = coverArt
    self.iTunesArtwork = iTunesArtwork
  }

  func search(_ query: MetadataQuery) async throws -> [MetadataCandidate] {
    if query.isEmpty { throw MetadataLookupError.emptyQuery }
    try Task.checkCancellation()
    let recordings = try await musicBrainz.search(query)
    if !recordings.isEmpty { return recordings }
    try Task.checkCancellation()
    return try await iTunes.search(query)
  }

  /// The candidate’s own image, the Cover Art Archive, or iTunes, in that order.
  /// iTunes as a last resort for a MusicBrainz candidate is a fallback and may not match.
  func image(for candidate: MetadataCandidate, size: CoverArtSize) async throws -> LookupImage? {
    try Task.checkCancellation()
    if let data = try await coverArt.image(for: candidate, size: size) {
      return LookupImage(data: data, origin: .candidate)
    }
    try Task.checkCancellation()
    if candidate.source == .iTunes, let url = candidate.imageURL ?? candidate.thumbnailURL {
      guard let data = try await iTunesArtwork.client.data(from: url, acceptNotFound: true) else {
        return nil
      }
      return LookupImage(data: data, origin: .candidate)
    }
    guard let data = try await iTunesArtwork.artwork(matching: candidate) else { return nil }
    return LookupImage(data: data, origin: .iTunesFallback)
  }
}
