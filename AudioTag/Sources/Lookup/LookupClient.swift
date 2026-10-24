//
//  LookupClient.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2026.
//

import Foundation

/// Fetches a URL’s data. Tests record JSON fixtures behind this, so CI never opens the network.
protocol LookupTransport: Sendable {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// `URLSession`, following redirects onto HTTPS where a server still answers with HTTP, as the
/// Cover Art Archive’s images on archive.org sometimes do, which App Transport Security blocks.
final class URLSessionTransport: NSObject, LookupTransport, URLSessionTaskDelegate,
  @unchecked Sendable
{
  private var session: URLSession!

  override init() {
    super.init()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 30
    configuration.httpAdditionalHeaders = ["Accept": "application/json"]
    session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await session.data(for: request)
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
  ) async -> URLRequest? {
    var request = request
    if let url = request.url, url.scheme == "http" {
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
      components?.scheme = "https"
      request.url = components?.url ?? url
    }
    return request
  }
}

/// Waits so MusicBrainz sees at most about one request per second from this process.
actor RequestPacer {
  private var nextAllowed: ContinuousClock.Instant = .now
  private let interval: Duration

  init(interval: Duration = .seconds(1)) {
    self.interval = interval
  }

  func wait() async throws {
    let now = ContinuousClock.now
    if nextAllowed > now {
      try await Task.sleep(until: nextAllowed, clock: .continuous)
    }
    try Task.checkCancellation()
    nextAllowed = ContinuousClock.now + interval
  }
}

/// HTTP for the lookup providers: a User-Agent, MusicBrainz pacing, and errors mapped to
/// `MetadataLookupError`.
struct LookupClient: Sendable {
  var transport: any LookupTransport
  var userAgent: String
  var pacer: RequestPacer
  /// Hosts that must not be called more than once a second, as MusicBrainz requires.
  var pacedHosts: Set<String>

  init(
    transport: any LookupTransport = URLSessionTransport(),
    userAgent: String = AudioTagIdentity.userAgent,
    pacer: RequestPacer = RequestPacer(),
    pacedHosts: Set<String> = ["musicbrainz.org"]
  ) {
    self.transport = transport
    self.userAgent = userAgent
    self.pacer = pacer
    self.pacedHosts = pacedHosts
  }

  func data(from url: URL, acceptNotFound: Bool = false) async throws -> Data? {
    try Task.checkCancellation()
    if let host = url.host, pacedHosts.contains(host) {
      try await pacer.wait()
    }
    try Task.checkCancellation()
    var request = URLRequest(url: url)
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await transport.data(for: request)
    } catch is CancellationError {
      throw MetadataLookupError.cancelled
    } catch {
      throw Self.map(error)
    }
    try Task.checkCancellation()
    guard let http = response as? HTTPURLResponse else {
      throw MetadataLookupError.unreachable
    }
    if http.statusCode == 404, acceptNotFound { return nil }
    guard (200..<300).contains(http.statusCode) else {
      throw MetadataLookupError.httpStatus(http.statusCode)
    }
    return data
  }

  func data(from url: URL) async throws -> Data {
    guard let data = try await data(from: url, acceptNotFound: false) else {
      throw MetadataLookupError.httpStatus(404)
    }
    return data
  }

  private static func map(_ error: Error) -> MetadataLookupError {
    if error is CancellationError { return .cancelled }
    if let lookup = error as? MetadataLookupError { return lookup }
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
      switch nsError.code {
      case NSURLErrorCancelled:
        return .cancelled
      case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
        NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff:
        return .offline
      default:
        return .unreachable
      }
    }
    return .unreachable
  }
}
