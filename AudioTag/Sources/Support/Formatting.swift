//
//  Formatting.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import Foundation
import TagLib

/// TagLib's, rather than the SDK's.
typealias Picture = TagLib.Picture

extension AudioFormat {
  var name: String {
    switch self {
    case .mpeg: "MP3"
    case .flac: "FLAC"
    case .mp4: "MPEG-4"
    case .oggVorbis: "Ogg Vorbis"
    case .oggFLAC: "Ogg FLAC"
    case .opus: "Opus"
    case .speex: "Speex"
    case .ape: "Monkey’s Audio"
    case .asf: "Windows Media"
    case .musepack: "Musepack"
    case .wavPack: "WavPack"
    case .trueAudio: "TrueAudio"
    case .wav: "WAV"
    case .aiff: "AIFF"
    case .dsf: "DSF"
    case .dsdiff: "DSDIFF"
    case .matroska: "Matroska"
    case .shorten: "Shorten"
    case .mod: "ProTracker Module"
    case .s3m: "ScreamTracker III Module"
    case .it: "Impulse Tracker Module"
    case .xm: "Extended Module"
    case .unknown: "Unknown"
    }
  }
}

extension AudioProperties.Codec {
  var name: String {
    switch self {
    case .aac: "AAC"
    case .alac: "Apple Lossless"
    case .ac3: "AC-3"
    case .eac3: "E-AC-3"
    case .flac: "FLAC"
    case .dts: "DTS"
    case .opus: "Opus"
    }
  }
}

extension AudioMetadata {
  /// The format, with an MP4 file's codec, as in `MPEG-4 (AAC)`.
  var kind: String {
    guard let codec = properties?.codec else { return format.name }
    return "\(format.name) (\(codec.name))"
  }
}

enum Format {
  static func duration(_ seconds: TimeInterval) -> String {
    let seconds = Int(seconds.rounded())
    let (hours, minutes) = (seconds / 3600, seconds / 60 % 60)
    return hours > 0
      ? String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
      : String(format: "%d:%02d", minutes, seconds % 60)
  }

  static func bitrate(_ kilobits: Int) -> String {
    "\(kilobits) kbps"
  }

  static func sampleRate(_ hertz: Int) -> String {
    (Double(hertz) / 1000).formatted(.number.precision(.fractionLength(0...1))) + " kHz"
  }

  static func channels(_ count: Int) -> String {
    switch count {
    case 1: "Mono"
    case 2: "Stereo"
    default: "\(count) channels"
    }
  }

  static func bytes(_ count: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
  }
}

extension Picture.Kind {
  /// As ID3v2 names it.
  var name: String {
    switch self {
    case .other: "Other"
    case .fileIcon: "File Icon"
    case .otherFileIcon: "Other File Icon"
    case .frontCover: "Front Cover"
    case .backCover: "Back Cover"
    case .leafletPage: "Leaflet Page"
    case .media: "Media"
    case .leadArtist: "Lead Artist"
    case .artist: "Artist"
    case .conductor: "Conductor"
    case .band: "Band"
    case .composer: "Composer"
    case .lyricist: "Lyricist"
    case .recordingLocation: "Recording Location"
    case .duringRecording: "During Recording"
    case .duringPerformance: "During Performance"
    case .movieScreenCapture: "Movie Screen Capture"
    case .colouredFish: "A Bright Coloured Fish"
    case .illustration: "Illustration"
    case .bandLogo: "Band Logo"
    case .publisherLogo: "Publisher Logo"
    }
  }
}
