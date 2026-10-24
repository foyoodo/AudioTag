//
//  MetadataLookupTests.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2026.
//

import Foundation
import Testing

@testable import AudioTag

enum LookupFixtures {
  static func data(_ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appending(path: "Fixtures/\(name)")
    return try Data(contentsOf: url)
  }
}

struct MapTransport: LookupTransport {
  var responses: [String: (status: Int, data: Data)]
  var requests: Lock<[URL]> = Lock([])

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    guard let url = request.url else { throw MetadataLookupError.unreachable }
    requests.mutate { $0.append(url) }
    let key = (url.host ?? "") + url.path
    let match =
      responses[key] ?? responses.first { key.hasPrefix($0.key) || $0.key.hasPrefix(key) }?.value
    guard let match,
      let response = HTTPURLResponse(
        url: url, statusCode: match.status, httpVersion: nil, headerFields: nil)
    else {
      throw MetadataLookupError.httpStatus(404)
    }
    return (match.data, response)
  }
}

final class HeaderTransport: LookupTransport, @unchecked Sendable {
  let agent = Lock<String?>(nil)

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    agent.mutate { $0 = request.value(forHTTPHeaderField: "User-Agent") }
    let url = request.url!
    let response = HTTPURLResponse(
      url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    return (try LookupFixtures.data("musicbrainz-recording-search-empty.json"), response)
  }
}

/// A small lock so the mock transport can record the URLs it was given.
final class Lock<Value>: @unchecked Sendable {
  private var value: Value
  private let lock = NSLock()

  init(_ value: Value) {
    self.value = value
  }

  func mutate(_ body: (inout Value) -> Void) {
    lock.lock()
    defer { lock.unlock() }
    body(&value)
  }

  func get() -> Value {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

@Suite("Metadata query")
struct MetadataQueryTests {
  @Test("A file name is read as artist, album and title when the tags are empty")
  func fileName() {
    let two = MetadataQuery.from(fileName: "01 Artist - Title.mp3")
    #expect(two.artist == "Artist")
    #expect(two.title == "Title")
    #expect(two.album.isEmpty)
    let three = MetadataQuery.from(fileName: "Artist - Album - Title.flac")
    #expect(three.artist == "Artist")
    #expect(three.album == "Album")
    #expect(three.title == "Title")
    let titled = MetadataQuery.from(fileName: "03. Hello.m4a")
    #expect(titled.title == "Hello")
    #expect(titled.artist.isEmpty)
    let plain = MetadataQuery.from(fileName: "song.mp3")
    #expect(plain.title == "song")
  }

  @Test("A Lucene query uses the fields that are filled in, and escapes quotes")
  func lucene() {
    let query = MetadataQuery(title: "Blow Your Mind", artist: "Dua Lipa", album: "")
    #expect(
      MusicBrainz.luceneQuery(query)
        == "recording:\"Blow Your Mind\" AND artist:\"Dua Lipa\"")
    let quoted = MetadataQuery(title: "Say \"hello\"", artist: "", album: "")
    let escaped = MusicBrainz.escape("Say \"hello\"")
    #expect(escaped == "Say \\\"hello\\\"")
    #expect(MusicBrainz.luceneQuery(quoted) == "recording:\"\(escaped)\"")
    #expect(MusicBrainz.luceneQuery(MetadataQuery(title: "", artist: "", album: "")).isEmpty)
  }

  @Test("The User-Agent names AudioTag, its version, and the project URL")
  func userAgent() {
    let agent = AudioTagIdentity.userAgent(version: "0.2.0")
    #expect(agent == "AudioTag/0.2.0 ( https://github.com/foyoodo/AudioTag )")
  }
}

@Suite("MusicBrainz JSON")
struct MusicBrainzParsingTests {
  @Test("A recorded recording search becomes candidates, preferring a matching album")
  func recordings() throws {
    let data = try LookupFixtures.data("musicbrainz-recording-search.json")
    let query = MetadataQuery(title: "Blow Your Mind (Mwah)", artist: "Dua Lipa", album: "Dua Lipa")
    let candidates = try MusicBrainz.recordings(from: data, query: query)
    #expect(candidates.count == 2)
    let first = candidates[0]
    #expect(first.title == "Blow Your Mind (Mwah)")
    #expect(first.artist == "Dua Lipa")
    #expect(first.album == "Dua Lipa")
    #expect(first.date == "2017-06-02")
    #expect(first.trackNumber == 6)
    #expect(first.trackCount == 12)
    #expect(first.duration == 178.0)
    #expect(first.genre == "electropop")
    #expect(first.source == .musicBrainz)
    #expect(first.recordingMBID == "026fa041-3917-4c73-9079-ed16e36f20f8")
    #expect(first.releaseMBID == "abbc4905-c25f-4c67-8e2d-19329ec48b1f")
    #expect(first.score == 100)
    #expect(first.thumbnailURL?.absoluteString.contains("front-250") == true)
    #expect(candidates[1].title == "New Rules")
    #expect(candidates[1].trackNumber == 10)
    #expect(candidates[1].score == 80)
  }

  @Test("An empty recording search is an empty list, not an error")
  func empty() throws {
    let data = try LookupFixtures.data("musicbrainz-recording-search-empty.json")
    #expect(try MusicBrainz.recordings(from: data).isEmpty)
  }

  @Test("JSON that isn’t a recording search is a decoding error")
  func invalid() {
    #expect(throws: MetadataLookupError.decoding) {
      try MusicBrainz.recordings(from: Data("not json".utf8))
    }
  }

  @Test("A multi-disc release uses the medium’s track total, not the release’s")
  func multiDiscTrackCount() throws {
    let data = try LookupFixtures.data("musicbrainz-recording-search-multidisc.json")
    let candidates = try MusicBrainz.recordings(from: data)
    let first = try #require(candidates.first)
    #expect(first.title == "Helter Skelter")
    #expect(first.discNumber == 2)
    #expect(first.trackNumber == 6)
    #expect(first.trackCount == 13)
  }

  @Test("A single medium without its own track count uses the release’s")
  func singleMediumReleaseTrackCount() throws {
    let json = Data(
      """
      {"recordings":[{"id":"r","title":"Song","releases":[{
        "id":"rel","title":"Album","track-count":10,
        "media":[{"position":1,"track":[{"number":"4"}]}]
      }]}]}
      """.utf8)
    let first = try #require(try MusicBrainz.recordings(from: json).first)
    #expect(first.trackCount == 10)
    #expect(first.trackNumber == 4)
  }

  @Test("A multi-disc release without per-medium totals does not use the release total")
  func multiDiscOmitsReleaseTotal() throws {
    let json = Data(
      """
      {"recordings":[{"id":"r","title":"Song","releases":[{
        "id":"rel","title":"Album","track-count":24,
        "media":[
          {"position":1},
          {"position":2,"track":[{"number":"3"}]}
        ]
      }]}]}
      """.utf8)
    let first = try #require(try MusicBrainz.recordings(from: json).first)
    #expect(first.discNumber == 2)
    #expect(first.trackNumber == 3)
    #expect(first.trackCount == nil)
  }
}

@Suite("iTunes JSON")
struct ITunesParsingTests {
  @Test("A recorded song search becomes candidates, with a larger artwork URL")
  func songs() throws {
    let data = try LookupFixtures.data("itunes-search.json")
    let songs = try ITunesSearch.songs(from: data)
    #expect(songs.count == 2)
    let first = songs[0]
    #expect(first.title == "Upside Down")
    #expect(first.artist == "Jack Johnson")
    #expect(first.album.hasPrefix("Sing-a-Longs"))
    #expect(first.trackNumber == 1)
    #expect(first.trackCount == 14)
    #expect(first.genre == "Rock")
    #expect(first.source == .iTunes)
    #expect(first.duration == TimeInterval(207_266) / 1000)
    #expect(first.date.hasPrefix("2006-02-07"))
    #expect(first.thumbnailURL?.absoluteString.contains("100x100") == true)
    #expect(first.imageURL?.absoluteString.contains("600x600") == true)
  }

  @Test("The artwork URL is enlarged from the 100-pixel thumbnail")
  func largerArtwork() {
    let url = URL(string: "https://example.com/100x100bb.jpg")!
    #expect(ITunesSearch.largerArtworkURL(url).absoluteString.contains("600x600bb"))
  }
}

@Suite("Cover Art Archive JSON")
struct CoverArtArchiveParsingTests {
  @Test("The front image is read, and HTTP is upgraded to HTTPS")
  func frontImage() throws {
    let data = try LookupFixtures.data("cover-art-archive-release.json")
    let thumbnail = try CoverArtArchive.frontImageURL(from: data, size: .thumbnail)
    #expect(thumbnail?.scheme == "https")
    #expect(thumbnail?.absoluteString.contains("829521842-250.jpg") == true)
    let full = try CoverArtArchive.frontImageURL(from: data, size: .full)
    #expect(full?.scheme == "https")
    #expect(full?.absoluteString.hasSuffix("829521842.jpg") == true)
  }

  @Test("A release MBID builds Cover Art Archive image URLs")
  func urls() {
    let url = CoverArtArchive.imageURL(
      releaseMBID: "76df3287-6cda-33eb-8e9a-044b5e15ffdd", size: .thumbnail)
    #expect(url.host == "coverartarchive.org")
    #expect(url.path.hasSuffix("/front-250"))
  }
}

@Suite("Field preview")
struct MetadataFieldChangeTests {
  @Test("Only fields the candidate has are offered, and those that differ would change")
  func changes() {
    let current: [MetadataField: String] = [
      .title: "song.mp3", .artist: "Dua Lipa", .album: "", .date: "",
    ]
    let candidate = MetadataCandidate(
      id: "test", title: "New Rules", artist: "Dua Lipa", album: "Dua Lipa",
      albumArtist: "Dua Lipa", date: "2017-06-02", trackNumber: 10, trackCount: 12,
      discNumber: 1, genre: "Pop", duration: 209, source: .musicBrainz)
    let changes = MetadataLookup.changes(current: current, candidate: candidate)
    let byField = Dictionary(uniqueKeysWithValues: changes.map { ($0.field, $0) })
    #expect(byField[.title]?.wouldChange == true)
    #expect(byField[.artist]?.wouldChange == false)
    #expect(byField[.album]?.proposed == "Dua Lipa")
    #expect(byField[.trackNumber]?.proposed == "10")
    #expect(byField[.genre]?.proposed == "Pop")
  }

  @Test("MusicBrainz genre is only pre-checked when the track has none")
  func musicBrainzGenrePreCheck() {
    let candidate = MetadataCandidate(
      id: "mb", title: "New Rules", artist: "Dua Lipa", album: "Dua Lipa",
      albumArtist: "Dua Lipa", date: "2017-06-02", trackNumber: 10, trackCount: 12,
      genre: "electropop", source: .musicBrainz)
    let withGenre = MetadataLookup.changes(
      current: [.genre: "Pop"], candidate: candidate
    ).first { $0.field == .genre }!
    #expect(withGenre.wouldChange == true)
    #expect(MetadataLookup.isCheckedByDefault(withGenre, source: .musicBrainz) == false)
    let empty = MetadataLookup.changes(
      current: [.genre: ""], candidate: candidate
    ).first { $0.field == .genre }!
    #expect(MetadataLookup.isCheckedByDefault(empty, source: .musicBrainz) == true)
  }

  @Test("iTunes genre is pre-checked when it differs from the track’s")
  func iTunesGenrePreCheck() {
    let candidate = MetadataCandidate(
      id: "itunes", title: "Upside Down", artist: "Jack Johnson", album: "Curious George",
      albumArtist: "Jack Johnson", date: "2006-02-07", trackNumber: 1, trackCount: 14,
      genre: "Rock", source: .iTunes)
    let change = MetadataLookup.changes(
      current: [.genre: "Pop"], candidate: candidate
    ).first { $0.field == .genre }!
    #expect(MetadataLookup.isCheckedByDefault(change, source: .iTunes) == true)
  }
}

@Suite("Lookup client")
struct LookupClientTests {
  @Test("MusicBrainz is searched first, and iTunes is used when it has no recordings")
  func fallback() async throws {
    let mb = try LookupFixtures.data("musicbrainz-recording-search-empty.json")
    let itunes = try LookupFixtures.data("itunes-search.json")
    let transport = MapTransport(responses: [
      "musicbrainz.org/ws/2/recording": (200, mb),
      "itunes.apple.com/search": (200, itunes),
    ])
    let client = LookupClient(
      transport: transport, userAgent: AudioTagIdentity.userAgent(version: "0.2.0"),
      pacer: RequestPacer(interval: .zero), pacedHosts: [])
    let service = MetadataLookupService(client: client)
    let results = try await service.search(
      MetadataQuery(title: "Upside Down", artist: "Jack Johnson", album: ""))
    #expect(results.contains { $0.source == .iTunes && $0.title == "Upside Down" })
    let urls = transport.requests.get().map { ($0.host ?? "") + $0.path }
    #expect(urls.contains { $0.hasPrefix("musicbrainz.org") })
    #expect(urls.contains { $0.hasPrefix("itunes.apple.com") })
  }

  @Test("A MusicBrainz hit is returned without calling iTunes")
  func musicBrainzFirst() async throws {
    let mb = try LookupFixtures.data("musicbrainz-recording-search.json")
    let transport = MapTransport(responses: [
      "musicbrainz.org/ws/2/recording": (200, mb)
    ])
    let client = LookupClient(
      transport: transport, userAgent: AudioTagIdentity.userAgent(version: "0.2.0"),
      pacer: RequestPacer(interval: .zero), pacedHosts: [])
    let service = MetadataLookupService(client: client)
    let results = try await service.search(
      MetadataQuery(title: "Blow Your Mind (Mwah)", artist: "Dua Lipa", album: ""))
    #expect(results.first?.source == .musicBrainz)
    #expect(transport.requests.get().allSatisfy { $0.host == "musicbrainz.org" })
  }

  @Test("An empty query is refused before anything is fetched")
  func emptyQuery() async {
    let transport = MapTransport(responses: [:])
    let client = LookupClient(
      transport: transport, userAgent: "AudioTag/0.2.0 ( https://github.com/foyoodo/AudioTag )",
      pacer: RequestPacer(interval: .zero), pacedHosts: [])
    let service = MetadataLookupService(client: client)
    await #expect(throws: MetadataLookupError.emptyQuery) {
      try await service.search(MetadataQuery(title: "  ", artist: "", album: ""))
    }
    #expect(transport.requests.get().isEmpty)
  }

  @Test("Cover Art Archive images are the candidate’s own cover")
  func candidateArtwork() async throws {
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
    let transport = MapTransport(responses: [
      "coverartarchive.org": (200, jpeg)
    ])
    let client = LookupClient(
      transport: transport, userAgent: AudioTagIdentity.userAgent(version: "0.2.0"),
      pacer: RequestPacer(interval: .zero), pacedHosts: [])
    let service = MetadataLookupService(client: client)
    let candidate = MetadataCandidate(
      id: "mb", title: "Song", artist: "Artist", album: "Album", albumArtist: "Artist",
      date: "2017", genre: "", source: .musicBrainz,
      releaseMBID: "abbc4905-c25f-4c67-8e2d-19329ec48b1f")
    let image = try #require(try await service.image(for: candidate, size: .full))
    #expect(image.origin == .candidate)
    #expect(image.origin.isArtworkPreChecked)
    #expect(image.origin.artworkLabel == "Artwork")
    #expect(image.data == jpeg)
  }

  @Test("iTunes artwork used when Cover Art Archive has none is a fallback, not pre-checked")
  func iTunesArtworkFallback() async throws {
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
    let itunes = try LookupFixtures.data("itunes-search.json")
    let transport = MapTransport(responses: [
      "coverartarchive.org": (404, Data()),
      "itunes.apple.com/search": (200, itunes),
      "is1-ssl.mzstatic.com": (200, jpeg),
    ])
    let client = LookupClient(
      transport: transport, userAgent: AudioTagIdentity.userAgent(version: "0.2.0"),
      pacer: RequestPacer(interval: .zero), pacedHosts: [])
    let service = MetadataLookupService(client: client)
    let candidate = MetadataCandidate(
      id: "mb", title: "Blow Your Mind (Mwah)", artist: "Dua Lipa", album: "Dua Lipa",
      albumArtist: "Dua Lipa", date: "2017", genre: "electropop", source: .musicBrainz,
      releaseMBID: "abbc4905-c25f-4c67-8e2d-19329ec48b1f",
      thumbnailURL: CoverArtArchive.imageURL(
        releaseMBID: "abbc4905-c25f-4c67-8e2d-19329ec48b1f", size: .thumbnail),
      imageURL: CoverArtArchive.imageURL(
        releaseMBID: "abbc4905-c25f-4c67-8e2d-19329ec48b1f", size: .full))
    let image = try #require(try await service.image(for: candidate, size: .full))
    #expect(image.origin == .iTunesFallback)
    #expect(!image.origin.isArtworkPreChecked)
    #expect(image.origin.artworkLabel == "Artwork (from iTunes, may not match)")
    #expect(image.data == jpeg)
  }

  @Test("The User-Agent is sent on each request")
  func userAgentHeader() async throws {
    let transport = HeaderTransport()
    let client = LookupClient(
      transport: transport, userAgent: AudioTagIdentity.userAgent(version: "0.2.0"),
      pacer: RequestPacer(interval: .zero), pacedHosts: [])
    _ = try await MusicBrainzProvider(client: client).search(
      MetadataQuery(title: "Test", artist: "", album: ""))
    #expect(transport.agent.get() == "AudioTag/0.2.0 ( https://github.com/foyoodo/AudioTag )")
  }
}

@Suite("Lookup errors")
struct LookupErrorTests {
  @Test("HTTP errors and an offline network are told of in plain language")
  func messages() {
    #expect(MetadataLookupError.offline.message.contains("network"))
    #expect(MetadataLookupError.httpStatus(503).message.contains("busy"))
    #expect(MetadataLookupError.emptyQuery.message.contains("title"))
  }
}
